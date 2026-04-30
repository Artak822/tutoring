from django.shortcuts import render, get_object_or_404, redirect
from django.contrib import messages
from django.contrib.auth import login, authenticate
from django.contrib.auth.decorators import login_required
from django.contrib.auth.views import LoginView
from django.urls import reverse
from django.utils import timezone
from django.db.models import Q, Sum
from datetime import datetime, timedelta
from calendar import monthrange
from decimal import Decimal, InvalidOperation
from .models import Student, Lesson, Attendance, Payment, Tutor, StudentGroup
from .forms import StudentForm, LessonForm, AttendanceForm, PaymentForm, TutorRegistrationForm, ClearAllDebtsForm, RecurringLessonForm, StudentGroupForm


def get_tutor(request):
    """Получить репетитора для текущего пользователя"""
    if request.user.is_authenticated:
        try:
            return request.user.tutor
        except Tutor.DoesNotExist:
            return None
    return None


@login_required
def student_list(request):
    """Список всех учеников"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    students = Student.objects.filter(tutor=tutor, is_active=True)
    students_count = students.count()
    return render(request, 'main/student_list.html', {
        'students': students,
        'students_count': students_count
    })


@login_required
def student_detail(request, pk):
    """Детальная информация об ученике"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    student = get_object_or_404(Student, pk=pk, tutor=tutor)
    
    # Получаем все занятия ученика с информацией о посещаемости и оплате
    all_lessons = Lesson.objects.filter(tutor=tutor, students=student).order_by('-date', '-time')
    lessons_data = []
    for lesson in all_lessons:
        attendance = Attendance.objects.filter(lesson=lesson, student=student).first()
        payment = Payment.objects.filter(lesson=lesson, student=student).first()
        
        # Определяем статус посещения
        attendance_status = None
        if attendance:
            attendance_status = attendance.status  # 'present' или 'absent'
        
        # Определяем статус оплаты
        payment_status = None
        if payment:
            payment_status = 'paid'
        elif attendance and attendance.status == 'present' and lesson.lesson_price > 0:
            payment_status = 'unpaid'
        
        lessons_data.append({
            'lesson': lesson,
            'attendance': attendance,
            'attendance_status': attendance_status,
            'payment': payment,
            'payment_status': payment_status,
            'payment_from_balance': payment.is_balance_payment if payment else False,
        })
    
    payments = Payment.objects.filter(student=student).order_by('-payment_date')[:10]
    
    # Статистика
    total_paid = student.get_total_paid()
    total_debt = student.get_total_debt()
    total_lessons = student.get_total_lessons_count()
    absent_lessons = student.get_absent_lessons_count()
    present_lessons = student.get_present_lessons_count()
    
    return render(request, 'main/student_detail.html', {
        'student': student,
        'lessons_data': lessons_data,
        'payments': payments,
        'total_paid': total_paid,
        'total_debt': total_debt,
        'total_lessons': total_lessons,
        'absent_lessons': absent_lessons,
        'present_lessons': present_lessons,
        'prepaid_balance': student.prepaid_balance,
    })


@login_required
def student_create(request):
    """Создание нового ученика"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    if request.method == 'POST':
        form = StudentForm(request.POST)
        if form.is_valid():
            student = form.save(commit=False)
            student.tutor = tutor
            student.save()
            messages.success(request, f'Ученик {student} успешно создан.')
            return redirect('student_detail', pk=student.pk)
    else:
        form = StudentForm()
    return render(request, 'main/student_form.html', {
        'form': form,
        'title': 'Создать ученика'
    })


@login_required
def student_edit(request, pk):
    """Редактирование ученика"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    student = get_object_or_404(Student, pk=pk, tutor=tutor)
    if request.method == 'POST':
        form = StudentForm(request.POST, instance=student)
        if form.is_valid():
            student = form.save()
            messages.success(request, f'Ученик {student} успешно обновлен.')
            return redirect('student_detail', pk=student.pk)
    else:
        form = StudentForm(instance=student)
    return render(request, 'main/student_form.html', {
        'form': form,
        'student': student,
        'title': 'Редактировать ученика'
    })


