from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.authtoken.views import obtain_auth_token
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .forms import TutorRegistrationForm

# POST /api/v1/auth/login/ — {username, password} -> {token}
login_view = obtain_auth_token


class RegisterView(APIView):
    """POST /api/v1/auth/register/ — регистрация репетитора (тот же TutorRegistrationForm,
    что и веб-регистрация), возвращает токен сразу после создания аккаунта."""
    permission_classes = [AllowAny]

    def post(self, request):
        form = TutorRegistrationForm(request.data)
        if not form.is_valid():
            return Response(form.errors, status=status.HTTP_400_BAD_REQUEST)
        user = form.save()
        token, _ = Token.objects.get_or_create(user=user)
        return Response({'token': token.key}, status=status.HTTP_201_CREATED)
