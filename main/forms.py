from django import forms
from django.contrib.auth.forms import UserCreationForm
from django.contrib.auth.models import User
from django.utils import timezone
from .models import Student, Lesson, Attendance, Payment, Tutor, StudentGroup


class GroupedStudentWidget(forms.CheckboxSelectMultiple):
    """Кастомный виджет для выбора учеников с группировкой по группам"""
    template_name = 'main/widgets/grouped_student_widget.html'
    
    def __init__(self, tutor=None, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.tutor = tutor
    
    def get_context(self, name, value, attrs):
        context = super().get_context(name, value, attrs)
        
        if self.tutor:
            # Получаем все группы репетитора
            groups = StudentGroup.objects.filter(tutor=self.tutor, is_active=True).prefetch_related('students')
            
            # Получаем всех учеников
            all_students = Student.objects.filter(tutor=self.tutor, is_active=True)
            
            # Получаем учеников, которые состоят хотя бы в одной группе
            students_in_groups = set()
            for group in groups:
                students_in_groups.update(group.students.filter(is_active=True))
            
            # Ученики без групп
            students_without_groups = [s for s in all_students if s not in students_in_groups]
            
            context['groups'] = groups
            context['students_without_groups'] = students_without_groups
        else:
            context['groups'] = []
            context['students_without_groups'] = []
        
        return context


class TutorRegistrationForm(UserCreationForm):
    """Форма регистрации репетитора"""
    email = forms.EmailField(required=True, widget=forms.EmailInput(attrs={
        'class': 'form-input',
        'placeholder': 'Введите email'
    }))
    first_name = forms.CharField(max_length=30, required=True, widget=forms.TextInput(attrs={
        'class': 'form-input',
        'placeholder': 'Введите имя'
    }))
    last_name = forms.CharField(max_length=30, required=True, widget=forms.TextInput(attrs={
        'class': 'form-input',
        'placeholder': 'Введите фамилию'
    }))
    phone = forms.CharField(max_length=20, required=False, widget=forms.TextInput(attrs={
        'class': 'form-input',
        'placeholder': 'Введите телефон'
    }))
    
    class Meta:
        model = User
        fields = ('username', 'email', 'first_name', 'last_name', 'password1', 'password2')
        widgets = {
            'username': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Введите имя пользователя'
            }),
        }
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['password1'].widget.attrs.update({'class': 'form-input', 'placeholder': 'Введите пароль'})
        self.fields['password2'].widget.attrs.update({'class': 'form-input', 'placeholder': 'Подтвердите пароль'})
    
    def save(self, commit=True):
        user = super().save(commit=False)
        user.email = self.cleaned_data['email']
        user.first_name = self.cleaned_data['first_name']
        user.last_name = self.cleaned_data['last_name']
        if commit:
            user.save()
            tutor = Tutor.objects.create(
                user=user,
                phone=self.cleaned_data.get('phone', '')
            )
        return user


class StudentForm(forms.ModelForm):
    """Форма для создания и редактирования ученика"""
    
    class Meta:
        model = Student
        fields = ['first_name', 'last_name', 'phone', 'telegram', 'grade', 'default_price', 'notes', 'is_active']
        exclude = ['tutor']
        widgets = {
            'first_name': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Введите имя'
            }),
            'last_name': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Введите фамилию'
            }),
            'phone': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Введите телефон'
            }),
            'telegram': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Введите телеграм'
            }),
            'grade': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Введите класс'
            }),
            'default_price': forms.NumberInput(attrs={
                'class': 'form-input',
                'min': '0',
                'step': '0.01',
                'placeholder': 'Цена за занятие'
            }),
            'notes': forms.Textarea(attrs={
                'class': 'form-textarea',
                'rows': 5,
                'placeholder': 'Дополнительные заметки'
            }),
            'is_active': forms.CheckboxInput(attrs={
                'class': 'form-checkbox'
            }),
        }
        labels = {
            'first_name': 'Имя',
            'last_name': 'Фамилия',
            'phone': 'Телефон',
            'telegram': 'Телеграм',
            'grade': 'Класс',
            'default_price': 'Цена по умолчанию',
            'notes': 'Заметки',
            'is_active': 'Активен',
        }
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Делаем поля обязательными
        self.fields['first_name'].required = True
        self.fields['last_name'].required = True
        # Добавляем атрибут required в HTML
        self.fields['first_name'].widget.attrs['required'] = True
        self.fields['last_name'].widget.attrs['required'] = True