@login_required
def student_delete(request, pk):
    """Архивирование ученика (мягкое удаление)"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    student = get_object_or_404(Student, pk=pk, tutor=tutor)
    if request.method == 'POST':
        student.is_active = False
        student.save(update_fields=['is_active'])
        messages.success(request, f'Ученик {student} перемещён в архив.')
        return redirect('student_list')
    return render(request, 'main/student_confirm_delete.html', {'student': student})


@login_required
def student_archive(request):
    """Список архивных учеников"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    students = Student.objects.filter(tutor=tutor, is_active=False)
    return render(request, 'main/student_archive.html', {'students': students})


@login_required
def student_restore(request, pk):
    """Восстановление ученика из архива"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    student = get_object_or_404(Student, pk=pk, tutor=tutor, is_active=False)
    if request.method == 'POST':
        student.is_active = True
        student.save(update_fields=['is_active'])
        messages.success(request, f'Ученик {student} восстановлен.')
        return redirect('student_archive')
    return render(request, 'main/student_confirm_restore.html', {'student': student})


@login_required
def calendar_view(request):
    """Календарь с занятиями"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    # Получаем год и месяц из параметров или используем текущие
    now = timezone.now()
    try:
        year = int(request.GET.get('year', now.year))
        month = int(request.GET.get('month', now.month))
    except (ValueError, TypeError):
        year = now.year
        month = now.month
    
    today = now.date()

    # ── Мобильная неделя: параметр ?week=YYYY-MM-DD (понедельник) ──
    from datetime import timedelta as _td
    week_param = request.GET.get('week')
    try:
        mobile_monday = datetime.strptime(week_param, '%Y-%m-%d').date()
        # Приводим к понедельнику на случай если передали другой день
        mobile_monday -= _td(days=mobile_monday.weekday())
    except (TypeError, ValueError):
        # По умолчанию — понедельник текущей недели
        mobile_monday = today - _td(days=today.weekday())

    mobile_sunday = mobile_monday + _td(days=6)
    prev_week_monday = mobile_monday - _td(days=7)
    next_week_monday = mobile_monday + _td(days=7)

    # Занятия для мобильного вида (7 дней, любой месяц)
    mobile_lessons = Lesson.objects.filter(
        tutor=tutor, date__gte=mobile_monday, date__lte=mobile_sunday
    ).order_by('date', 'time')
    mobile_lessons_by_date = {}
    for lesson in mobile_lessons:
        dk = lesson.date.strftime('%Y-%m-%d')
        mobile_lessons_by_date.setdefault(dk, []).append(lesson)

    weekday_names = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье']
    current_week = []
    for i in range(7):
        d = mobile_monday + _td(days=i)
        current_week.append({
            'date': d,
            'lessons': mobile_lessons_by_date.get(d.strftime('%Y-%m-%d'), []),
            'weekday_name': weekday_names[d.weekday()],
        })

    # ── Десктопный месячный вид ──
    if month == 1:
        prev_month, prev_year = 12, year - 1
    else:
        prev_month, prev_year = month - 1, year

    if month == 12:
        next_month, next_year = 1, year + 1
    else:
        next_month, next_year = month + 1, year

    first_day = datetime(year, month, 1).date()
    last_day_num = monthrange(year, month)[1]
    last_day = datetime(year, month, last_day_num).date()

    desktop_lessons = Lesson.objects.filter(
        tutor=tutor, date__gte=first_day, date__lte=last_day
    ).order_by('date', 'time')
    lessons_by_date = {}
    for lesson in desktop_lessons:
        dk = lesson.date.strftime('%Y-%m-%d')
        lessons_by_date.setdefault(dk, []).append(lesson)

    first_weekday = first_day.weekday()
    calendar_days = [None] * first_weekday
    for day in range(1, last_day_num + 1):
        d = datetime(year, month, day).date()
        calendar_days.append({
            'date': d,
            'lessons': lessons_by_date.get(d.strftime('%Y-%m-%d'), []),
            'weekday_name': weekday_names[d.weekday()],
        })

    weeks = []
    week = []
    for day in calendar_days:
        week.append(day)
        if len(week) == 7:
            weeks.append(week)
            week = []
    if week:
        while len(week) < 7:
            week.append(None)
        weeks.append(week)

    month_names = ['', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
                   'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь']

    return render(request, 'main/calendar.html', {
        'weeks': weeks,
        'current_week': current_week,
        'mobile_monday': mobile_monday,
        'mobile_sunday': mobile_sunday,
        'prev_week_monday': prev_week_monday,
        'next_week_monday': next_week_monday,
        'year': year,
        'month': month,
        'month_name': month_names[month],
        'prev_year': prev_year,
        'prev_month': prev_month,
        'next_year': next_year,
        'next_month': next_month,
        'today': today,
    })


