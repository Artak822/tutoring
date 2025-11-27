from django import forms
from django.contrib.auth.forms import UserCreationForm
from django.contrib.auth.models import User
from django.utils import timezone
from .models import Student, Lesson, Attendance, Payment, Tutor


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
        fields = ['first_name', 'last_name', 'phone', 'telegram', 'grade', 'notes', 'is_active']
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


class LessonForm(forms.ModelForm):
    """Форма для создания и редактирования занятия"""
    
    class Meta:
        model = Lesson
        fields = ['students', 'date', 'time', 'duration', 'lesson_price', 'subject', 'notes']
        exclude = ['tutor']
        widgets = {
            'students': forms.SelectMultiple(attrs={
                'class': 'form-select',
                'size': '8'
            }),
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
            'lesson_price': 'Стоимость занятия (за одного ученика)',
            'subject': 'Предмет/Тема',
            'notes': 'Заметки',
        }
    
    def __init__(self, *args, **kwargs):
        tutor = kwargs.pop('tutor', None)
        super().__init__(*args, **kwargs)
        # Показываем только активных учеников репетитора
        if tutor:
            self.fields['students'].queryset = Student.objects.filter(tutor=tutor, is_active=True).order_by('last_name', 'first_name')
        else:
            self.fields['students'].queryset = Student.objects.none()
        self.fields['students'].required = True
        
        # Устанавливаем значение по умолчанию для стоимости только для новых занятий
        if not self.instance.pk and not self.fields['lesson_price'].initial:
            self.fields['lesson_price'].initial = 500


class AttendanceForm(forms.ModelForm):
    """Форма для отметки посещаемости"""
    
    class Meta:
        model = Attendance
        fields = ['status', 'notes']
        widgets = {
            'status': forms.Select(attrs={
                'class': 'form-input'
            }),
            'notes': forms.Textarea(attrs={
                'class': 'form-textarea',
                'rows': 3,
                'placeholder': 'Дополнительные заметки'
            }),
        }
        labels = {
            'status': 'Статус',
            'notes': 'Заметки',
        }


class PaymentForm(forms.ModelForm):
    """Форма для отметки оплаты"""
    
    class Meta:
        model = Payment
        fields = ['amount', 'payment_date', 'payment_method', 'notes']
        widgets = {
            'amount': forms.NumberInput(attrs={
                'class': 'form-input',
                'min': '0.01',
                'step': '0.01',
                'placeholder': '0.00'
            }),
            'payment_date': forms.DateInput(attrs={
                'class': 'form-input',
                'type': 'date'
            }),
            'payment_method': forms.Select(attrs={
                'class': 'form-input',
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
        if lesson and student:
            # Устанавливаем стоимость занятия по умолчанию
            if lesson.lesson_price > 0:
                self.fields['amount'].initial = lesson.lesson_price
        if not self.fields['payment_date'].initial:
            self.fields['payment_date'].initial = timezone.now().date()


class ClearAllDebtsForm(forms.Form):
    """Форма для погашения всех долгов ученика"""
    payment_method = forms.ChoiceField(
        choices=Payment.PAYMENT_METHOD_CHOICES,
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
        label='Дата оплаты',
        initial=timezone.now().date()
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