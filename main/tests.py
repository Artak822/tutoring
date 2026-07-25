"""Тесты REST API, которым пользуется iOS-клиент.

Главное, что здесь проверяется — скоуп по репетитору (чужие данные не видны и не
изменяемы) и то, что API даёт тот же результат, что и веб-версия, потому что оба
клиента ходят в один и тот же services.py.
"""
from datetime import date, time, timedelta
from decimal import Decimal

from django.contrib.auth.models import User
from django.urls import reverse
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from .models import Tutor, Student, StudentGroup, Lesson, Attendance, Payment


def make_tutor(username):
    user = User.objects.create_user(username=username, password='pass12345!')
    return Tutor.objects.create(user=user)


class APITestBase(APITestCase):
    def setUp(self):
        self.tutor = make_tutor('artak')
        self.other_tutor = make_tutor('someone-else')

        self.token = Token.objects.create(user=self.tutor.user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {self.token.key}')

        self.student = Student.objects.create(
            tutor=self.tutor, first_name='Иван', last_name='Петров', default_price=Decimal('1000.00')
        )
        self.other_student = Student.objects.create(
            tutor=self.other_tutor, first_name='Чужой', last_name='Ученик'
        )

        self.lesson = Lesson.objects.create(
            tutor=self.tutor, date=date(2026, 7, 20), time=time(15, 0),
            duration=60, lesson_price=Decimal('1000.00'),
        )
        self.lesson.students.set([self.student])

    def make_lesson(self, day, price=Decimal('1000.00'), students=None, tutor=None):
        lesson = Lesson.objects.create(
            tutor=tutor or self.tutor, date=day, time=time(12, 0),
            duration=60, lesson_price=price,
        )
        lesson.students.set(students if students is not None else [self.student])
        return lesson


class AuthTests(APITestCase):
    def test_login_returns_token(self):
        tutor = make_tutor('artak')
        response = self.client.post(reverse('api_login'), {
            'username': tutor.user.username, 'password': 'pass12345!',
        })
        self.assertEqual(response.status_code, 200)
        self.assertIn('token', response.data)

    def test_anonymous_request_is_rejected(self):
        response = self.client.get(reverse('api_me'))
        self.assertEqual(response.status_code, 401)

    def test_logout_deletes_token(self):
        tutor = make_tutor('artak')
        token = Token.objects.create(user=tutor.user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        response = self.client.post(reverse('api_logout'))
        self.assertEqual(response.status_code, 204)
        self.assertFalse(Token.objects.filter(user=tutor.user).exists())

        # Тем же токеном ходить больше нельзя
        self.assertEqual(self.client.get(reverse('api_me')).status_code, 401)

    def test_user_without_tutor_profile_gets_403(self):
        user = User.objects.create_user(username='no-profile', password='pass12345!')
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')
        self.assertEqual(self.client.get(reverse('api_me')).status_code, 403)


class TutorScopeTests(APITestBase):
    """Самое опасное место API: увидеть или изменить чужих учеников нельзя."""

    def test_student_list_contains_only_own_students(self):
        response = self.client.get('/api/v1/students/')
        ids = [row['id'] for row in response.data['results']]
        self.assertIn(self.student.id, ids)
        self.assertNotIn(self.other_student.id, ids)

    def test_foreign_student_detail_is_404(self):
        response = self.client.get(f'/api/v1/students/{self.other_student.id}/')
        self.assertEqual(response.status_code, 404)

    def test_foreign_lesson_quick_action_is_404(self):
        foreign_lesson = self.make_lesson(
            date(2026, 7, 21), students=[self.other_student], tutor=self.other_tutor
        )
        response = self.client.post(
            f'/api/v1/lessons/{foreign_lesson.id}/quick-action/',
            {'action': 'mark_present', 'student': self.other_student.id},
        )
        self.assertEqual(response.status_code, 404)

    def test_cannot_attach_foreign_student_to_lesson(self):
        response = self.client.post('/api/v1/lessons/', {
            'students': [self.other_student.id],
            'date': '2026-07-22', 'time': '10:00', 'duration': 60, 'lesson_price': '500.00',
        })
        self.assertEqual(response.status_code, 400)

    def test_created_lesson_belongs_to_current_tutor(self):
        response = self.client.post('/api/v1/lessons/', {
            'students': [self.student.id],
            'date': '2026-07-22', 'time': '10:00', 'duration': 60, 'lesson_price': '500.00',
        })
        self.assertEqual(response.status_code, 201)
        self.assertEqual(Lesson.objects.get(pk=response.data['id']).tutor, self.tutor)


class LessonFilterTests(APITestBase):
    def test_filter_by_date_range(self):
        self.make_lesson(date(2026, 8, 5))
        response = self.client.get('/api/v1/lessons/', {
            'date_from': '2026-07-01', 'date_to': '2026-07-31',
        })
        dates = [row['date'] for row in response.data['results']]
        self.assertEqual(dates, ['2026-07-20'])

    def test_calendar_returns_month_without_pagination(self):
        for day in range(1, 26):
            self.make_lesson(date(2026, 9, day))
        response = self.client.get('/api/v1/lessons/calendar/', {'year': 2026, 'month': 9})
        self.assertEqual(response.status_code, 200)
        # 25 занятий > PAGE_SIZE=20 — календарь обязан отдать месяц целиком
        self.assertEqual(len(response.data['lessons']), 25)
        self.assertEqual(response.data['start_date'], '2026-09-01')
        self.assertEqual(response.data['end_date'], '2026-09-30')

    def test_calendar_rejects_bad_month(self):
        response = self.client.get('/api/v1/lessons/calendar/', {'year': 2026, 'month': 13})
        self.assertEqual(response.status_code, 400)

    def test_calendar_hides_foreign_lessons(self):
        self.make_lesson(date(2026, 9, 3), students=[self.other_student], tutor=self.other_tutor)
        self.make_lesson(date(2026, 9, 4))
        response = self.client.get('/api/v1/lessons/calendar/', {'year': 2026, 'month': 9})
        self.assertEqual(len(response.data['lessons']), 1)


class QuickActionTests(APITestBase):
    def test_mark_present_without_balance_leaves_lesson_unpaid(self):
        response = self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'mark_present', 'student': self.student.id,
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['attendance_status'], 'present')
        self.assertIsNone(response.data['payment'])

    def test_mark_present_auto_pays_from_prepaid_balance(self):
        self.student.add_prepaid_balance(Decimal('1000.00'))
        response = self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'mark_present', 'student': self.student.id,
        })
        self.assertEqual(response.data['payment']['method'], 'balance')
        self.assertTrue(response.data['payment']['is_balance'])
        self.assertEqual(response.data['student_balance'], '0.00')

    def test_overpayment_goes_to_prepaid_balance(self):
        self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'mark_present', 'student': self.student.id,
        })
        response = self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'add_payment', 'student': self.student.id, 'amount': '1500', 'method': 'cash',
        })
        self.assertEqual(response.data['payment']['amount'], '1500.00')
        self.assertEqual(response.data['student_balance'], '500.00')

    def test_mark_absent_refunds_balance_payment(self):
        self.student.add_prepaid_balance(Decimal('1000.00'))
        self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'mark_present', 'student': self.student.id,
        })
        response = self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'mark_absent', 'student': self.student.id,
        })
        self.assertEqual(response.data['attendance_status'], 'absent')
        self.assertIsNone(response.data['payment'])
        self.assertEqual(response.data['student_balance'], '1000.00')

    def test_add_payment_marks_student_present(self):
        """Оплата без предварительной отметки должна сохранять посещаемость:
        ответ возвращает 'present', и state после перезагрузки обязан это подтверждать."""
        response = self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'add_payment', 'student': self.student.id, 'amount': '1000', 'method': 'cash',
        })
        self.assertEqual(response.data['attendance_status'], 'present')

        state = self.client.get(f'/api/v1/lessons/{self.lesson.id}/state/')
        self.assertEqual(state.data['students'][0]['attendance_status'], 'present')

    def test_student_not_in_lesson_is_rejected(self):
        stranger = Student.objects.create(tutor=self.tutor, first_name='Не', last_name='Назначен')
        response = self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'mark_present', 'student': stranger.id,
        })
        self.assertEqual(response.status_code, 400)

    def test_invalid_amount_is_rejected(self):
        self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'mark_present', 'student': self.student.id,
        })
        response = self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'add_payment', 'student': self.student.id, 'amount': '-5', 'method': 'cash',
        })
        self.assertEqual(response.status_code, 400)