@login_required
def lesson_list(request):
    """Список всех занятий"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    lessons = Lesson.objects.filter(tutor=tutor).order_by('-date', '-time')
    return render(request, 'main/lesson_list.html', {'lessons': lessons})


@login_required
def lesson_detail(request, pk):
    """Детальная информация о занятии"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    lesson = get_object_or_404(Lesson, pk=pk, tutor=tutor)
    attendances = Attendance.objects.filter(lesson=lesson)
    payments = Payment.objects.filter(lesson=lesson)
    
    # Создаем словарь для быстрого доступа к посещаемости и оплатам по ученику
    attendance_dict = {att.student.pk: att for att in attendances}
    payment_dict = {pay.student.pk: pay for pay in payments}
    
    # Для каждого ученика на занятии создаем информацию
    students_data = []
    for student in lesson.students.all():
        attendance = attendance_dict.get(student.pk)
        payment = payment_dict.get(student.pk)
        
        # Проверяем, была ли списана сумма с предоплаты на долги при создании этого платежа
        debt_paid_amount = None
        if payment:
            session_key = f'debt_paid_{pk}_{student.pk}'
            if session_key in request.session:
                try:
                    debt_paid_amount = Decimal(request.session[session_key])
                    # Удаляем из сессии после использования
                    del request.session[session_key]
                except (ValueError, InvalidOperation):
                    pass
        
        students_data.append({
            'student': student,
            'attendance': attendance,
            'payment': payment,
            'has_debt': attendance and attendance.status == 'present' and not payment and lesson.lesson_price > 0,
            'debt_paid_amount': debt_paid_amount
        })
    
    return render(request, 'main/lesson_detail.html', {
        'lesson': lesson,
        'students_data': students_data,
        'attendances': attendances,
        'payments': payments,
        'total_price': lesson.get_total_price(),
        'present_count': lesson.get_present_students_count(),
    })


@login_required
def lesson_create(request):
    """Создание нового занятия"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    
    # Получаем дату из GET параметра, если есть
    initial_date = request.GET.get('date', None)
    
    if request.method == 'POST':
        form = LessonForm(request.POST, tutor=tutor)
        if form.is_valid():
            lesson = form.save(commit=False)
            lesson.tutor = tutor
            lesson.save()
            form.save_m2m()  # Сохраняем ManyToMany связи
            messages.success(request, f'Занятие успешно создано.')
            return redirect('lesson_detail', pk=lesson.pk)
    else:
        form = LessonForm(tutor=tutor, initial_date=initial_date)
    return render(request, 'main/lesson_form.html', {
        'form': form,
        'title': 'Создать занятие'
    })


@login_required
def lesson_edit(request, pk):
    """Редактирование занятия"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    lesson = get_object_or_404(Lesson, pk=pk, tutor=tutor)
    if request.method == 'POST':
        form = LessonForm(request.POST, instance=lesson, tutor=tutor)
        if form.is_valid():
            lesson = form.save()
            messages.success(request, f'Занятие успешно обновлено.')
            return redirect('lesson_detail', pk=lesson.pk)
    else:
        form = LessonForm(instance=lesson, tutor=tutor)
    return render(request, 'main/lesson_form.html', {
        'form': form,
        'lesson': lesson,
        'title': 'Редактировать занятие'
    })


