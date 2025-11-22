# ✅ Чеклист перед деплоем

## Обязательные шаги:

### 1. Установите переменные окружения на вашей платформе:

- [ ] **SECRET_KEY** - сгенерируйте новый ключ:
  ```bash
  python manage.py shell -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
  ```

- [ ] **DEBUG=False** - для продакшена

- [ ] **ALLOWED_HOSTS** - ваш домен (например: `yourdomain.com,www.yourdomain.com`)

- [ ] **CSRF_TRUSTED_ORIGINS** - ваш домен с https:// (например: `https://your-app.railway.app`)

### 2. Проверьте файлы:

- [ ] `requirements.txt` содержит все зависимости
- [ ] `Procfile` настроен для вашей платформы
- [ ] `build.sh` (если используется) настроен правильно

### 3. После деплоя выполните:

- [ ] Миграции: `python manage.py migrate`
- [ ] Соберите статические файлы: `python manage.py collectstatic --noinput`
- [ ] Создайте суперпользователя: `python manage.py createsuperuser`

### 4. Проверьте работу:

- [ ] Сайт открывается
- [ ] Статические файлы загружаются (CSS, JS)
- [ ] Можно войти в систему
- [ ] Можно создать ученика
- [ ] Можно создать занятие

## Полезные команды:

```bash
# Проверка настроек Django
python manage.py check --deploy

# Сборка статических файлов
python manage.py collectstatic --noinput

# Миграции
python manage.py migrate

# Создание суперпользователя
python manage.py createsuperuser
```

## Где установить переменные окружения:

- **Railway**: Settings → Environment Variables
- **Render**: Environment → Environment Variables
- **Heroku**: `heroku config:set KEY=value`
- **PythonAnywhere**: Web → Web app → Environment variables

