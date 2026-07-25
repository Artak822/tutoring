from rest_framework import serializers

from .models import Tutor, Student, StudentGroup, Lesson, Attendance, Payment


class TutorSerializer(serializers.ModelSerializer):
    """Только для чтения — профиль текущего репетитора (GET /api/v1/me/)."""
    username = serializers.CharField(source='user.username', read_only=True)
    first_name = serializers.CharField(source='user.first_name', read_only=True)
    last_name = serializers.CharField(source='user.last_name', read_only=True)
    students_count = serializers.SerializerMethodField()

    class Meta:
        model = Tutor
        fields = ['id', 'username', 'first_name', 'last_name', 'phone', 'created_at', 'students_count']

    def get_students_count(self, obj):
        return obj.get_students_count()


class StudentGroupSerializer(serializers.ModelSerializer):
    students_count = serializers.SerializerMethodField()

    class Meta:
        model = StudentGroup
        fields = ['id', 'name', 'description', 'is_active', 'created_at', 'updated_at', 'students_count']

    def get_students_count(self, obj):
        return obj.get_students_count()


class StudentSerializer(serializers.ModelSerializer):
    total_paid = serializers.SerializerMethodField()
    total_debt = serializers.SerializerMethodField()

    class Meta:
        model = Student
        fields = [
            'id', 'groups', 'first_name', 'last_name', 'phone', 'telegram',
            'grade', 'notes', 'is_active', 'default_price', 'prepaid_balance',
            'created_at', 'updated_at', 'total_paid', 'total_debt',
        ]
        # prepaid_balance меняется только через services.py (авто-списание/возврат),
        # напрямую через API её трогать нельзя — иначе баланс разойдётся с реальными платежами
        read_only_fields = ['prepaid_balance']

    def get_total_paid(self, obj):
        return str(obj.get_total_paid())

    def get_total_debt(self, obj):
        return str(obj.get_total_debt())

    def validate_groups(self, value):
        tutor = self.context['request'].user.tutor
        for group in value:
            if group.tutor_id != tutor.id:
                raise serializers.ValidationError('Группа не принадлежит текущему репетитору')
        return value


class LessonSerializer(serializers.ModelSerializer):
    present_students_count = serializers.SerializerMethodField()
    total_price = serializers.SerializerMethodField()
    cancellation_reason_display = serializers.CharField(source='get_cancellation_reason_display', read_only=True)

    class Meta:
        model = Lesson
        fields = [
            'id', 'students', 'date', 'time', 'duration', 'lesson_price', 'subject',
            'notes', 'status', 'cancellation_reason', 'cancellation_reason_display',
            'cancellation_note', 'created_at', 'updated_at',
            'present_students_count', 'total_price',
        ]
        # status/cancellation_* меняются только через /cancel/ и /restore/ (см. api_views.py),
        # т.к. отмена возвращает деньги на баланс — это должно идти через services.py
        read_only_fields = ['status', 'cancellation_reason', 'cancellation_note']

    def get_present_students_count(self, obj):
        return obj.get_present_students_count()

    def get_total_price(self, obj):
        return str(obj.get_total_price())

    def validate_students(self, value):
        tutor = self.context['request'].user.tutor
        for student in value:
            if student.tutor_id != tutor.id:
                raise serializers.ValidationError('Ученик не принадлежит текущему репетитору')
        return value


class AttendanceSerializer(serializers.ModelSerializer):
    """Только для чтения — отметки посещаемости меняются через quick-action на LessonViewSet."""

    class Meta:
        model = Attendance
        fields = ['id', 'lesson', 'student', 'status', 'notes', 'created_at']


class PaymentSerializer(serializers.ModelSerializer):
    """Только для чтения — платежи создаются/удаляются через quick-action на LessonViewSet,
    чтобы не расходиться с логикой предоплаты/автопогашения долгов в services.py."""

    class Meta:
        model = Payment
        fields = [
            'id', 'student', 'lesson', 'amount', 'payment_date',
            'payment_method', 'notes', 'created_at', 'is_balance_payment',
        ]


class QuickActionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['mark_present', 'mark_absent', 'add_payment', 'reset_payment'])
    student = serializers.IntegerField()
    amount = serializers.CharField(required=False, allow_blank=True)
    method = serializers.ChoiceField(choices=['cash', 'transfer'], required=False)


class CancelLessonSerializer(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True)
    note = serializers.CharField(required=False, allow_blank=True)
