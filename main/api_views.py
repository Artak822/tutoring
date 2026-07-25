from calendar import monthrange
from datetime import datetime, timedelta
from decimal import Decimal

from django.db.models import Q, Sum
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
    RecurringLessonSerializer, ClearDebtsSerializer, StudentDebtSerializer,
)
from .services import ServiceError

# Версия контракта API. Клиент сверяет её при запуске и просит обновиться,
# если сервер ушёл вперёд по мажорной части.
API_VERSION = '1.0'


def _parse_date(value):
    """YYYY-MM-DD из query-параметра; мусор молча игнорируем — фильтр просто не применяется."""
    if not value:
        return None
    try:
        return datetime.strptime(value, '%Y-%m-%d').date()
    except (ValueError, TypeError):
        return None


def _search_q(term):
    """Поиск по ученику с учётом того, что SQLite не умеет регистронезависимый LIKE
    для кириллицы (ICU не собран), а PostgreSQL умеет.

    На проде хватило бы одного icontains, но локальная разработка идёт на SQLite, и
    там «петров» не нашёл бы «Петров». Поэтому перебираем варианты регистра —
    на PostgreSQL они просто дублируют друг друга и ничего не портят.
    """
    variants = {term, term.lower(), term.upper(), term.capitalize()}
    query = Q()
    for variant in variants:
        query |= (
            Q(first_name__icontains=variant)
            | Q(last_name__icontains=variant)
            | Q(phone__icontains=variant)
            | Q(telegram__icontains=variant)
        )
    return query


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
            'profit_all_time': services.money(tutor.get_total_profit()),
            'profit_month': services.money(tutor.get_total_profit(start_date=month_ago)),
            'profit_week': services.money(tutor.get_total_profit(start_date=week_ago)),
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
            {'payment_method': row['payment_method'], 'total': services.money(row['total'])}
            for row in payments_qs.values('payment_method').annotate(total=Sum('amount')).order_by()
        ]
        profit_by_day = [
            {'payment_date': row['payment_date'].isoformat(), 'total': services.money(row['total'])}
            for row in payments_qs.values('payment_date').annotate(total=Sum('amount')).order_by('payment_date')
        ]
        profit_by_student = [
            {
                'student_id': row['student__id'],
                'first_name': row['student__first_name'],
                'last_name': row['student__last_name'],
                'total': services.money(row['total']),
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
            'total_profit': services.money(total_profit),
            'profit_by_method': profit_by_method,
            'profit_by_day': profit_by_day,
            'profit_by_student': profit_by_student,
            'lessons_count': lessons_count,
            'avg_per_lesson': services.money(avg_per_lesson),
            'avg_per_day': services.money(avg_per_day),
            'days_count': days_count,
        })


class MetaView(APIView):
    """GET /api/v1/meta/ — версия API и справочники значений для клиента,
    чтобы подписи вроде «Воздушная тревога» не дублировались в коде iOS."""
    permission_classes = [HasTutorProfile]

    def get(self, request):
        return Response({
            'api_version': API_VERSION,
            'currency': '₽',
            'payment_methods': [
                {'value': v, 'label': l} for v, l in Payment.PAYMENT_METHOD_CHOICES
            ],
            'cancellation_reasons': [
                {'value': v, 'label': l} for v, l in Lesson.CANCELLATION_REASON_CHOICES
            ],
            'lesson_statuses': [
                {'value': v, 'label': l} for v, l in Lesson.STATUS_CHOICES
            ],
            'attendance_statuses': [
                {'value': v, 'label': l} for v, l in Attendance.STATUS_CHOICES
            ],
            'recurring_periods': [
                {'value': '2weeks', 'label': '2 недели'},
                {'value': '1month', 'label': '1 месяц'},
                {'value': '3months', 'label': '3 месяца'},
                {'value': '6months', 'label': '6 месяцев'},
                {'value': '1year', 'label': '1 год'},
            ],
        })


