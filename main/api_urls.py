from django.urls import path, include
from rest_framework.routers import DefaultRouter

from . import api_views, auth_views

router = DefaultRouter()
router.register('students', api_views.StudentViewSet, basename='api-student')
router.register('groups', api_views.StudentGroupViewSet, basename='api-group')
router.register('lessons', api_views.LessonViewSet, basename='api-lesson')
router.register('attendances', api_views.AttendanceViewSet, basename='api-attendance')
router.register('payments', api_views.PaymentViewSet, basename='api-payment')

urlpatterns = [
    path('auth/login/', auth_views.login_view, name='api_login'),
    path('auth/register/', auth_views.RegisterView.as_view(), name='api_register'),
    path('auth/logout/', auth_views.LogoutView.as_view(), name='api_logout'),
    path('me/', api_views.MeView.as_view(), name='api_me'),
    path('meta/', api_views.MetaView.as_view(), name='api_meta'),
    path('dashboard/', api_views.DashboardView.as_view(), name='api_dashboard'),
    path('reports/profit/', api_views.ProfitReportView.as_view(), name='api_profit_report'),
    path('', include(router.urls)),
]