class StudentGroupForm(forms.ModelForm):
    """Форма для создания и редактирования группы учеников"""
    students = forms.ModelMultipleChoiceField(
        queryset=Student.objects.none(),
        widget=forms.CheckboxSelectMultiple(),
        label='Ученики',
        required=False,
    )
    
    class Meta:
        model = StudentGroup
        fields = ['name', 'description', 'is_active']
        widgets = {
            'name': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Оставьте пустым для автогенерации из имен учеников',
                'required': False
            }),
            'description': forms.Textarea(attrs={
                'class': 'form-textarea',
                'rows': 3,
                'placeholder': 'Описание группы (необязательно)'
            }),
            'is_active': forms.CheckboxInput(attrs={
                'class': 'form-checkbox'
            }),
        }
        labels = {
            'name': 'Название группы (необязательно)',
            'description': 'Описание',
            'is_active': 'Активна',
        }
    
    def __init__(self, *args, **kwargs):
        tutor = kwargs.pop('tutor', None)
        super().__init__(*args, **kwargs)
        
        # Делаем поле name необязательным
        self.fields['name'].required = False
        
        # Показываем только активных учеников репетитора
        if tutor:
            self.fields['students'].queryset = Student.objects.filter(tutor=tutor, is_active=True).order_by('last_name', 'first_name')
        
        # Если редактируем существующую группу, показываем текущих учеников
        if self.instance.pk:
            self.fields['students'].initial = self.instance.students.all()
    
    def save(self, commit=True):
        # Сначала генерируем имя, если нужно
        students = self.cleaned_data.get('students', [])
        
        if not self.cleaned_data.get('name') or self.cleaned_data['name'].strip() == '':
            if students:
                names = [student.first_name for student in students]
                self.cleaned_data['name'] = ', '.join(names)
            else:
                self.cleaned_data['name'] = 'Новая группа'
        
        # Сохраняем группу
        group = super().save(commit=False)
        group.name = self.cleaned_data['name']
        
        if commit:
            group.save()
            # Важно: сохраняем ManyToMany связи ПОСЛЕ сохранения группы
            group.students.set(students)
            self.save_m2m()  # Сохраняем остальные ManyToMany если есть
        
        return group


class LessonForm(forms.ModelForm):
    """Форма для создания и редактирования занятия"""
    
    class Meta:
        model = Lesson
        fields = ['students', 'date', 'time', 'duration', 'lesson_price', 'subject', 'notes']
        exclude = ['tutor']
        widgets = {
            'date': forms.DateInput(attrs={
                'class': 'form-input',
                'type': 'date'
            }),
            'time': forms.TimeInput(attrs={
                'class': 'form-input',
                'type': 'time'
            }),
            'duration': forms.NumberInput(attrs={
                'class': 'form-input',
                'min': '1',
                'placeholder': '60'
            }),
            'lesson_price': forms.NumberInput(attrs={
                'class': 'form-input',
                'min': '0',
                'step': '0.01',
                'placeholder': '500'
            }),
            'subject': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Введите предмет или тему'
            }),
            'notes': forms.Textarea(attrs={
                'class': 'form-textarea',
                'rows': 5,
                'placeholder': 'Дополнительные заметки'
            }),
        }
        labels = {
            'students': 'Ученики',
            'date': 'Дата',
            'time': 'Время',
            'duration': 'Длительность (минуты)',
            'lesson_price': 'Стоимость занятия',
            'subject': 'Предмет/Тема',
            'notes': 'Заметки',
        }
    
    def __init__(self, *args, **kwargs):
        tutor = kwargs.pop('tutor', None)
        initial_date = kwargs.pop('initial_date', None)
        
        # Преобразуем строку в объект date, если это строка, до вызова super()
        if initial_date and isinstance(initial_date, str):
            try:
                from datetime import datetime
                initial_date = datetime.strptime(initial_date, '%Y-%m-%d').date()
            except (ValueError, TypeError):
                initial_date = timezone.now().date()
        
        # Устанавливаем initial для даты, если передана
        if initial_date and 'initial' not in kwargs:
            kwargs['initial'] = {'date': initial_date}
        elif not initial_date and 'initial' not in kwargs:
            kwargs['initial'] = {'date': timezone.now().date()}
        elif initial_date and 'initial' in kwargs:
            kwargs['initial']['date'] = initial_date
        
        super().__init__(*args, **kwargs)
        
        # Заменяем виджет на кастомный для учеников
        if tutor:
            self.fields['students'].widget = GroupedStudentWidget(tutor=tutor)
            self.fields['students'].queryset = Student.objects.filter(tutor=tutor, is_active=True).order_by('last_name', 'first_name')
        else:
            self.fields['students'].queryset = Student.objects.none()
        
        self.fields['students'].required = True
        
        # Устанавливаем значение по умолчанию для стоимости только для новых занятий
        if not self.instance.pk and not self.fields['lesson_price'].initial:
            self.fields['lesson_price'].initial = 500
        
        # Убеждаемся, что значение даты установлено в виджете
        if not self.instance.pk:
            if self.fields['date'].initial:
                date_value = self.fields['date'].initial
                if hasattr(date_value, 'strftime'):
                    date_str = date_value.strftime('%Y-%m-%d')
                elif isinstance(date_value, str):
                    date_str = date_value
                else:
                    date_str = str(date_value)
                # Устанавливаем значение в виджете
                self.fields['date'].widget.attrs['value'] = date_str
            else:
                # Если initial не установлен, устанавливаем сегодняшнюю дату
                today = timezone.now().date()
                self.fields['date'].initial = today
                self.fields['date'].widget.attrs['value'] = today.strftime('%Y-%m-%d')
    