class StudentViewSet(TutorScopedViewSetMixin, viewsets.ModelViewSet):
    queryset = Student.objects.all()
    serializer_class = StudentSerializer

    def get_queryset(self):
        qs = super().get_queryset()
        params = self.request.query_params

        is_active = params.get('is_active')
        if is_active is not None:
            qs = qs.filter(is_active=is_active.lower() in ('1', 'true', 'yes'))

        group = params.get('group')
        if group:
            qs = qs.filter(groups__id=group)

        search = params.get('search', '').strip()
        if search:
            qs = qs.filter(_search_q(search))

        return qs.distinct()

    @action(detail=False, methods=['get'])
    def debts(self, request):
        """GET /api/v1/students/debts/ — активные ученики с ненулевым долгом,
        от большего к меньшему. Долг считается по тем же правилам, что в вебе."""
        rows = []
        total = Decimal('0.00')
        for student in self.get_queryset().filter(is_active=True):
            debt = student.get_total_debt()
            if debt <= 0:
                continue
            total += debt
            rows.append({
                'id': student.id,
                'first_name': student.first_name,
                'last_name': student.last_name,
                'phone': student.phone,
                'debt': services.money(debt),
                'prepaid_balance': services.money(student.prepaid_balance),
            })
        rows.sort(key=lambda r: Decimal(r['debt']), reverse=True)

        return Response({
            'total_debt': services.money(total),
            'students': StudentDebtSerializer(rows, many=True).data,
        })

    @action(detail=True, methods=['get'])
    def history(self, request, pk=None):
        """GET /api/v1/students/{id}/history/ — карточка ученика целиком:
        занятия с посещаемостью и оплатой, статистика, последние платежи.
        Собирать это на клиенте из lessons/attendances/payments — три запроса
        и своя копия правил долга, поэтому считает сервер."""
        return Response(services.student_history(self.get_object()))

    @action(detail=True, methods=['post'], url_path='clear-debts')
    def clear_debts(self, request, pk=None):
        student = self.get_object()
        serializer = ClearDebtsSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            result = services.clear_all_debts(
                student,
                serializer.validated_data['payment_method'],
                serializer.validated_data.get('payment_date') or timezone.now().date(),
                serializer.validated_data.get('notes', ''),
            )
        except ServiceError as e:
            return Response({'error': e.message}, status=e.status)
        return Response(result)

    @action(detail=True, methods=['post'])
    def archive(self, request, pk=None):
        """Мягкое удаление — ученик уходит в архив, история занятий остаётся."""
        student = self.get_object()
        student.is_active = False
        student.save(update_fields=['is_active'])
        return Response(StudentSerializer(student, context={'request': request}).data)

    @action(detail=True, methods=['post'])
    def restore(self, request, pk=None):
        student = self.get_object()
        student.is_active = True
        student.save(update_fields=['is_active'])
        return Response(StudentSerializer(student, context={'request': request}).data)


class StudentGroupViewSet(TutorScopedViewSetMixin, viewsets.ModelViewSet):
    queryset = StudentGroup.objects.all()
    serializer_class = StudentGroupSerializer


class LessonViewSet(TutorScopedViewSetMixin, viewsets.ModelViewSet):
    queryset = Lesson.objects.all()
    serializer_class = LessonSerializer

    def get_queryset(self):
        qs = super().get_queryset().prefetch_related('students')
        params = self.request.query_params

        date_from = _parse_date(params.get('date_from'))
        if date_from:
            qs = qs.filter(date__gte=date_from)

        date_to = _parse_date(params.get('date_to'))
        if date_to:
            qs = qs.filter(date__lte=date_to)

        student = params.get('student')
        if student:
            qs = qs.filter(students__id=student)

        status_param = params.get('status')
        if status_param:
            qs = qs.filter(status=status_param)

        return qs.distinct()

    @action(detail=False, methods=['get'])
    def calendar(self, request):
        """GET /api/v1/lessons/calendar/?year=&month= — занятия месяца без пагинации.
        Сетка календаря должна получать месяц одним запросом, иначе дни «мигают»."""
        today = timezone.now().date()
        try:
            year = int(request.query_params.get('year', today.year))
            month = int(request.query_params.get('month', today.month))
            if not 1 <= month <= 12:
                raise ValueError
        except (ValueError, TypeError):
            return Response({'error': 'Неверный год или месяц'}, status=400)

        start = today.replace(year=year, month=month, day=1)
        last_day = monthrange(year, month)[1]
        end = start.replace(day=last_day)

        lessons = (
            self.get_queryset()
            .filter(date__gte=start, date__lte=end)
            .order_by('date', 'time')
        )

        return Response({
            'year': year,
            'month': month,
            'start_date': start.isoformat(),
            'end_date': end.isoformat(),
            'lessons': LessonSerializer(lessons, many=True, context={'request': request}).data,
        })

    @action(detail=True, methods=['get'])
    def state(self, request, pk=None):
        """Посещаемость и оплата всех учеников занятия одним запросом."""
        return Response(services.lesson_state(self.get_object()))

    @action(detail=False, methods=['post'])
    def recurring(self, request):
        """Серия еженедельных занятий на выбранный период."""
        serializer = RecurringLessonSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        tutor = request.user.tutor
        students = list(Student.objects.filter(pk__in=data['students'], tutor=tutor))
        if len(students) != len(set(data['students'])):
            return Response({'error': 'Часть учеников не найдена'}, status=400)

        try:
            lessons = services.create_recurring_lessons(
                tutor=tutor,
                students=students,
                start_date=data['start_date'],
                time=data['time'],
                duration=data['duration'],
                lesson_price=data['lesson_price'],
                period=data['period'],
                notes=data.get('notes', ''),
            )
        except ServiceError as e:
            return Response({'error': e.message}, status=e.status)

        return Response({
            'created_count': len(lessons),
            'lessons': LessonSerializer(lessons, many=True, context={'request': request}).data,
        }, status=201)

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