@login_required
def lesson_delete(request, pk):
    """Удаление занятия"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    lesson = get_object_or_404(Lesson, pk=pk, tutor=tutor)
    if request.method == 'POST':
        lesson_date = lesson.date
        lesson.delete()
        messages.success(request, f'Занятие от {lesson_date} успешно удалено.')
        return redirect('calendar')
    return render(request, 'main/lesson_confirm_delete.html', {'lesson': lesson})


@login_required
def mark_attendance(request, lesson_pk, student_pk):
    """Отметка посещаемости для ученика на занятии"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    lesson = get_object_or_404(Lesson, pk=lesson_pk, tutor=tutor)
    student = get_object_or_404(Student, pk=student_pk, tutor=tutor)
    
    # Проверяем, что ученик назначен на это занятие
    if student not in lesson.students.all():
        messages.error(request, 'Этот ученик не назначен на данное занятие.')
        return redirect('lesson_detail', pk=lesson_pk)
    
    # Проверяем, существует ли уже запись о посещаемости
    try:
        attendance = Attendance.objects.get(lesson=lesson, student=student)
        is_new = False
    except Attendance.DoesNotExist:
        attendance = None
        is_new = True
    
    if request.method == 'POST':
        if is_new:
            # Создаем новую запись
            form = AttendanceForm(request.POST)
            if form.is_valid():
                attendance = form.save(commit=False)
                attendance.lesson = lesson
                attendance.student = student
                attendance.save()
                if attendance.status == 'present':
                    student.try_auto_pay_lesson(lesson)
                elif attendance.status == 'absent':
                    # Если сразу ставим "отсутствовал", удаляем все оплаты за это занятие
                    payments_to_delete = Payment.objects.filter(lesson=lesson, student=student)
                    if payments_to_delete.exists():
                        payments_to_delete.delete()
                        messages.info(request, f'Оплаты за занятие удалены, так как ученик отсутствовал.')
                messages.success(request, f'Посещаемость для {student} отмечена.')
                return redirect('lesson_detail', pk=lesson_pk)
        else:
            # Обновляем существующую
            previous_status = attendance.status
            form = AttendanceForm(request.POST, instance=attendance)
            if form.is_valid():
                updated_attendance = form.save()
                if updated_attendance.status == 'present':
                    student.try_auto_pay_lesson(lesson)
                elif previous_status == 'present' and updated_attendance.status != 'present':
                    # Если статус изменился с "присутствовал" на "отсутствовал", удаляем все оплаты
                    student.refund_balance_payment_for_lesson(lesson)
                    # Удаляем все оплаты за это занятие
                    payments_to_delete = Payment.objects.filter(lesson=lesson, student=student)
                    if payments_to_delete.exists():
                        payments_to_delete.delete()
                        messages.info(request, f'Оплаты за занятие удалены, так как ученик отсутствовал.')
                messages.success(request, f'Посещаемость для {student} обновлена.')
                return redirect('lesson_detail', pk=lesson_pk)
    else:
        if is_new:
            # Для новой записи создаем форму без instance
            form = AttendanceForm(initial={'status': 'present'})
        else:
            # Для существующей показываем текущие данные
            form = AttendanceForm(instance=attendance)
    
    return render(request, 'main/mark_attendance.html', {
        'form': form,
        'lesson': lesson,
        'student': student,
        'attendance': attendance,
        'is_new': is_new
    })


