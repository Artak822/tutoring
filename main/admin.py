from django.contrib import admin
from .models import Student, Lesson, Attendance, Payment, Tutor


@admin.register(Tutor)
class TutorAdmin(admin.ModelAdmin):
    list_display = ('user', 'phone', 'created_at')
    list_filter = ('created_at',)
    search_fields = ('user__username', 'user__first_name', 'user__last_name', 'phone')
    ordering = ('-created_at',)


@admin.register(Student)
class StudentAdmin(admin.ModelAdmin):
    list_display = ('last_name', 'first_name', 'tutor', 'grade', 'phone', 'telegram', 'is_active', 'created_at')
    list_filter = ('is_active', 'created_at', 'grade', 'tutor')
    search_fields = ('first_name', 'last_name', 'phone', 'telegram')
    ordering = ('last_name', 'first_name')


@admin.register(Lesson)
class LessonAdmin(admin.ModelAdmin):
    list_display = ('get_students', 'tutor', 'date', 'time', 'duration', 'lesson_price', 'subject', 'created_at')
    list_filter = ('date', 'created_at', 'students', 'tutor')
    search_fields = ('students__first_name', 'students__last_name', 'subject')
    ordering = ('-date', '-time')
    date_hierarchy = 'date'
    filter_horizontal = ('students',)
    
    def get_students(self, obj):
        return ", ".join([str(s) for s in obj.students.all()])
    get_students.short_description = 'Ученики'


@admin.register(Attendance)
class AttendanceAdmin(admin.ModelAdmin):
    list_display = ('student', 'lesson', 'status', 'created_at')
    list_filter = ('status', 'created_at')
    search_fields = ('student__first_name', 'student__last_name')
    ordering = ('-lesson__date', '-lesson__time')


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ('student', 'lesson', 'amount', 'payment_date', 'created_at')
    list_filter = ('payment_date', 'created_at')
    search_fields = ('student__first_name', 'student__last_name')
    ordering = ('-payment_date', '-created_at')
    date_hierarchy = 'payment_date'

