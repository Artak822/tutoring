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
from decimal import Decimal
from .models import Student, Lesson, Attendance, Payment, Tutor
from .forms import StudentForm, LessonForm, AttendanceForm, PaymentForm, TutorRegistrationForm


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
        return redirect('dashboard')
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
        return redirect('dashboard')
    student = get_object_or_404(Student, pk=pk, tutor=tutor)
    lessons = Lesson.objects.filter(tutor=tutor, students=student).order_by('-date', '-time')[:10]
    payments = Payment.objects.filter(student=student).order_by('-payment_date')[:10]
    
    # Статистика
    total_paid = student.get_total_paid()
    total_debt = student.get_total_debt()
    total_lessons = student.get_total_lessons_count()
    absent_lessons = student.get_absent_lessons_count()
    present_lessons = student.get_present_lessons_count()
    
    return render(request, 'main/student_detail.html', {
        'student': student,
        'lessons': lessons,
        'payments': payments,
        'total_paid': total_paid,
        'total_debt': total_debt,
        'total_lessons': total_lessons,
        'absent_lessons': absent_lessons,
        'present_lessons': present_lessons,
    })


@login_required
def student_create(request):
    """Создание нового ученика"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('dashboard')
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
        return redirect('dashboard')
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
    """Удаление ученика"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('dashboard')
    student = get_object_or_404(Student, pk=pk, tutor=tutor)
    if request.method == 'POST':
        student_name = str(student)
        student.delete()
        messages.success(request, f'Ученик {student_name} успешно удален.')
        return redirect('student_list')
    return render(request, 'main/student_confirm_delete.html', {'student': student})


