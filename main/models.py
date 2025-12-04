from django.db import models
from django.db.models import Sum, Q
from django.contrib.auth.models import User
from django.urls import reverse
from django.core.validators import MinValueValidator
from decimal import Decimal
from datetime import datetime, timedelta
from django.utils import timezone


class Tutor(models.Model):
    """Модель репетитора"""
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='tutor', verbose_name='Пользователь')
    phone = models.CharField(max_length=20, blank=True, null=True, verbose_name='Телефон')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Дата создания')
    
    class Meta:
        verbose_name = 'Репетитор'
        verbose_name_plural = 'Репетиторы'
    
    def __str__(self):
        return f"{self.user.get_full_name() or self.user.username}"
    
    def get_students_count(self):
        """Количество учеников"""
        return self.students.filter(is_active=True).count()
    
    def get_total_profit(self, start_date=None, end_date=None):
        """Общая прибыль за период"""
        payments = Payment.objects.filter(student__tutor=self, is_balance_payment=False)
        if start_date:
            payments = payments.filter(payment_date__gte=start_date)
        if end_date:
            payments = payments.filter(payment_date__lte=end_date)
        result = payments.aggregate(total=Sum('amount'))
        return result['total'] or Decimal('0.00')
    
    def get_lessons_count(self, start_date=None, end_date=None):
        """Количество прошедших занятий за период (только с отметками посещаемости)"""
        # Получаем все занятия, у которых есть хотя бы одна отметка посещаемости
        # Занятие считается прошедшим только если есть хотя бы одна отметка посещаемости
        lessons = self.lessons.filter(attendances__isnull=False).distinct()
        
        if start_date:
            lessons = lessons.filter(date__gte=start_date)
        if end_date:
            lessons = lessons.filter(date__lte=end_date)
        return lessons.count()


class StudentGroup(models.Model):
    """Модель группы учеников"""
    tutor = models.ForeignKey(Tutor, on_delete=models.CASCADE, related_name='groups', verbose_name='Репетитор')
    name = models.CharField(max_length=200, verbose_name='Название группы')
    description = models.TextField(blank=True, verbose_name='Описание')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Дата создания')
    updated_at = models.DateTimeField(auto_now=True, verbose_name='Дата обновления')
    is_active = models.BooleanField(default=True, verbose_name='Активна')
    
    class Meta:
        verbose_name = 'Группа учеников'
        verbose_name_plural = 'Группы учеников'
        ordering = ['name']
    
    def __str__(self):
        return self.name
    
    def get_students_count(self):
        """Количество учеников в группе"""
        return self.students.filter(is_active=True).count()


