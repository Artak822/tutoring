"""Бизнес-логика посещаемости/оплаты/отмены занятия.

Вынесена из views.py, чтобы HTML-AJAX-эндпоинты и DRF API вызывали один и тот же код
и не расходились в поведении между веб- и iOS-клиентом.
"""
from datetime import timedelta
from decimal import Decimal, InvalidOperation

from .models import Attendance, Lesson, Payment


class ServiceError(Exception):
    """Ошибка бизнес-логики. Вызывающий код (HTML-вьюха или DRF-вьюха) сам решает,
    как превратить её в HTTP-ответ."""

    def __init__(self, message, status=400):
        super().__init__(message)
        self.message = message
        self.status = status


def money(value):
    """Деньги в API — всегда строка с двумя знаками.

    Агрегаты Sum и Decimal('1500') из тела запроса дают «1500», поля модели — «1500.00».
    Клиенту нужен один формат, иначе сравнение сумм и кэш начинают врать.
    """
    if value is None:
        return None
    return str(Decimal(value).quantize(Decimal('0.01')))


def payment_to_dict(payment):
    if not payment:
        return None
    return {
        'amount': money(payment.amount),
        'method': payment.payment_method,
        'method_display': payment.get_payment_method_display(),
        'is_balance': payment.is_balance_payment,
    }


def _quick_action_result(lesson, student, attendance_status, payment):
    return {
        'attendance_status': attendance_status,
        'payment': payment_to_dict(payment),
        'student_balance': money(student.prepaid_balance),
        'lesson_price': money(lesson.lesson_price),
    }


def mark_present(lesson, student):
    attendance, _ = Attendance.objects.get_or_create(
        lesson=lesson, student=student, defaults={'status': 'present'}
    )
    if attendance.status != 'present':
        attendance.status = 'present'
        attendance.save()

    payment = Payment.objects.filter(lesson=lesson, student=student).first()
    if not payment and lesson.lesson_price > 0:
        payment = student.try_auto_pay_lesson(lesson)

    student.refresh_from_db()
    return _quick_action_result(lesson, student, 'present', payment)


def mark_absent(lesson, student):
    attendance = Attendance.objects.filter(lesson=lesson, student=student).first()
    if attendance:
        if attendance.status == 'present':
            student.refund_balance_payment_for_lesson(lesson)
            Payment.objects.filter(lesson=lesson, student=student).delete()
        attendance.status = 'absent'
        attendance.save()
    else:
        Attendance.objects.create(lesson=lesson, student=student, status='absent')

    student.refresh_from_db()
    return _quick_action_result(lesson, student, 'absent', None)


def add_payment(lesson, student, amount_raw, method):
    try:
        amount = Decimal(amount_raw)
        if amount <= 0:
            raise ValueError
    except (ValueError, InvalidOperation, TypeError):
        raise ServiceError('Некорректная сумма')

    if method not in ('cash', 'transfer'):
        raise ServiceError('Некорректный метод оплаты')

    if Payment.objects.filter(lesson=lesson, student=student).exists():
        raise ServiceError('Оплата уже существует')

    payment = Payment.objects.create(
        student=student,
        lesson=lesson,
        amount=amount,
        payment_date=lesson.date,
        payment_method=method,
        is_balance_payment=False,
    )

    # Оплата означает, что ученик был на занятии: ответ и так возвращает 'present',
    # но без этой записи посещаемость терялась после перезагрузки страницы.
    attendance, created = Attendance.objects.get_or_create(
        lesson=lesson, student=student, defaults={'status': 'present'}
    )
    if not created and attendance.status != 'present':
        attendance.status = 'present'
        attendance.save(update_fields=['status'])

    if amount > lesson.lesson_price:
        student.add_prepaid_balance(amount - lesson.lesson_price)

    student.auto_pay_debt_from_prepaid()
    student.refresh_from_db()
    return _quick_action_result(lesson, student, 'present', payment)


