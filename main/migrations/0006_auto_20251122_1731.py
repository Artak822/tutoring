# Generated migration for data migration

from django.db import migrations
from django.contrib.auth.hashers import make_password


def create_default_tutor_and_assign(apps, schema_editor):
    """Создает дефолтного репетитора и назначает его существующим записям"""
    Tutor = apps.get_model('main', 'Tutor')
    Student = apps.get_model('main', 'Student')
    Lesson = apps.get_model('main', 'Lesson')
    User = apps.get_model('auth', 'User')
    
    # Получаем или создаем дефолтного репетитора
    tutor = Tutor.objects.first()
    if not tutor:
        # Создаем дефолтного пользователя и репетитора
        default_user, created = User.objects.get_or_create(
            username='default_tutor',
            defaults={
                'first_name': 'Default',
                'last_name': 'Tutor',
                'email': 'default@tutor.com',
                'is_active': True,
                'password': make_password('changeme123'),
            }
        )
        if not created:
            # Если пользователь уже существует, обновляем пароль
            default_user.password = make_password('changeme123')
            default_user.save()
        
        tutor = Tutor.objects.create(user=default_user)
    
    # Назначаем репетитора всем существующим ученикам
    Student.objects.filter(tutor__isnull=True).update(tutor=tutor)
    
    # Назначаем репетитора всем существующим занятиям
    Lesson.objects.filter(tutor__isnull=True).update(tutor=tutor)


def reverse_migration(apps, schema_editor):
    """Обратная миграция - убирает репетитора"""
    Student = apps.get_model('main', 'Student')
    Lesson = apps.get_model('main', 'Lesson')
    
    Student.objects.all().update(tutor=None)
    Lesson.objects.all().update(tutor=None)


class Migration(migrations.Migration):

    dependencies = [
        ('main', '0005_alter_attendance_status_tutor_lesson_tutor_and_more'),
    ]

    operations = [
        migrations.RunPython(create_default_tutor_and_assign, reverse_migration),
    ]
