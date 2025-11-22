# ✅ Проверка готовности к продакшену

## Проверено и исправлено:

### ✅ База данных
- [x] Добавлена автоматическая поддержка PostgreSQL через `DATABASE_URL`
- [x] SQLite используется для локальной разработки (если `DATABASE_URL` не установлен)
- [x] PostgreSQL используется автоматически в продакшене (Railway/Render устанавливают `DATABASE_URL`)
- [x] Добавлен `dj-database-url==2.1.0` в `requirements.txt`
- [x] Добавлен `psycopg2-binary==2.9.9` в `requirements.txt`

### ✅ Безопасность
- [x] `SECRET_KEY` читается из переменных окружения
- [x] `DEBUG` читается из переменных окружения (по умолчанию `True` для разработки)
- [x] `ALLOWED_HOSTS` настраивается через переменные окружения
- [x] `CSRF_TRUSTED_ORIGINS` настраивается через переменные окружения
- [x] В продакшене (`DEBUG=False`) включены:
  - `SESSION_COOKIE_SECURE = True` - cookies только через HTTPS
  - `CSRF_COOKIE_SECURE = True` - CSRF cookies только через HTTPS
  - `SECURE_BROWSER_XSS_FILTER = True` - защита от XSS
  - `SECURE_CONTENT_TYPE_NOSNIFF = True` - защита от MIME-sniffing
  - `X_FRAME_OPTIONS = 'DENY'` - защита от clickjacking
  - `SECURE_HSTS_SECONDS = 31536000` - HSTS на 1 год
  - `SECURE_HSTS_INCLUDE_SUBDOMAINS = True`
  - `SECURE_HSTS_PRELOAD = True`

### ✅ Статические файлы
- [x] `STATIC_ROOT` настроен (`staticfiles/`)
- [x] `WhiteNoiseMiddleware` добавлен в `MIDDLEWARE`
- [x] `whitenoise==6.8.2` в `requirements.txt`
- [x] `build.sh` содержит `collectstatic --noinput`

### ✅ Деплой файлы
- [x] `Procfile` настроен: `web: gunicorn tutoring.wsgi --log-file -`
- [x] `runtime.txt` содержит `python-3.12.0`
- [x] `build.sh` содержит миграции и сборку статики
- [x] `requirements.txt` содержит все зависимости

### ✅ Переменные окружения
- [x] `.env` файл добавлен в `.gitignore`
- [x] `python-dotenv==1.2.1` в `requirements.txt`
- [x] Автоматическая загрузка `.env` в `settings.py`

### ✅ Миграции
- [x] Все миграции созданы и готовы к применению
- [x] `build.sh` содержит `python manage.py migrate`

## Что нужно сделать на Railway:

### 1. Добавить PostgreSQL (если еще не добавлен):
1. В Railway откройте ваш проект
2. Нажмите "+ New" → "Database" → "Add PostgreSQL"
3. Railway автоматически установит `DATABASE_URL` - **ничего делать не нужно!**

### 2. Установить переменные окружения:
В Settings → Environment Variables добавьте:

```
SECRET_KEY=ваш-сгенерированный-ключ
DEBUG=False
ALLOWED_HOSTS=tutoringforartak.up.railway.app
CSRF_TRUSTED_ORIGINS=https://tutoringforartak.up.railway.app
```

**Важно:** `DATABASE_URL` устанавливается автоматически при добавлении PostgreSQL - **не устанавливайте вручную!**

### 3. После деплоя:
1. Railway автоматически выполнит миграции (если настроен `build.sh`)
2. Если нет - выполните вручную через Railway Console:
   ```bash
   python manage.py migrate
   ```
3. Создайте суперпользователя:
   ```bash
   python manage.py createsuperuser
   ```

## Проверка работы:

После деплоя проверьте:
- [ ] Сайт открывается
- [ ] Форма регистрации работает (нет ошибки CSRF)
- [ ] Форма входа работает
- [ ] Статические файлы загружаются (CSS, JS)
- [ ] Можно создать ученика
- [ ] Можно создать занятие
- [ ] База данных работает (данные сохраняются)

## Важные замечания:

1. **База данных**: SQLite НЕ подходит для продакшена на Railway, так как файловая система эфемерная. Используйте PostgreSQL (Railway предоставляет бесплатно).

2. **Переменные окружения**: Все чувствительные данные (SECRET_KEY, пароли БД) должны быть в переменных окружения, НЕ в коде.

3. **DEBUG**: В продакшене ОБЯЗАТЕЛЬНО `DEBUG=False` для безопасности.

4. **CSRF_TRUSTED_ORIGINS**: Обязательно укажите ваш домен с `https://` для работы форм.

5. **DATABASE_URL**: Не устанавливайте вручную - Railway/Render делают это автоматически при добавлении PostgreSQL.

## Команды для проверки локально:

```bash
# Проверка настроек Django
python manage.py check --deploy

# Проверка миграций
python manage.py showmigrations

# Сборка статических файлов
python manage.py collectstatic --noinput

# Тест запуска сервера
python manage.py runserver
```

