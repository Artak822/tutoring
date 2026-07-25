from datetime import datetime, timedelta
from decimal import Decimal

from django.db.models import Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from . import services
from .models import Student, StudentGroup, Lesson, Attendance, Payment
from .permissions import HasTutorProfile, TutorScopedViewSetMixin, TutorScopedByLessonMixin
from .serializers import (
    TutorSerializer, StudentSerializer, StudentGroupSerializer, LessonSerializer,
    AttendanceSerializer, PaymentSerializer, QuickActionSerializer, CancelLessonSerializer,
)
from .services import ServiceError


class MeView(APIView):
    """GET /api/v1/me/ — профиль текущего репетитора"""
    permission_classes = [HasTutorProfile]

    def get(self, request):
        return Response(TutorSerializer(request.user.tutor).data)


class DashboardView(APIView):
    """GET /api/v1/dashboard/ — те же цифры, что на главном дашборде веб-версии"""
    permission_classes = [HasTutorProfile]

    def get(self, request):
        tutor = request.user.tutor
        today = timezone.now().date()
        week_ago = today - timedelta(days=7)
        month_ago = today - timedelta(days=30)

        return Response({
            'students_count': tutor.get_students_count(),
            'profit_all_time': str(tutor.get_total_profit()),
            'profit_month': str(tutor.get_total_profit(start_date=month_ago)),
            'profit_week': str(tutor.get_total_profit(start_date=week_ago)),
            'lessons_all_time': tutor.get_lessons_count(),
            'lessons_month': tutor.get_lessons_count(start_date=month_ago),
            'lessons_week': tutor.get_lessons_count(start_date=week_ago),
        })


class ProfitReportView(APIView):
    """GET /api/v1/reports/profit/?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD"""
    permission_classes = [HasTutorProfile]

    def get(self, request):
        tutor = request.user.tutor
        today = timezone.now().date()
        start_date, end_date = today.replace(day=1), today

        start_date_str = request.query_params.get('start_date')
        end_date_str = request.query_params.get('end_date')
        try:
            if start_date_str:
                start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
            if end_date_str:
                end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
        except (ValueError, TypeError):
            return Response({'error': 'Неверный формат дат'}, status=400)

        if start_date > end_date:
            start_date, end_date = end_date, start_date

        payments_qs = Payment.objects.filter(
            student__tutor=tutor,
            is_balance_payment=False,
            payment_date__gte=start_date,
            payment_date__lte=end_date,
        )

        total_profit = payments_qs.aggregate(total=Sum('amount'))['total'] or Decimal('0.00')

        profit_by_method = [
            {'payment_method': row['payment_method'], 'total': str(row['total'])}
            for row in payments_qs.values('payment_method').annotate(total=Sum('amount')).order_by()
        ]
        profit_by_day = [
            {'payment_date': row['payment_date'].isoformat(), 'total': str(row['total'])}
            for row in payments_qs.values('payment_date').annotate(total=Sum('amount')).order_by('payment_date')
        ]
        profit_by_student = [
            {
                'student_id': row['student__id'],
                'first_name': row['student__first_name'],
                'last_name': row['student__last_name'],
                'total': str(row['total']),
            }
            for row in payments_qs.values('student__id', 'student__first_name', 'student__last_name')
            .annotate(total=Sum('amount')).order_by('-total')
        ]

        lessons_count = tutor.get_lessons_count(start_date=start_date, end_date=end_date)
        days_count = (end_date - start_date).days + 1
        avg_per_lesson = total_profit / lessons_count if lessons_count else Decimal('0.00')
        avg_per_day = total_profit / days_count if days_count else Decimal('0.00')

        return Response({
            'start_date': start_date.isoformat(),
            'end_date': end_date.isoformat(),
            'total_profit': str(total_profit),
            'profit_by_method': profit_by_method,
            'profit_by_day': profit_by_day,
            'profit_by_student': profit_by_student,
            'lessons_count': lessons_count,
            'avg_per_lesson': str(avg_per_lesson),
            'avg_per_day': str(avg_per_day),
            'days_count': days_count,
        })


class StudentViewSet(TutorScopedViewSetMixin, viewsets.ModelViewSet):
    queryset = Student.objects.all()
    serializer_class = StudentSerializer


class StudentGroupViewSet(TutorScopedViewSetMixin, viewsets.ModelViewSet):
    queryset = StudentGroup.objects.all()
    serializer_class = StudentGroupSerializer


class LessonViewSet(TutorScopedViewSetMixin, viewsets.ModelViewSet):
    queryset = Lesson.objects.all()
    serializer_class = LessonSerializer

    @action(detail=True, methods=['post'], url_path='quick-action')
    def quick_action(self, request, pk=None):
        """POST {action, student, amount?, method?} — зеркало quick_lesson_action из views.py"""
        lesson = self.get_object()
        serializer = QuickActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        student = get_object_or_404(Student, pk=data['student'], tutor=request.user.tutor)
        if student not in lesson.students.all():
            return Response({'error': 'Ученик не назначен на это занятие'}, status=400)

        action_name = data['action']
        try:
            if action_name == 'mark_present':
                result = services.mark_present(lesson, student)
            elif action_name == 'mark_absent':
                result = services.mark_absent(lesson, student)
            elif action_name == 'add_payment':
                amount_raw = data.get('amount') or str(lesson.lesson_price)
                method = data.get('method', 'cash')
                result = services.add_payment(lesson, student, amount_raw, method)
            else:  # reset_payment
                result = services.reset_payment(lesson, student)
        except ServiceError as e:
            return Response({'error': e.message}, status=e.status)

        return Response(result)

    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        lesson = self.get_object()
        serializer = CancelLessonSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            result = services.cancel_lesson(
                lesson,
                serializer.validated_data.get('reason', ''),
                serializer.validated_data.get('note', ''),
            )
        except ServiceError as e:
            return Response({'error': e.message}, status=e.status)
        return Response(result)

    @action(detail=True, methods=['post'])
    def restore(self, request, pk=None):
        lesson = self.get_object()
        return Response(services.restore_lesson(lesson))


class AttendanceViewSet(TutorScopedByLessonMixin, viewsets.ReadOnlyModelViewSet):
    """Только чтение — мутации идут через LessonViewSet.quick_action"""
    queryset = Attendance.objects.all()
    serializer_class = AttendanceSerializer


class PaymentViewSet(TutorScopedByLessonMixin, viewsets.ReadOnlyModelViewSet):
    """Только чтение — мутации идут через LessonViewSet.quick_action"""
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