class LessonStateTests(APITestBase):
    def test_state_returns_attendance_and_payment_per_student(self):
        second = Student.objects.create(tutor=self.tutor, first_name='Мария', last_name='Сидорова')
        self.lesson.students.add(second)
        self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'mark_present', 'student': self.student.id,
        })
        self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'add_payment', 'student': self.student.id, 'amount': '1000', 'method': 'transfer',
        })

        response = self.client.get(f'/api/v1/lessons/{self.lesson.id}/state/')
        self.assertEqual(response.status_code, 200)
        by_id = {row['student_id']: row for row in response.data['students']}

        self.assertEqual(by_id[self.student.id]['attendance_status'], 'present')
        self.assertEqual(by_id[self.student.id]['payment']['method'], 'transfer')
        self.assertIsNone(by_id[second.id]['attendance_status'])
        self.assertIsNone(by_id[second.id]['payment'])
        self.assertEqual(response.data['present_count'], 1)


class CancelLessonTests(APITestBase):
    def test_cancel_returns_balance_payment_to_student(self):
        self.student.add_prepaid_balance(Decimal('1000.00'))
        self.client.post(f'/api/v1/lessons/{self.lesson.id}/quick-action/', {
            'action': 'mark_present', 'student': self.student.id,
        })

        response = self.client.post(f'/api/v1/lessons/{self.lesson.id}/cancel/', {
            'reason': 'air_alert', 'note': 'Тревога',
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['status'], 'cancelled')

        self.student.refresh_from_db()
        self.assertEqual(self.student.prepaid_balance, Decimal('1000.00'))
        self.assertFalse(Payment.objects.filter(lesson=self.lesson).exists())

    def test_invalid_reason_is_rejected(self):
        response = self.client.post(f'/api/v1/lessons/{self.lesson.id}/cancel/', {'reason': 'потому что'})
        self.assertEqual(response.status_code, 400)

    def test_status_cannot_be_changed_through_patch(self):
        """status меняется только через /cancel/ — иначе деньги не вернутся на баланс."""
        response = self.client.patch(f'/api/v1/lessons/{self.lesson.id}/', {'status': 'cancelled'})
        self.assertEqual(response.status_code, 200)
        self.lesson.refresh_from_db()
        self.assertEqual(self.lesson.status, 'scheduled')


class RecurringLessonTests(APITestBase):
    def test_creates_weekly_lessons_for_period(self):
        response = self.client.post('/api/v1/lessons/recurring/', {
            'students': [self.student.id],
            'start_date': '2026-08-03', 'time': '16:00', 'duration': 60,
            'lesson_price': '1200.00', 'period': '1month',
        }, format='json')
        self.assertEqual(response.status_code, 201)
        # 30 дней от 3 августа — занятия 3, 10, 17, 24, 31 августа
        self.assertEqual(response.data['created_count'], 5)

        created = Lesson.objects.filter(tutor=self.tutor, date__gte=date(2026, 8, 3))
        self.assertTrue(all(l.date.weekday() == 0 for l in created))

    def test_foreign_student_is_rejected(self):
        response = self.client.post('/api/v1/lessons/recurring/', {
            'students': [self.other_student.id],
            'start_date': '2026-08-03', 'time': '16:00', 'duration': 60,
            'lesson_price': '1200.00', 'period': '1month',
        }, format='json')
        self.assertEqual(response.status_code, 400)

    def test_unknown_period_is_rejected(self):
        response = self.client.post('/api/v1/lessons/recurring/', {
            'students': [self.student.id],
            'start_date': '2026-08-03', 'time': '16:00', 'duration': 60,
            'lesson_price': '1200.00', 'period': '10years',
        }, format='json')
        self.assertEqual(response.status_code, 400)


class DebtTests(APITestBase):
    def make_debt(self, student, day, price=Decimal('1000.00')):
        lesson = self.make_lesson(day, price=price, students=[student])
        Attendance.objects.create(lesson=lesson, student=student, status='present')
        return lesson

    def test_debts_list_sorted_by_amount(self):
        poor = Student.objects.create(tutor=self.tutor, first_name='Должник', last_name='Большой')
        self.make_debt(self.student, date(2026, 7, 1))
        self.make_debt(poor, date(2026, 7, 2), price=Decimal('3000.00'))

        response = self.client.get('/api/v1/students/debts/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['total_debt'], '4000.00')
        self.assertEqual([row['id'] for row in response.data['students']], [poor.id, self.student.id])

    def test_students_without_debt_are_not_listed(self):
        response = self.client.get('/api/v1/students/debts/')
        self.assertEqual(response.data['students'], [])
        self.assertEqual(response.data['total_debt'], '0.00')

    def test_clear_debts_creates_payments(self):
        self.make_debt(self.student, date(2026, 7, 1))
        self.make_debt(self.student, date(2026, 7, 8))

        response = self.client.post(f'/api/v1/students/{self.student.id}/clear-debts/', {
            'payment_method': 'cash', 'payment_date': '2026-07-25',
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['total_debt'], '2000.00')
        self.assertEqual(response.data['payments_created'], 2)
        self.assertEqual(response.data['total_debt_left'], '0.00')

    def test_clear_debts_uses_prepaid_balance_first(self):
        self.make_debt(self.student, date(2026, 7, 1))
        self.make_debt(self.student, date(2026, 7, 8))
        self.student.add_prepaid_balance(Decimal('1000.00'))

        response = self.client.post(f'/api/v1/students/{self.student.id}/clear-debts/', {
            'payment_method': 'cash',
        })
        self.assertEqual(response.data['paid_from_balance_count'], 1)
        self.assertEqual(response.data['payments_created'], 1)
        self.assertEqual(response.data['student_balance'], '0.00')

    def test_clear_debts_without_debt_is_400(self):
        response = self.client.post(f'/api/v1/students/{self.student.id}/clear-debts/', {
            'payment_method': 'cash',
        })
        self.assertEqual(response.status_code, 400)


class StudentHistoryTests(APITestBase):
    def test_history_returns_lessons_with_attendance_and_payment(self):
        paid = self.make_lesson(date(2026, 7, 1))
        Attendance.objects.create(lesson=paid, student=self.student, status='present')
        Payment.objects.create(
            student=self.student, lesson=paid, amount=Decimal('1000.00'),
            payment_date=date(2026, 7, 1), payment_method='cash',
        )
        unpaid = self.make_lesson(date(2026, 7, 8))
        Attendance.objects.create(lesson=unpaid, student=self.student, status='present')

        response = self.client.get(f'/api/v1/students/{self.student.id}/history/')
        self.assertEqual(response.status_code, 200)

        rows = {row['lesson_id']: row for row in response.data['lessons']}
        self.assertEqual(rows[paid.id]['attendance_status'], 'present')
        self.assertEqual(rows[paid.id]['payment']['amount'], '1000.00')
        self.assertEqual(rows[unpaid.id]['attendance_status'], 'present')
        self.assertIsNone(rows[unpaid.id]['payment'])
        # Занятие из setUp без отметок тоже должно быть в истории
        self.assertIsNone(rows[self.lesson.id]['attendance_status'])

        self.assertEqual(response.data['stats']['total_lessons'], 3)
        self.assertEqual(response.data['stats']['present_lessons'], 2)
        self.assertEqual(response.data['stats']['total_debt'], '1000.00')
        self.assertEqual(response.data['stats']['total_paid'], '1000.00')

    def test_history_lessons_sorted_newest_first(self):
        self.make_lesson(date(2026, 7, 1))
        self.make_lesson(date(2026, 8, 1))

        response = self.client.get(f'/api/v1/students/{self.student.id}/history/')
        dates = [row['date'] for row in response.data['lessons']]
        self.assertEqual(dates, sorted(dates, reverse=True))

    def test_history_of_foreign_student_is_404(self):
        response = self.client.get(f'/api/v1/students/{self.other_student.id}/history/')
        self.assertEqual(response.status_code, 404)


class StudentArchiveTests(APITestBase):
    def test_archive_and_restore(self):
        response = self.client.post(f'/api/v1/students/{self.student.id}/archive/')
        self.assertEqual(response.status_code, 200)
        self.student.refresh_from_db()
        self.assertFalse(self.student.is_active)

        response = self.client.post(f'/api/v1/students/{self.student.id}/restore/')
        self.assertEqual(response.status_code, 200)
        self.student.refresh_from_db()
        self.assertTrue(self.student.is_active)

    def test_filter_by_is_active(self):
        archived = Student.objects.create(
            tutor=self.tutor, first_name='В', last_name='Архиве', is_active=False
        )
        response = self.client.get('/api/v1/students/', {'is_active': 'false'})
        self.assertEqual([row['id'] for row in response.data['results']], [archived.id])

    def test_search_by_name(self):
        Student.objects.create(tutor=self.tutor, first_name='Мария', last_name='Смирнова')
        response = self.client.get('/api/v1/students/', {'search': 'петров'})
        self.assertEqual([row['id'] for row in response.data['results']], [self.student.id])

    def test_prepaid_balance_is_read_only(self):
        response = self.client.patch(
            f'/api/v1/students/{self.student.id}/', {'prepaid_balance': '99999.00'}
        )
        self.assertEqual(response.status_code, 200)
        self.student.refresh_from_db()
        self.assertEqual(self.student.prepaid_balance, Decimal('0.00'))


class DashboardAndReportTests(APITestBase):
    def test_dashboard_counts_only_own_data(self):
        Payment.objects.create(
            student=self.student, lesson=self.lesson, amount=Decimal('1000.00'),
            payment_date=date.today(), payment_method='cash',
        )
        Payment.objects.create(
            student=self.other_student, amount=Decimal('5000.00'),
            payment_date=date.today(), payment_method='cash',
        )
        response = self.client.get(reverse('api_dashboard'))
        self.assertEqual(response.data['profit_all_time'], '1000.00')
        self.assertEqual(response.data['students_count'], 1)

    def test_profit_report_excludes_balance_payments(self):
        Payment.objects.create(
            student=self.student, lesson=self.lesson, amount=Decimal('1000.00'),
            payment_date=date(2026, 7, 20), payment_method='cash',
        )
        Payment.objects.create(
            student=self.student, amount=Decimal('700.00'), payment_date=date(2026, 7, 21),
            payment_method='balance', is_balance_payment=True,
        )
        response = self.client.get(reverse('api_profit_report'), {
            'start_date': '2026-07-01', 'end_date': '2026-07-31',
        })
        # Списание с предоплаты — не новые деньги, в прибыль не попадает
        self.assertEqual(response.data['total_profit'], '1000.00')

    def test_profit_report_swaps_reversed_dates(self):
        response = self.client.get(reverse('api_profit_report'), {
            'start_date': '2026-07-31', 'end_date': '2026-07-01',
        })
        self.assertEqual(response.data['start_date'], '2026-07-01')
        self.assertEqual(response.data['end_date'], '2026-07-31')


class MetaTests(APITestBase):
    def test_meta_exposes_reference_values(self):
        response = self.client.get(reverse('api_meta'))
        self.assertEqual(response.status_code, 200)
        self.assertIn('api_version', response.data)
        reasons = [row['value'] for row in response.data['cancellation_reasons']]
        self.assertIn('air_alert', reasons)
        methods = [row['value'] for row in response.data['payment_methods']]
        self.assertEqual(methods, ['cash', 'transfer', 'balance'])


class GroupTests(APITestBase):
    def test_group_scoped_to_tutor(self):
        StudentGroup.objects.create(tutor=self.other_tutor, name='Чужая группа')
        mine = StudentGroup.objects.create(tutor=self.tutor, name='11 класс')
        response = self.client.get('/api/v1/groups/')
        self.assertEqual([row['id'] for row in response.data['results']], [mine.id])

    def test_cannot_assign_student_to_foreign_group(self):
        foreign_group = StudentGroup.objects.create(tutor=self.other_tutor, name='Чужая')
        response = self.client.patch(
            f'/api/v1/students/{self.student.id}/', {'groups': [foreign_group.id]}
        )
        self.assertEqual(response.status_code, 400)

    def test_create_group_with_students(self):
        response = self.client.post('/api/v1/groups/', {
            'name': '11 класс', 'students': [self.student.id],
        }, format='json')
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['students'], [self.student.id])
        self.assertEqual(response.data['students_count'], 1)

        group = StudentGroup.objects.get(pk=response.data['id'])
        self.assertEqual(group.tutor_id, self.tutor.id)
        self.assertEqual(list(self.student.groups.all()), [group])

    def test_blank_name_is_built_from_student_names(self):
        second = Student.objects.create(tutor=self.tutor, first_name='Анна', last_name='Сидорова')
        response = self.client.post('/api/v1/groups/', {
            'name': '', 'students': [self.student.id, second.id],
        }, format='json')
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['name'], 'Иван, Анна')

    def test_blank_name_without_students_gets_default(self):
        response = self.client.post('/api/v1/groups/', {'name': ''}, format='json')
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['name'], 'Новая группа')

    def test_update_group_replaces_roster(self):
        second = Student.objects.create(tutor=self.tutor, first_name='Анна', last_name='Сидорова')
        group = StudentGroup.objects.create(tutor=self.tutor, name='11 класс')
        group.students.set([self.student])

        response = self.client.patch(
            f'/api/v1/groups/{group.id}/', {'students': [second.id]}, format='json'
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(list(group.students.all()), [second])
        # Название не трогали — переименования быть не должно
        self.assertEqual(response.data['name'], '11 класс')

    def test_cannot_put_foreign_student_into_group(self):
        response = self.client.post('/api/v1/groups/', {
            'name': 'Сборная', 'students': [self.other_student.id],
        }, format='json')
        self.assertEqual(response.status_code, 400)