class Student(models.Model):
    """Модель ученика"""
    tutor = models.ForeignKey(Tutor, on_delete=models.CASCADE, related_name='students', verbose_name='Репетитор')
    groups = models.ManyToManyField(StudentGroup, related_name='students', blank=True, verbose_name='Группы')
    first_name = models.CharField(max_length=100, verbose_name='Имя')
    last_name = models.CharField(max_length=100, verbose_name='Фамилия')
    phone = models.CharField(max_length=20, blank=True, null=True, verbose_name='Телефон')
    telegram = models.CharField(max_length=20, blank=True, null=True, verbose_name='Телеграм')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Дата создания')
    updated_at = models.DateTimeField(auto_now=True, verbose_name='Дата обновления')
    grade = models.CharField(max_length=10, blank=True, null=True, verbose_name='Класс')
    notes = models.TextField(blank=True, verbose_name='Заметки')
    is_active = models.BooleanField(default=True, verbose_name='Активен')
    prepaid_balance = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=Decimal('0.00'),
        verbose_name='Баланс предоплаты'
    )

    class Meta:
        verbose_name = 'Ученик'
        verbose_name_plural = 'Ученики'
        ordering = ['last_name', 'first_name']

    def __str__(self):
        return f"{self.last_name} {self.first_name}"

    def get_absolute_url(self):
        return reverse('student_detail', kwargs={'pk': self.pk})
    
    def get_total_paid(self):
        """Общая сумма всех оплат ученика"""
        payments = self.payments.filter(is_balance_payment=False)
        return payments.aggregate(total=Sum('amount'))['total'] or Decimal('0.00')
    
    def get_total_debt(self):
        """Общий долг ученика (только за занятия с отметками посещаемости)"""
        # Суммируем стоимость всех занятий, где ученик присутствовал, но не оплатил
        # Занятие считается прошедшим только если есть хотя бы одна отметка посещаемости
        total_debt = Decimal('0.00')
        
        for lesson in self.lessons.all():
            # Проверяем, что у занятия есть хотя бы одна отметка посещаемости
            # Если нет ни одной отметки - занятие не было проведено
            if not lesson.attendances.exists():
                continue  # Пропускаем занятия без отметок посещаемости
            
            # Проверяем, присутствовал ли ученик на занятии
            attendance = Attendance.objects.filter(lesson=lesson, student=self, status='present').first()
            if attendance:
                # Проверяем, оплатил ли он это занятие
                payment = Payment.objects.filter(lesson=lesson, student=self).first()
                if not payment and lesson.lesson_price > 0:
                    total_debt += lesson.lesson_price
        return total_debt
    
    def get_total_lessons_count(self):
        """Общее количество назначенных занятий"""
        return self.lessons.count()
    
    def get_absent_lessons_count(self):
        """Количество пропущенных занятий"""
        return self.attendances.filter(status='absent').count()
    
    def get_present_lessons_count(self):
        """Количество посещенных занятий"""
        return self.attendances.filter(status='present').count()
    
    def add_prepaid_balance(self, amount: Decimal):
        """Пополнение баланса предоплаты"""
        if amount <= 0:
            return
        self.prepaid_balance = (self.prepaid_balance or Decimal('0.00')) + amount
        self.save(update_fields=['prepaid_balance'])
    
    def deduct_prepaid_balance(self, amount: Decimal):
        """Списание средств с баланса предоплаты"""
        if amount <= 0:
            return
        new_balance = (self.prepaid_balance or Decimal('0.00')) - amount
        if new_balance < 0:
            new_balance = Decimal('0.00')
        self.prepaid_balance = new_balance
        self.save(update_fields=['prepaid_balance'])
    
    def update_overpayment_balance(self, lesson, previous_amount: Decimal, new_amount: Decimal):
        """Корректировка баланса при переплате за конкретное занятие"""
        if not lesson or lesson.lesson_price is None:
            return
        lesson_cost = lesson.lesson_price or Decimal('0.00')
        prev_overpay = max((previous_amount or Decimal('0.00')) - lesson_cost, Decimal('0.00'))
        new_overpay = max((new_amount or Decimal('0.00')) - lesson_cost, Decimal('0.00'))
        delta = new_overpay - prev_overpay
        if delta == 0:
            return
        if delta > 0:
            self.add_prepaid_balance(delta)
        else:
            self.deduct_prepaid_balance(abs(delta))
    
    def refund_balance_payment_for_lesson(self, lesson):
        """Возвращает на баланс оплату, которая была списана автоматически"""
        if not lesson:
            return False
        payment = Payment.objects.filter(
            lesson=lesson,
            student=self,
            is_balance_payment=True
        ).first()
        if not payment:
            return False
        self.add_prepaid_balance(payment.amount)
        payment.delete()
        return True
    
    def try_auto_pay_lesson(self, lesson):
        """Автоматически списывает предоплату для занятия, если средств достаточно"""
        if not lesson or lesson.lesson_price <= 0:
            return None
        if self.prepaid_balance < lesson.lesson_price:
            return None
        existing_payment = Payment.objects.filter(lesson=lesson, student=self).first()
        if existing_payment:
            return None
        payment = Payment.objects.create(
            student=self,
            lesson=lesson,
            amount=lesson.lesson_price,
            payment_date=lesson.date,
            payment_method='balance',
            is_balance_payment=True,
            notes='Автоматическая оплата с предоплаты'
        )
        self.deduct_prepaid_balance(lesson.lesson_price)
        return payment
    
    def auto_pay_debt_from_prepaid(self):
        """Автоматически погашает долг с предоплаты (старые долги в первую очередь)"""
        if self.prepaid_balance <= 0:
            return []
        
        # Находим все занятия с долгом (присутствовал, но не оплатил)
        unpaid_lessons = []
        for lesson in self.lessons.all():
            # Проверяем, что у занятия есть хотя бы одна отметка посещаемости
            if not lesson.attendances.exists():
                continue
            
            # Проверяем, присутствовал ли ученик на занятии
            attendance = Attendance.objects.filter(lesson=lesson, student=self, status='present').first()
            if attendance:
                # Проверяем, оплатил ли он это занятие
                payment = Payment.objects.filter(lesson=lesson, student=self).first()
                if not payment and lesson.lesson_price > 0:
                    unpaid_lessons.append(lesson)
        
        # Сортируем по дате (старые долги в первую очередь)
        unpaid_lessons.sort(key=lambda l: (l.date, l.time))
        
        # Погашаем долги, пока есть средства на предоплате
        paid_lessons = []
        remaining_balance = self.prepaid_balance
        
        for lesson in unpaid_lessons:
            if remaining_balance >= lesson.lesson_price:
                # Создаем платеж с предоплаты
                payment = Payment.objects.create(
                    student=self,
                    lesson=lesson,
                    amount=lesson.lesson_price,
                    payment_date=lesson.date,
                    payment_method='balance',
                    is_balance_payment=True,
                    notes='Автоматическое погашение долга с предоплаты'
                )
                remaining_balance -= lesson.lesson_price
                paid_lessons.append(lesson)
            else:
                # Недостаточно средств для полного погашения этого долга
                break
        
        # Обновляем баланс предоплаты
        if paid_lessons:
            total_deducted = sum(lesson.lesson_price for lesson in paid_lessons)
            self.deduct_prepaid_balance(total_deducted)
        
        return paid_lessons