@login_required
def mark_payment(request, lesson_pk, student_pk):
    """Отметка оплаты для ученика за занятие"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    lesson = get_object_or_404(Lesson, pk=lesson_pk, tutor=tutor)
    student = get_object_or_404(Student, pk=student_pk, tutor=tutor)
    
    # Проверяем, что ученик назначен на это занятие
    if student not in lesson.students.all():
        messages.error(request, 'Этот ученик не назначен на данное занятие.')
        return redirect('lesson_detail', pk=lesson_pk)
    
    # Проверяем, присутствовал ли ученик
    attendance = Attendance.objects.filter(lesson=lesson, student=student, status='present').first()
    if not attendance:
        messages.warning(request, 'Ученик не присутствовал на занятии.')
    
    # Проверяем, есть ли уже оплата (до обработки POST, чтобы обновить существующую)
    existing_payment = Payment.objects.filter(lesson=lesson, student=student).first()
    
    if request.method == 'POST':
        # Проверяем сумму до валидации формы
        try:
            amount_value = Decimal(request.POST.get('amount', '0') or '0')
        except (ValueError, InvalidOperation):
            amount_value = Decimal('0')
        
        # Если сумма равна 0
        if amount_value == 0:
            if existing_payment:
                # Если есть существующая оплата, удаляем её
                previous_amount = existing_payment.amount
                was_balance_payment = existing_payment.is_balance_payment
                # Возвращаем баланс, если оплата была списана с предоплаты
                if was_balance_payment:
                    student.add_prepaid_balance(previous_amount)
                # Обновляем баланс переплаты
                student.update_overpayment_balance(lesson, previous_amount, Decimal('0.00'))
                # Удаляем оплату
                existing_payment.delete()
                messages.success(request, f'Оплата для {student} удалена.')
            else:
                # Если новой оплаты нет, просто возвращаемся
                messages.info(request, 'Оплата не была создана, так как сумма равна 0.')
            return redirect('lesson_detail', pk=lesson_pk)
        
        # Если есть существующая оплата, передаем instance для обновления
        if existing_payment:
            previous_amount = existing_payment.amount
            was_balance_payment = existing_payment.is_balance_payment
            form = PaymentForm(request.POST, instance=existing_payment, lesson=lesson, student=student)
        else:
            previous_amount = Decimal('0.00')
            was_balance_payment = False
            form = PaymentForm(request.POST, lesson=lesson, student=student)
        
        if form.is_valid():
            payment = form.save(commit=False)
            
            # Сохраняем оплату (сумма уже проверена выше, если была 0, то оплата удалена)
            payment.student = student
            payment.lesson = lesson
            # Теперь способ оплаты не может быть 'balance' (убрали из формы)
            payment.is_balance_payment = False
            payment.save()
            
            # Если оплата ранее была списана с предоплаты, возвращаем средства
            if was_balance_payment:
                student.add_prepaid_balance(lesson.lesson_price)
            
            student.update_overpayment_balance(lesson, previous_amount, payment.amount)
            
            # Автоматически погашаем долг с предоплаты, если есть средства
            paid_lessons = student.auto_pay_debt_from_prepaid()
            debt_paid_amount = Decimal('0.00')
            if paid_lessons:
                lessons_count = len(paid_lessons)
                debt_paid_amount = sum(lesson.lesson_price for lesson in paid_lessons)
                messages.info(request, 
                    f'Автоматически погашено {lessons_count} долг(ов) на сумму {debt_paid_amount} руб. с предоплаты.')
                # Сохраняем информацию о списанных долгах в сессии для отображения в деталях занятия
                session_key = f'debt_paid_{lesson_pk}_{student_pk}'
                request.session[session_key] = str(debt_paid_amount)
            
            if existing_payment:
                messages.success(request, f'Оплата для {student} обновлена.')
            else:
                messages.success(request, f'Оплата для {student} отмечена.')
            return redirect('lesson_detail', pk=lesson_pk)
    else:
        # Проверяем, есть ли уже оплата
        if existing_payment:
            form = PaymentForm(instance=existing_payment, lesson=lesson, student=student)
        else:
            # Для новой формы устанавливаем начальные данные
            initial_data = {
                'payment_date': timezone.now().date().strftime('%Y-%m-%d'),
                'amount': lesson.lesson_price if lesson.lesson_price > 0 else None
            }
            form = PaymentForm(initial=initial_data, lesson=lesson, student=student)
    
    return render(request, 'main/mark_payment.html', {
        'form': form,
        'lesson': lesson,
        'student': student,
        'attendance': attendance
    })


def register(request):
    """Регистрация нового репетитора"""
    if request.user.is_authenticated:
        return redirect('calendar')
    
    if request.method == 'POST':
        form = TutorRegistrationForm(request.POST)
        if form.is_valid():
            user = form.save()
            username = form.cleaned_data.get('username')
            password = form.cleaned_data.get('password1')
            user = authenticate(username=username, password=password)
            if user:
                login(request, user)
                messages.success(request, f'Добро пожаловать, {user.get_full_name() or username}!')
                return redirect('calendar')
    else:
        form = TutorRegistrationForm()
    return render(request, 'main/register.html', {'form': form})


class TutorLoginView(LoginView):
    """Вход в систему"""
    template_name = 'main/login.html'
    redirect_authenticated_user = True
    
    def get_success_url(self):
        return reverse('calendar')


@login_required
def dashboard(request):
    """Личный кабинет репетитора со статистикой"""
    try:
        tutor = get_tutor(request)
        if not tutor:
            # Автоматически создаем профиль Tutor, если его нет
            tutor = Tutor.objects.create(user=request.user)
            messages.success(request, 'Профиль репетитора создан.')
        
        now = timezone.now()
        today = now.date()
        
        # Даты для статистики
        week_ago = today - timedelta(days=7)
        month_ago = today - timedelta(days=30)
        
        # Статистика по ученикам
        students_count = tutor.get_students_count()
        
        # Статистика по прибыли
        profit_all_time = tutor.get_total_profit()
        profit_month = tutor.get_total_profit(start_date=month_ago)
        profit_week = tutor.get_total_profit(start_date=week_ago)
        
        # Статистика по занятиям
        lessons_all_time = tutor.get_lessons_count()
        lessons_month = tutor.get_lessons_count(start_date=month_ago)
        lessons_week = tutor.get_lessons_count(start_date=week_ago)
        
        # Список долгов (ученики с долгами) - только топ 4 для дашборда
        students_with_debts = []
        total_debts = Decimal('0.00')
        all_students = Student.objects.filter(tutor=tutor, is_active=True)
        for student in all_students:
            debt = student.get_total_debt()
            if debt > 0:
                students_with_debts.append({
                    'student': student,
                    'debt': debt
                })
                total_debts += debt
        # Сортируем по размеру долга (от большего к меньшему)
        students_with_debts.sort(key=lambda x: x['debt'], reverse=True)
        
        # Для дашборда показываем только топ 4
        top_debtors = students_with_debts[:4]
        total_debtors_count = len(students_with_debts)
        
        return render(request, 'main/dashboard.html', {
            'tutor': tutor,
            'students_count': students_count,
            'profit_all_time': profit_all_time,
            'profit_month': profit_month,
            'profit_week': profit_week,
            'lessons_all_time': lessons_all_time,
            'lessons_month': lessons_month,
            'lessons_week': lessons_week,
            'students_with_debts': top_debtors,
            'total_debtors_count': total_debtors_count,
            'total_debts': total_debts,
        })
    except Exception as e:
        # Логируем ошибку для отладки
        import traceback
        print(f"Error in dashboard: {e}")
        print(traceback.format_exc())
        messages.error(request, f'Произошла ошибка: {str(e)}')
        return redirect('login')


@login_required
def profit_report(request):
    """Отчёты по прибыли за произвольный период"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')

    today = timezone.now().date()
    # По умолчанию показываем текущий месяц
    default_start = today.replace(day=1)
    default_end = today

    start_date_str = request.GET.get('start_date')
    end_date_str = request.GET.get('end_date')

    start_date = default_start
    end_date = default_end

    try:
        if start_date_str:
            start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
        if end_date_str:
            end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
    except (ValueError, TypeError):
        messages.warning(request, 'Неверный формат дат, использован период по умолчанию.')

    # Гарантируем, что start <= end
    if start_date > end_date:
        start_date, end_date = end_date, start_date

    payments_qs = Payment.objects.filter(
        student__tutor=tutor,
        is_balance_payment=False,
        payment_date__gte=start_date,
        payment_date__lte=end_date,
    ).select_related('student', 'lesson').order_by('-payment_date', '-created_at')

    total_profit = payments_qs.aggregate(total=Sum('amount'))['total'] or Decimal('0.00')

    # Разбивка по способам оплаты
    profit_by_method = payments_qs.values('payment_method').annotate(total=Sum('amount')).order_by()

    # Разбивка по дням
    profit_by_day = payments_qs.values('payment_date').annotate(total=Sum('amount')).order_by('payment_date')

    # Разбивка по ученикам
    profit_by_student = payments_qs.values(
        'student__id',
        'student__first_name',
        'student__last_name',
    ).annotate(total=Sum('amount')).order_by('-total')

    lessons_count = tutor.get_lessons_count(start_date=start_date, end_date=end_date)

    # Средняя прибыль за занятие и за день
    days_count = (end_date - start_date).days + 1
    avg_per_lesson = total_profit / lessons_count if lessons_count else Decimal('0.00')
    avg_per_day = total_profit / days_count if days_count else Decimal('0.00')

    return render(request, 'main/profit_report.html', {
        'tutor': tutor,
        'start_date': start_date,
        'end_date': end_date,
        'payments': payments_qs[:200],
        'total_profit': total_profit,
        'profit_by_method': profit_by_method,
        'profit_by_day': profit_by_day,
        'profit_by_student': profit_by_student,
        'lessons_count': lessons_count,
        'avg_per_lesson': avg_per_lesson,
        'avg_per_day': avg_per_day,
        'days_count': days_count,
    })


