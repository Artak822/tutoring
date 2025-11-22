from django.urls import path
from django.contrib.auth.views import LogoutView
from django.views.decorators.http import require_http_methods
from . import views

urlpatterns = [
    path('', views.dashboard, name='dashboard'),
    path('register/', views.register, name='register'),
    path('login/', views.TutorLoginView.as_view(), name='login'),
    path('logout/', LogoutView.as_view(next_page='login'), name='logout'),
    path('students/', views.student_list, name='student_list'),
    path('student/create/', views.student_create, name='student_create'),
    path('student/<int:pk>/', views.student_detail, name='student_detail'),
    path('student/<int:pk>/edit/', views.student_edit, name='student_edit'),
    path('student/<int:pk>/delete/', views.student_delete, name='student_delete'),
    path('calendar/', views.calendar_view, name='calendar'),
    path('lessons/', views.lesson_list, name='lesson_list'),
    path('lesson/create/', views.lesson_create, name='lesson_create'),
    path('lesson/<int:pk>/', views.lesson_detail, name='lesson_detail'),
    path('lesson/<int:pk>/edit/', views.lesson_edit, name='lesson_edit'),
    path('lesson/<int:pk>/delete/', views.lesson_delete, name='lesson_delete'),
    path('lesson/<int:lesson_pk>/attendance/<int:student_pk>/', views.mark_attendance, name='mark_attendance'),
    path('lesson/<int:lesson_pk>/payment/<int:student_pk>/', views.mark_payment, name='mark_payment'),
]