def reset_payment(lesson, student):
    payment = Payment.objects.filter(lesson=lesson, student=student).first()
    if payment:
        if payment.is_balance_payment:
            student.add_prepaid_balance(payment.amount)
        elif payment.amount > lesson.lesson_price:
            student.deduct_prepaid_balance(payment.amount - lesson.lesson_price)
        payment.delete()

    student.refresh_from_db()
    return _quick_action_result(lesson, student, 'present', None)


def cancel_lesson(lesson, reason, note):
    valid_reasons = [r[0] for r in lesson.CANCELLATION_REASON_CHOICES]
    if reason and reason not in valid_reasons:
        raise ServiceError('Некорректная причина')

    for student in lesson.students.all():
        payment = Payment.objects.filter(lesson=lesson, student=student).first()
        if payment:
            if payment.is_balance_payment:
                student.add_prepaid_balance(payment.amount)
            elif payment.amount > lesson.lesson_price:
                student.deduct_prepaid_balance(payment.amount - lesson.lesson_price)
            payment.delete()

    lesson.status = 'cancelled'
    lesson.cancellation_reason = reason
    lesson.cancellation_note = note
    lesson.save(update_fields=['status', 'cancellation_reason', 'cancellation_note'])

    reason_display = dict(lesson.CANCELLATION_REASON_CHOICES).get(reason, '')
    return {
        'status': 'cancelled',
        'reason': reason,
        'reason_display': reason_display,
        'note': note,
    }


def restore_lesson(lesson):
    lesson.status = 'scheduled'
    lesson.cancellation_reason = ''
    lesson.cancellation_note = ''
    lesson.save(update_fields=['status', 'cancellation_reason', 'cancellation_note'])
    return {'status': 'scheduled'}


def lesson_state(lesson):
    """Состояние всех учеников занятия — посещаемость + оплата.

    Веб-версия отдаёт то же самое в lesson_detail как students_state_json,
    iOS-клиент забирает это одним запросом вместо N запросов к attendances/payments.
    """
    attendances = {a.student_id: a.status for a in lesson.attendances.all()}
    payments = {p.student_id: p for p in lesson.payments.all()}

    students = []
    for student in lesson.students.all():
        students.append({
            'student_id': student.id,
            'first_name': student.first_name,
            'last_name': student.last_name,
            'attendance_status': attendances.get(student.id),
            'payment': payment_to_dict(payments.get(student.id)),
            'student_balance': money(student.prepaid_balance),
        })

    return {
        'lesson_id': lesson.id,
        'lesson_price': money(lesson.lesson_price),
        'status': lesson.status,
        'present_count': lesson.get_present_students_count(),
        'total_price': money(lesson.get_total_price()),
        'students': students,
    }


# Периоды повторяющихся занятий — те же значения, что в RecurringLessonForm
RECURRING_PERIOD_DAYS = {
    '2weeks': 14,
    '1month': 30,
    '3months': 90,
    '6months': 180,
    '1year': 365,
}


def create_recurring_lessons(tutor, students, start_date, time, duration, lesson_price, period, notes=''):
    """Еженедельные занятия в тот же день недели до конца выбранного периода."""
    if period not in RECURRING_PERIOD_DAYS:
        raise ServiceError('Некорректный период повторения')
    if not students:
        raise ServiceError('Не выбран ни один ученик')

    end_date = start_date + timedelta(days=RECURRING_PERIOD_DAYS[period])

    created = []
    current_date = start_date
    while current_date <= end_date:
        lesson = Lesson.objects.create(
            tutor=tutor,
            date=current_date,
            time=time,
            duration=duration,
            lesson_price=lesson_price,
            subject='',
            notes=notes,
        )
        lesson.students.set(students)
        created.append(lesson)
        current_date += timedelta(weeks=1)

    return created