@login_required
def students_debt_list(request):
    """Полный список учеников с долгами"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    
    # Список всех долгов (ученики с долгами)
    students_with_debts = []
    total_debts = Decimal('0.00')
    all_students = Student.objects.filter(tutor=tutor, is_active=True)
    for student in all_students:
        debt = student.get_total_debt()
        if debt > 0:
            students_with_debts.append({
                'student': student,
                'debt': debt
            })
            total_debts += debt
    # Сортируем по размеру долга (от большего к меньшему)
    students_with_debts.sort(key=lambda x: x['debt'], reverse=True)
    
    return render(request, 'main/students_debt_list.html', {
        'students_with_debts': students_with_debts,
        'total_debts': total_debts,
    })


@login_required
def recurring_lesson_create(request):
    """Создание повторяющихся занятий"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    
    # Получаем день недели из GET параметра (0=Пн, 6=Вс)
    weekday_str = request.GET.get('weekday', None)
    initial_date = None
    
    if weekday_str:
        try:
            target_weekday = int(weekday_str)  # 0=Пн, 6=Вс
            today = timezone.now().date()
            current_weekday = today.weekday()
            
            # Вычисляем, сколько дней до следующего вхождения этого дня недели
            days_ahead = target_weekday - current_weekday
            if days_ahead < 0:  # Целевой день уже прошел на этой неделе
                days_ahead += 7
            # Если days_ahead == 0, это сегодняшний день - используем сегодня
            initial_date = today + timedelta(days=days_ahead)
        except (ValueError, TypeError):
            initial_date = timezone.now().date()
    else:
        initial_date = timezone.now().date()
    
    if request.method == 'POST':
        form = RecurringLessonForm(request.POST, tutor=tutor)
        if form.is_valid():
            # Получаем данные из формы
            students = form.cleaned_data['students']
            start_date = form.cleaned_data['start_date']
            time = form.cleaned_data['time']
            duration = form.cleaned_data['duration']
            lesson_price = form.cleaned_data['lesson_price']
            period = form.cleaned_data['period']
            notes = form.cleaned_data['notes']
            
            # Вычисляем конечную дату в зависимости от периода
            if period == '2weeks':
                end_date = start_date + timedelta(weeks=2)
            elif period == '1month':
                end_date = start_date + timedelta(days=30)
            elif period == '3months':
                end_date = start_date + timedelta(days=90)
            elif period == '6months':
                end_date = start_date + timedelta(days=180)
            elif period == '1year':
                end_date = start_date + timedelta(days=365)
            else:
                end_date = start_date + timedelta(days=30)
            
            # Создаем занятия каждую неделю в тот же день недели
            current_date = start_date
            lessons_created = 0
            
            while current_date <= end_date:
                lesson = Lesson.objects.create(
                    tutor=tutor,
                    date=current_date,
                    time=time,
                    duration=duration,
                    lesson_price=lesson_price,
                    subject='',
                    notes=notes
                )
                lesson.students.set(students)
                lessons_created += 1
                
                # Переходим к следующей неделе (тот же день недели)
                current_date += timedelta(weeks=1)
            
            messages.success(request, f'Создано {lessons_created} занятий на период "{dict(form.fields["period"].choices)[period]}".')
            return redirect('calendar')
    else:
        form = RecurringLessonForm(tutor=tutor, initial_date=initial_date)
    
    # Определяем название дня недели для отображения
    weekday_names = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье']
    weekday_name = weekday_names[initial_date.weekday()] if initial_date else ''
    
    return render(request, 'main/recurring_lesson_form.html', {
        'form': form,
        'title': f'Повторяющиеся занятия - {weekday_name}',
        'weekday_name': weekday_name
    })


