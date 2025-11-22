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
        payments = Payment.objects.filter(student__tutor=self)
        if start_date:
            payments = payments.filter(payment_date__gte=start_date)
        if end_date:
            payments = payments.filter(payment_date__lte=end_date)
        result = payments.aggregate(total=Sum('amount'))
        return result['total'] or Decimal('0.00')
    
    def get_lessons_count(self, start_date=None, end_date=None):
        """Количество занятий за период"""
        lessons = self.lessons.all()
        if start_date:
            lessons = lessons.filter(date__gte=start_date)
        if end_date:
            lessons = lessons.filter(date__lte=end_date)
        return lessons.count()


class Student(models.Model):
    """Модель ученика"""
    tutor = models.ForeignKey(Tutor, on_delete=models.CASCADE, related_name='students', verbose_name='Репетитор')
    first_name = models.CharField(max_length=100, verbose_name='Имя')
    last_name = models.CharField(max_length=100, verbose_name='Фамилия')
    phone = models.CharField(max_length=20, blank=True, null=True, verbose_name='Телефон')
    telegram = models.CharField(max_length=20, blank=True, null=True, verbose_name='Телеграм')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Дата создания')
    updated_at = models.DateTimeField(auto_now=True, verbose_name='Дата обновления')
    grade = models.CharField(max_length=10, blank=True, null=True, verbose_name='Класс')
    notes = models.TextField(blank=True, verbose_name='Заметки')
    is_active = models.BooleanField(default=True, verbose_name='Активен')

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
        return self.payments.aggregate(total=Sum('amount'))['total'] or Decimal('0.00')
    
    def get_total_debt(self):
        """Общий долг ученика"""
        # Суммируем стоимость всех занятий, где ученик присутствовал, но не оплатил
        total_debt = Decimal('0.00')
        for lesson in self.lessons.all():
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
    ]
    
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='payments', verbose_name='Ученик')
    lesson = models.ForeignKey(Lesson, on_delete=models.SET_NULL, null=True, blank=True, related_name='payments', verbose_name='Занятие')
    amount = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(Decimal('0.01'))], verbose_name='Сумма')
    payment_date = models.DateField(verbose_name='Дата оплаты')
    payment_method = models.CharField(max_length=20, choices=PAYMENT_METHOD_CHOICES, default='cash', verbose_name='Способ оплаты')
    notes = models.TextField(blank=True, verbose_name='Заметки')
    created_at = models.DateTimeField(auto_now_add=True, verbose_name='Дата создания')

    class Meta:
        verbose_name = 'Оплата'
        verbose_name_plural = 'Оплаты'
        ordering = ['-payment_date', '-created_at']

    def __str__(self):
        return f"{self.student} - {self.amount} руб. ({self.payment_date})"
