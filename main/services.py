"""Бизнес-логика посещаемости/оплаты/отмены занятия.

Вынесена из views.py, чтобы HTML-AJAX-эндпоинты и DRF API вызывали один и тот же код
и не расходились в поведении между веб- и iOS-клиентом.
"""
from decimal import Decimal, InvalidOperation

from .models import Attendance, Payment


class ServiceError(Exception):
    """Ошибка бизнес-логики. Вызывающий код (HTML-вьюха или DRF-вьюха) сам решает,
    как превратить её в HTTP-ответ."""

    def __init__(self, message, status=400):
        super().__init__(message)
        self.message = message
        self.status = status


def payment_to_dict(payment):
    if not payment:
        return None
    return {
        'amount': str(payment.amount),
        'method': payment.payment_method,
        'method_display': payment.get_payment_method_display(),
        'is_balance': payment.is_balance_payment,
    }


def _quick_action_result(lesson, student, attendance_status, payment):
    return {
        'attendance_status': attendance_status,
        'payment': payment_to_dict(payment),
        'student_balance': str(student.prepaid_balance),
        'lesson_price': str(lesson.lesson_price),
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