@login_required
def group_list(request):
    """Список всех групп"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    groups = StudentGroup.objects.filter(tutor=tutor, is_active=True)
    return render(request, 'main/group_list.html', {'groups': groups})


@login_required
def group_detail(request, pk):
    """Детальная информация о группе"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    group = get_object_or_404(StudentGroup, pk=pk, tutor=tutor)
    students = group.students.filter(is_active=True).order_by('last_name', 'first_name')
    return render(request, 'main/group_detail.html', {
        'group': group,
        'students': students
    })


@login_required
def group_create(request):
    """Создание новой группы"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    if request.method == 'POST':
        form = StudentGroupForm(request.POST, tutor=tutor)
        if form.is_valid():
            group = form.save(commit=False)
            group.tutor = tutor
            # Не вызываем save() здесь, вызываем в форме
            group = form.save()  # Это сохранит группу и учеников
            messages.success(request, f'Группа "{group.name}" успешно создана.')
            return redirect('group_detail', pk=group.pk)
    else:
        form = StudentGroupForm(tutor=tutor)
    return render(request, 'main/group_form.html', {
        'form': form,
        'title': 'Создать группу'
    })


@login_required
def group_edit(request, pk):
    """Редактирование группы"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    group = get_object_or_404(StudentGroup, pk=pk, tutor=tutor)
    if request.method == 'POST':
        form = StudentGroupForm(request.POST, instance=group, tutor=tutor)
        if form.is_valid():
            group = form.save()
            messages.success(request, f'Группа "{group.name}" успешно обновлена.')
            return redirect('group_detail', pk=group.pk)
    else:
        form = StudentGroupForm(instance=group, tutor=tutor)
    return render(request, 'main/group_form.html', {
        'form': form,
        'group': group,
        'title': 'Редактировать группу'
    })