@login_required
def calendar_view(request):
    """Календарь с занятиями"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('dashboard')
    # Получаем год и месяц из параметров или используем текущие
    now = timezone.now()
    try:
        year = int(request.GET.get('year', now.year))
        month = int(request.GET.get('month', now.month))
    except (ValueError, TypeError):
        year = now.year
        month = now.month
    
    today = now.date()
    
    # Получаем параметры для недельного режима (для мобильных)
    try:
        week_offset = int(request.GET.get('week_offset', 0))
    except (ValueError, TypeError):
        week_offset = 0
    
    # Вычисляем предыдущий и следующий месяц
    if month == 1:
        prev_month = 12
        prev_year = year - 1
    else:
        prev_month = month - 1
        prev_year = year
    
    if month == 12:
        next_month = 1
        next_year = year + 1
    else:
        next_month = month + 1
        next_year = year
    
    # Получаем все занятия за месяц
    first_day = datetime(year, month, 1).date()
    last_day_num = monthrange(year, month)[1]
    last_day = datetime(year, month, last_day_num).date()
    
    lessons = Lesson.objects.filter(tutor=tutor, date__gte=first_day, date__lte=last_day).order_by('date', 'time')
    
    # Группируем занятия по дням
    lessons_by_date = {}
    for lesson in lessons:
        date_key = lesson.date.strftime('%Y-%m-%d')
        if date_key not in lessons_by_date:
            lessons_by_date[date_key] = []
        lessons_by_date[date_key].append(lesson)
    
    # Создаем календарную сетку
    first_weekday = first_day.weekday()  # 0 = понедельник, 6 = воскресенье
    calendar_days = []
    
    # Пустые дни в начале месяца
    for _ in range(first_weekday):
        calendar_days.append(None)
    
    # Дни месяца
    weekday_names = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье']
    for day in range(1, last_day_num + 1):
        date = datetime(year, month, day).date()
        date_key = date.strftime('%Y-%m-%d')
        calendar_days.append({
            'date': date,
            'lessons': lessons_by_date.get(date_key, []),
            'weekday_name': weekday_names[date.weekday()]
        })
    
    # Делим на недели
    weeks = []
    week = []
    for day in calendar_days:
        week.append(day)
        if len(week) == 7:
            weeks.append(week)
            week = []
    if week:
        # Дополняем последнюю неделю пустыми днями
        while len(week) < 7:
            week.append(None)
        weeks.append(week)
    
    # Для мобильной версии: определяем текущую неделю
    # Сначала находим неделю с сегодняшним днем
    base_week_index = None
    for i, week in enumerate(weeks):
        for day in week:
            if day and day['date'] == today:
                base_week_index = i
                break
        if base_week_index is not None:
            break
    
    if base_week_index is None:
        # Если сегодняшний день не в текущем месяце, показываем первую неделю
        base_week_index = 0
    
    # Применяем смещение недели
    current_week_index = base_week_index + week_offset
    
    # Проверяем, нужно ли переключить месяц
    target_year = year
    target_month = month
    target_week_offset = week_offset
    
    # Если следующая неделя выходит за пределы месяца
    if current_week_index >= len(weeks):
        # Переключаемся на следующий месяц
        if month == 12:
            target_year = year + 1
            target_month = 1
        else:
            target_year = year
            target_month = month + 1
        target_week_offset = 0  # Сбрасываем offset, начинаем с первой недели нового месяца
        # Делаем редирект на следующий месяц
        return redirect(f"{reverse('calendar')}?year={target_year}&month={target_month}&week_offset={target_week_offset}")
    
    # Если предыдущая неделя выходит за пределы месяца
    if current_week_index < 0:
        # Переключаемся на предыдущий месяц
        if month == 1:
            target_year = year - 1
            target_month = 12
        else:
            target_year = year
            target_month = month - 1
        
        # Вычисляем количество недель в предыдущем месяце
        prev_first_day = datetime(target_year, target_month, 1).date()
        prev_last_day_num = monthrange(target_year, target_month)[1]
        prev_first_weekday = prev_first_day.weekday()
        prev_total_days = prev_last_day_num + prev_first_weekday
        prev_weeks_count = (prev_total_days + 6) // 7  # Округляем вверх
        
        target_week_offset = prev_weeks_count - 1  # Показываем последнюю неделю предыдущего месяца
        # Делаем редирект на предыдущий месяц
        return redirect(f"{reverse('calendar')}?year={target_year}&month={target_month}&week_offset={target_week_offset}")
    
    # Ограничиваем индекс недели в пределах текущего месяца
    if current_week_index < 0:
        current_week_index = 0
    elif current_week_index >= len(weeks):
        current_week_index = len(weeks) - 1
    
    # Получаем текущую неделю для мобильной версии
    current_week = weeks[current_week_index] if weeks and current_week_index < len(weeks) else []
    
    # Определяем даты начала и конца текущей недели
    week_start_date = None
    week_end_date = None
    for day in current_week:
        if day:
            if week_start_date is None:
                week_start_date = day['date']
            week_end_date = day['date']
    
    # Вычисляем параметры для навигации по неделям
    # Для следующей недели
    if current_week_index >= len(weeks) - 1:
        # Если это последняя неделя месяца, переключаемся на следующий месяц
        next_week_year = next_year
        next_week_month = next_month
        next_week_offset = 0
    else:
        next_week_year = year
        next_week_month = month
        next_week_offset = week_offset + 1
    
    # Для предыдущей недели
    if current_week_index <= 0 and week_offset <= 0:
        # Если это первая неделя месяца, переключаемся на предыдущий месяц
        # Вычисляем количество недель в предыдущем месяце
        if prev_month == 12:
            prev_first_day = datetime(prev_year, prev_month, 1).date()
        else:
            prev_first_day = datetime(prev_year, prev_month, 1).date()
        prev_last_day_num = monthrange(prev_year, prev_month)[1]
        prev_first_weekday = prev_first_day.weekday()
        prev_total_days = prev_last_day_num + prev_first_weekday
        prev_weeks_count = (prev_total_days + 6) // 7  # Округляем вверх
        
        prev_week_year = prev_year
        prev_week_month = prev_month
        prev_week_offset = prev_weeks_count - 1  # Показываем последнюю неделю предыдущего месяца
    else:
        prev_week_year = year
        prev_week_month = month
        prev_week_offset = week_offset - 1
    
    month_names = ['', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
                   'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь']
    
    return render(request, 'main/calendar.html', {
        'weeks': weeks,
        'current_week': current_week,
        'current_week_index': current_week_index,
        'week_start_date': week_start_date,
        'week_end_date': week_end_date,
        'year': year,
        'month': month,
        'month_name': month_names[month],
        'prev_year': prev_year,
        'prev_month': prev_month,
        'next_year': next_year,
        'next_month': next_month,
        'prev_week_offset': week_offset - 1,
        'next_week_offset': week_offset + 1,
        'today': today,
    })


@login_required
def lesson_list(request):
    """Список всех занятий"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('dashboard')
    lessons = Lesson.objects.filter(tutor=tutor).order_by('-date', '-time')
    return render(request, 'main/lesson_list.html', {'lessons': lessons})