def unpaid_lessons_for(student):
    """Занятия, где ученик присутствовал, но оплаты нет. Та же логика,
    что в Student.get_total_debt(), но возвращает сами занятия."""
    unpaid = []
    for lesson in student.lessons.filter(status='scheduled'):
        if not lesson.attendances.exists():
            continue
        attendance = Attendance.objects.filter(lesson=lesson, student=student, status='present').first()
        if not attendance:
            continue
        if Payment.objects.filter(lesson=lesson, student=student).exists():
            continue
        if lesson.lesson_price > 0:
            unpaid.append(lesson)
    unpaid.sort(key=lambda l: (l.date, l.time))
    return unpaid


def clear_all_debts(student, payment_method, payment_date, notes=''):
    """Погашение всех долгов ученика: сначала с предоплаты, остаток — указанным способом."""
    if payment_method not in ('cash', 'transfer'):
        raise ServiceError('Некорректный метод оплаты')

    unpaid = unpaid_lessons_for(student)
    if not unpaid:
        raise ServiceError('У ученика нет долгов')

    total_debt = sum((l.lesson_price for l in unpaid), Decimal('0.00'))

    paid_from_balance = student.auto_pay_debt_from_prepaid()
    balance_amount = sum((l.lesson_price for l in paid_from_balance), Decimal('0.00'))

    remaining = [l for l in unpaid if l not in paid_from_balance]
    for lesson in remaining:
        Payment.objects.create(
            student=student,
            lesson=lesson,
            amount=lesson.lesson_price,
            payment_date=payment_date,
            payment_method=payment_method,
            notes=notes,
            is_balance_payment=False,
        )
        student.update_overpayment_balance(lesson, Decimal('0.00'), lesson.lesson_price)

    student.refresh_from_db()
    return {
        'total_debt': money(total_debt),
        'paid_from_balance_count': len(paid_from_balance),
        'paid_from_balance_amount': money(balance_amount),
        'payments_created': len(remaining),
        'payments_amount': money(sum((l.lesson_price for l in remaining), Decimal('0.00'))),
        'student_balance': money(student.prepaid_balance),
        'total_debt_left': money(student.get_total_debt()),
    }


def student_history(student, payments_limit=10):
    """Карточка ученика одним запросом: занятия с отметками и оплатами, статистика,
    последние платежи.

    Веб-версия собирает то же самое в views.student_detail. Клиенту нельзя дать
    просто список занятий: посещаемость и оплата лежат в отдельных таблицах,
    и без них строка занятия не отличит «был и должен» от «не приходил».
    """
    lessons = list(student.lessons.all().order_by('-date', '-time'))
    attendances = {a.lesson_id: a.status for a in student.attendances.all()}
    payments_by_lesson = {
        p.lesson_id: p for p in student.payments.filter(lesson__isnull=False)
    }

    rows = []
    for lesson in lessons:
        rows.append({
            'lesson_id': lesson.id,
            'date': lesson.date,
            'time': lesson.time,
            'duration': lesson.duration,
            'subject': lesson.subject,
            'lesson_price': money(lesson.lesson_price),
            'status': lesson.status,
            'attendance_status': attendances.get(lesson.id),
            'payment': payment_to_dict(payments_by_lesson.get(lesson.id)),
        })

    recent = student.payments.all().order_by('-payment_date', '-id')[:payments_limit]

    return {
        'stats': {
            'total_lessons': len(lessons),
            'present_lessons': student.get_present_lessons_count(),
            'absent_lessons': student.get_absent_lessons_count(),
            'total_paid': money(student.get_total_paid()),
            'total_debt': money(student.get_total_debt()),
            'prepaid_balance': money(student.prepaid_balance),
        },
        'lessons': rows,
        'payments': [
            {
                'id': p.id,
                'lesson_id': p.lesson_id,
                'amount': money(p.amount),
                'payment_date': p.payment_date,
                'method': p.payment_method,
                'method_display': p.get_payment_method_display(),
                'is_balance': p.is_balance_payment,
                'notes': p.notes,
            }
            for p in recent
        ],
    }