@login_required
def group_delete(request, pk):
    """Удаление группы"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    group = get_object_or_404(StudentGroup, pk=pk, tutor=tutor)
    if request.method == 'POST':
        group_name = group.name
        group.delete()
        messages.success(request, f'Группа "{group_name}" успешно удалена.')
        return redirect('group_list')
    return render(request, 'main/group_confirm_delete.html', {'group': group})


@login_required
def clear_all_debts(request, pk):
    """Погашение всех долгов ученика"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('calendar')
    
    student = get_object_or_404(Student, pk=pk, tutor=tutor)
    
    # Получаем все неоплаченные занятия
    unpaid_lessons = []
    for lesson in student.lessons.all():
        # Проверяем, что у занятия есть отметки посещаемости
        if not lesson.attendances.exists():
            continue
        
        # Проверяем, присутствовал ли ученик на занятии
        attendance = Attendance.objects.filter(lesson=lesson, student=student, status='present').first()
        if attendance:
            # Проверяем, оплатил ли он это занятие
            payment = Payment.objects.filter(lesson=lesson, student=student).first()
            if not payment and lesson.lesson_price > 0:
                unpaid_lessons.append(lesson)
    
    if not unpaid_lessons:
        messages.info(request, f'У ученика {student} нет долгов.')
        return redirect('student_detail', pk=pk)
    
    total_debt = sum([lesson.lesson_price for lesson in unpaid_lessons])
    
    if request.method == 'POST':
        form = ClearAllDebtsForm(request.POST)
        if form.is_valid():
            payment_method = form.cleaned_data['payment_method']
            payment_date = form.cleaned_data['payment_date']
            notes = form.cleaned_data['notes']
            
            # Сначала автоматически погашаем долги с предоплаты, если есть средства
            paid_from_balance = student.auto_pay_debt_from_prepaid()
            paid_from_balance_lessons = [lesson for lesson in paid_from_balance]
            paid_from_balance_amount = sum(lesson.lesson_price for lesson in paid_from_balance_lessons)
            
            # Обновляем список неоплаченных занятий (исключаем те, что уже оплачены с предоплаты)
            remaining_unpaid_lessons = [lesson for lesson in unpaid_lessons if lesson not in paid_from_balance_lessons]
            
            # Создаем платежи для оставшихся неоплаченных занятий
            payments_created = 0
            for lesson in remaining_unpaid_lessons:
                Payment.objects.create(
                    student=student,
                    lesson=lesson,
                    amount=lesson.lesson_price,
                    payment_date=payment_date,
                    payment_method=payment_method,
                    notes=notes,
                    is_balance_payment=False
                )
                payments_created += 1
                # Обновляем баланс переплаты
                student.update_overpayment_balance(lesson, Decimal('0.00'), lesson.lesson_price)
            
            # Формируем сообщения
            messages_list = []
            if paid_from_balance_lessons:
                messages_list.append(
                    f'Автоматически погашено {len(paid_from_balance_lessons)} долг(ов) на сумму {paid_from_balance_amount} руб. с предоплаты.'
                )
            if payments_created > 0:
                remaining_debt = sum(lesson.lesson_price for lesson in remaining_unpaid_lessons)
                messages_list.append(
                    f'Создано платежей: {payments_created} на сумму {remaining_debt} руб.'
                )
            
            if messages_list:
                for msg in messages_list:
                    messages.info(request, msg)
            
            messages.success(request, f'Все долги ({total_debt} руб.) успешно погашены.')
            return redirect('student_detail', pk=pk)
    else:
        # Устанавливаем начальные данные с сегодняшней датой
        initial_data = {'payment_date': timezone.now().date().strftime('%Y-%m-%d')}
        form = ClearAllDebtsForm(initial=initial_data)
    
    return render(request, 'main/clear_all_debts.html', {
        'form': form,
        'student': student,
        'unpaid_lessons': unpaid_lessons,
        'total_debt': total_debt,
    })