class Lesson(models.Model):
    """Модель занятия"""
    tutor = models.ForeignKey(Tutor, on_delete=models.CASCADE, related_name='lessons', verbose_name='Репетитор')
    students = models.ManyToManyField(Student, related_name='lessons', verbose_name='Ученики')
    date = models.DateField(verbose_name='Дата')
    time = models.TimeField(verbose_name='Время')
    duration = models.IntegerField(default=60, validators=[MinValueValidator(1)], verbose_name='Длительность (минуты)')
    lesson_price = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal('0.00'), validators=[MinValueValidator(Decimal('0.00'))], verbose_name='Стоимость занятия (за одного ученика)')
    subject = models.CharField(max_length=200, blank=True, verbose_name='Предмет/Тема')
    notes = models.TextField(blank=True, verbose_name='Заметки')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Дата создания')
    updated_at = models.DateTimeField(auto_now=True, verbose_name='Дата обновления')
    
    def get_present_students_count(self):
        """Количество учеников, которые присутствовали"""
        return self.attendances.filter(status='present').count()
    
    def get_total_price(self):
        """Общая стоимость занятия (цена * количество пришедших)"""
        present_count = self.get_present_students_count()
        return self.lesson_price * present_count if present_count > 0 else Decimal('0.00')

    class Meta:
        verbose_name = 'Занятие'
        verbose_name_plural = 'Занятия'
        ordering = ['-date', '-time']

    def __str__(self):
        students_list = ", ".join([str(s) for s in self.students.all()])
        if len(students_list) > 50:
            students_list = students_list[:47] + "..."
        return f"{students_list} - {self.date} {self.time}"

    def get_absolute_url(self):
        return reverse('lesson_detail', kwargs={'pk': self.pk})


class Attendance(models.Model):
    """Модель посещаемости"""
    STATUS_CHOICES = [
        ('present', 'Присутствовал'),
        ('absent', 'Отсутствовал'),
    ]
    
    lesson = models.ForeignKey(Lesson, on_delete=models.CASCADE, related_name='attendances', verbose_name='Занятие')
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='attendances', verbose_name='Ученик')
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='present', verbose_name='Статус')
    notes = models.TextField(blank=True, verbose_name='Заметки')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Дата создания')

    class Meta:
        verbose_name = 'Посещаемость'
        verbose_name_plural = 'Посещаемость'
        unique_together = ['lesson', 'student']
        ordering = ['-lesson__date', '-lesson__time']

    def __str__(self):
        return f"{self.student} - {self.lesson.date} ({self.get_status_display()})"


class Payment(models.Model):
    """Модель оплаты"""
    PAYMENT_METHOD_CHOICES = [
        ('cash', 'Наличные'),
        ('transfer', 'Перевод'),
        ('balance', 'Списано с предоплаты'),
    ]
    
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='payments', verbose_name='Ученик')
    lesson = models.ForeignKey(Lesson, on_delete=models.SET_NULL, null=True, blank=True, related_name='payments', verbose_name='Занятие')
    amount = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(Decimal('0.01'))], verbose_name='Сумма')
    payment_date = models.DateField(verbose_name='Дата оплаты')
    payment_method = models.CharField(max_length=20, choices=PAYMENT_METHOD_CHOICES, default='cash', verbose_name='Способ оплаты')
    notes = models.TextField(blank=True, verbose_name='Заметки')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Дата создания')
    is_balance_payment = models.BooleanField(default=False, verbose_name='Оплата с предоплаты')

    class Meta:
        verbose_name = 'Оплата'
        verbose_name_plural = 'Оплаты'
        ordering = ['-payment_date', '-created_at']

    def __str__(self):
        method = self.get_payment_method_display()
        return f"{self.student} - {self.amount} руб. ({self.payment_date}, {method})"