class AttendanceForm(forms.ModelForm):
    class Meta:
        model = Attendance
        fields = ['status', 'notes']
        widgets = {
            'status': forms.RadioSelect(attrs={
                'class': 'form-radio',
                'data-bind': 'checked: selectedStatus'
            }),
            'notes': forms.Textarea(attrs={
                'class': 'form-textarea',
                'rows': 3,
                'placeholder': 'Дополнительные заметки'
            }),
        }
        labels = {
            'status': 'Посещаемость',
        }
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Убедитесь, что choices установлены
        self.fields['status'].choices = Attendance.STATUS_CHOICES
        # Добавьте класс к label для каждого варианта
        self.fields['status'].widget.attrs.update({'class': 'form-radio'})

class PaymentForm(forms.ModelForm):
    """Форма для отметки оплаты"""
    
    class Meta:
        model = Payment
        fields = ['amount', 'payment_date', 'payment_method', 'notes']
        widgets = {
            'amount': forms.NumberInput(attrs={
                'class': 'form-input',
                'min': '0',
                'step': '0.01',
                'placeholder': '0.00'
            }),
            'payment_date': forms.DateInput(attrs={
                'class': 'form-input',
                'type': 'date'
            }),
            'payment_method': forms.RadioSelect(attrs={
                'class': 'form-radio',
            }),
            'notes': forms.Textarea(attrs={
                'class': 'form-textarea',
                'rows': 3,
                'placeholder': 'Дополнительные заметки (например: оплатили картой)'
            }),
        }
        labels = {
            'amount': 'Сумма',
            'payment_date': 'Дата оплаты',
            'payment_method': 'Способ оплаты',
            'notes': 'Заметки',
        }
    
    def __init__(self, *args, **kwargs):
        lesson = kwargs.pop('lesson', None)
        student = kwargs.pop('student', None)
        super().__init__(*args, **kwargs)
        
        # Убираем способ "Списано с предоплаты" из выбора - теперь это происходит автоматически
        choices = [
            choice for choice in Payment.PAYMENT_METHOD_CHOICES
            if choice[0] != 'balance'
        ]
        self.fields['payment_method'].choices = choices
        
        # Для новых платежей устанавливаем значения по умолчанию (если еще не установлены)
        if not self.instance.pk:
            if lesson and student:
                # Устанавливаем стоимость занятия по умолчанию
                if lesson.lesson_price > 0 and not self.fields['amount'].initial:
                    self.fields['amount'].initial = lesson.lesson_price
            
            # Всегда устанавливаем сегодняшнюю дату для новых платежей (если еще не установлена)
            if not self.fields['payment_date'].initial:
                today = timezone.now().date().strftime('%Y-%m-%d')
                self.fields['payment_date'].initial = today
                # Также устанавливаем через widget.attrs для надежности
                self.fields['payment_date'].widget.attrs['value'] = today