@login_required
def lesson_detail(request, pk):
    """Детальная информация о занятии"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('dashboard')
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
        students_data.append({
            'student': student,
            'attendance': attendance,
            'payment': payment,
            'has_debt': attendance and attendance.status == 'present' and not payment and lesson.lesson_price > 0
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
        return redirect('dashboard')
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
        form = LessonForm(tutor=tutor)
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
        return redirect('dashboard')
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
        return redirect('dashboard')
    lesson = get_object_or_404(Lesson, pk=pk, tutor=tutor)
    if request.method == 'POST':
        lesson_date = lesson.date
        lesson.delete()
        messages.success(request, f'Занятие от {lesson_date} успешно удалено.')
        return redirect('lesson_list')
    return render(request, 'main/lesson_confirm_delete.html', {'lesson': lesson})


@login_required
def mark_attendance(request, lesson_pk, student_pk):
    """Отметка посещаемости для ученика на занятии"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('dashboard')
    lesson = get_object_or_404(Lesson, pk=lesson_pk, tutor=tutor)
    student = get_object_or_404(Student, pk=student_pk, tutor=tutor)
    
    # Проверяем, что ученик назначен на это занятие
    if student not in lesson.students.all():
        messages.error(request, 'Этот ученик не назначен на данное занятие.')
        return redirect('lesson_detail', pk=lesson_pk)
    
    attendance, created = Attendance.objects.get_or_create(
        lesson=lesson,
        student=student,
        defaults={'status': 'present'}
    )
    
    if request.method == 'POST':
        form = AttendanceForm(request.POST, instance=attendance)
        if form.is_valid():
            form.save()
            messages.success(request, f'Посещаемость для {student} отмечена.')
            return redirect('lesson_detail', pk=lesson_pk)
    else:
        form = AttendanceForm(instance=attendance)
    
    return render(request, 'main/mark_attendance.html', {
        'form': form,
        'lesson': lesson,
        'student': student,
        'attendance': attendance
    })


@login_required
def mark_payment(request, lesson_pk, student_pk):
    """Отметка оплаты для ученика за занятие"""
    tutor = get_tutor(request)
    if not tutor:
        messages.error(request, 'Профиль репетитора не найден.')
        return redirect('dashboard')
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
        # Если есть существующая оплата, передаем instance для обновления
        if existing_payment:
            form = PaymentForm(request.POST, instance=existing_payment, lesson=lesson, student=student)
        else:
            form = PaymentForm(request.POST, lesson=lesson, student=student)
        
        if form.is_valid():
            payment = form.save(commit=False)
            payment.student = student
            payment.lesson = lesson
            payment.save()
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
            form = PaymentForm(lesson=lesson, student=student)
    
    return render(request, 'main/mark_payment.html', {
        'form': form,
        'lesson': lesson,
        'student': student,
        'attendance': attendance
    })


def register(request):
    """Регистрация нового репетитора"""
    if request.user.is_authenticated:
        return redirect('dashboard')
    
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
                return redirect('dashboard')
    else:
        form = TutorRegistrationForm()
    return render(request, 'main/register.html', {'form': form})


class TutorLoginView(LoginView):
    """Вход в систему"""
    template_name = 'main/login.html'
    redirect_authenticated_user = True
    
    def get_success_url(self):
        return reverse('dashboard')


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
        
        # Последние занятия
        recent_lessons = Lesson.objects.filter(tutor=tutor).order_by('-date', '-time')[:5]
        
        # Последние ученики
        recent_students = Student.objects.filter(tutor=tutor).order_by('-created_at')[:5]
        
        return render(request, 'main/dashboard.html', {
            'tutor': tutor,
            'students_count': students_count,
            'profit_all_time': profit_all_time,
            'profit_month': profit_month,
            'profit_week': profit_week,
            'lessons_all_time': lessons_all_time,
            'lessons_month': lessons_month,
            'lessons_week': lessons_week,
            'recent_lessons': recent_lessons,
            'recent_students': recent_students,
        })
    except Exception as e:
        # Логируем ошибку для отладки
        import traceback
        print(f"Error in dashboard: {e}")
        print(traceback.format_exc())
        messages.error(request, f'Произошла ошибка: {str(e)}')
        return redirect('login')
