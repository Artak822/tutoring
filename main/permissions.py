from rest_framework.permissions import BasePermission


class HasTutorProfile(BasePermission):
    """Доступ только для пользователей с привязанным профилем репетитора (main.get_tutor)."""
    message = 'Профиль репетитора не найден'

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and hasattr(request.user, 'tutor'))


class TutorScopedViewSetMixin:
    """Скоупит queryset и создание объектов текущим репетитором.
    Для моделей с прямым полем tutor (Student, StudentGroup, Lesson)."""
    permission_classes = [HasTutorProfile]

    def get_queryset(self):
        return super().get_queryset().filter(tutor=self.request.user.tutor)

    def perform_create(self, serializer):
        serializer.save(tutor=self.request.user.tutor)


class TutorScopedByLessonMixin:
    """Скоуп через lesson__tutor — для моделей без прямого поля tutor (Attendance, Payment)."""
    permission_classes = [HasTutorProfile]

    def get_queryset(self):
        return super().get_queryset().filter(lesson__tutor=self.request.user.tutor)