class RecurringLessonForm(forms.Form):
    """Форма для создания повторяющихся занятий"""
    PERIOD_CHOICES = [
        ('2weeks', '2 недели'),
        ('1month', '1 месяц'),
        ('3months', '3 месяца'),
        ('6months', '6 месяцев'),
        ('1year', '1 год'),
    ]
    
    students = forms.ModelMultipleChoiceField(
        queryset=Student.objects.none(),
        label='Ученики',
        required=True
    )
    start_date = forms.DateField(
        widget=forms.DateInput(attrs={
            'class': 'form-input',
            'type': 'date'
        }),
        label='Начальная дата'
    )
    time = forms.TimeField(
        widget=forms.TimeInput(attrs={
            'class': 'form-input',
            'type': 'time'
        }),
        label='Время'
    )
    duration = forms.IntegerField(
        widget=forms.NumberInput(attrs={
            'class': 'form-input',
            'min': '1',
            'placeholder': '60'
        }),
        label='Длительность (минуты)',
        initial=60
    )
    lesson_price = forms.DecimalField(
        widget=forms.NumberInput(attrs={
            'class': 'form-input',
            'min': '0',
            'step': '0.01',
            'placeholder': '500'
        }),
        label='Стоимость занятия (за одного ученика)',
        initial=500
    )
    period = forms.ChoiceField(
        choices=PERIOD_CHOICES,
        widget=forms.RadioSelect(attrs={
            'class': 'form-radio'
        }),
        label='Период повторения',
        initial='1month'
    )
    notes = forms.CharField(
        widget=forms.Textarea(attrs={
            'class': 'form-textarea',
            'rows': 3,
            'placeholder': 'Дополнительные заметки (необязательно)'
        }),
        label='Заметки',
        required=False
    )
    
    def __init__(self, *args, **kwargs):
        tutor = kwargs.pop('tutor', None)
        initial_date = kwargs.pop('initial_date', None)
        super().__init__(*args, **kwargs)
        
        # Заменяем виджет на кастомный для учеников
        if tutor:
            self.fields['students'].widget = GroupedStudentWidget(tutor=tutor)
            self.fields['students'].queryset = Student.objects.filter(tutor=tutor, is_active=True).order_by('last_name', 'first_name')
        
        # Устанавливаем начальную дату
        if initial_date:
            # Преобразуем дату в строку формата YYYY-MM-DD для HTML input
            if isinstance(initial_date, str):
                self.fields['start_date'].initial = initial_date
            else:
                self.fields['start_date'].initial = initial_date.strftime('%Y-%m-%d')
        else:
            self.fields['start_date'].initial = timezone.now().date().strftime('%Y-%m-%d')
    


class ClearAllDebtsForm(forms.Form):
    """Форма для погашения всех долгов ученика"""
    payment_method = forms.ChoiceField(
        choices=[choice for choice in Payment.PAYMENT_METHOD_CHOICES if choice[0] != 'balance'],
        widget=forms.RadioSelect(attrs={
            'class': 'form-radio'
        }),
        label='Способ оплаты',
        initial='cash'
    )
    payment_date = forms.DateField(
        widget=forms.DateInput(attrs={
            'class': 'form-input',
            'type': 'date'
        }),
        label='Дата оплаты'
    )
    notes = forms.CharField(
        widget=forms.Textarea(attrs={
            'class': 'form-textarea',
            'rows': 3,
            'placeholder': 'Дополнительные заметки (необязательно)'
        }),
        label='Заметки',
        required=False
    )
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Устанавливаем сегодняшнюю дату при каждом создании формы
        if not self.initial.get('payment_date'):
            today = timezone.now().date().strftime('%Y-%m-%d')
            self.fields['payment_date'].initial = today
            # Также устанавливаем через widget.attrs для надежности
            self.fields['payment_date'].widget.attrs['value'] = today