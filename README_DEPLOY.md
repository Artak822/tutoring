# Инструкция по развертыванию

## Варианты размещения

### 1. Railway (Рекомендуется - простой и бесплатный)

1. Зарегистрируйтесь на [Railway.app](https://railway.app)
2. Подключите GitHub репозиторий или загрузите проект
3. Railway автоматически определит Django проект
4. Добавьте переменные окружения:
   - `SECRET_KEY` - сгенерируйте новый ключ (можно использовать `python manage.py shell -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"`)
   - `DEBUG=False`
   - `ALLOWED_HOSTS=ваш-домен.railway.app,ваш-домен.com`
   - `CSRF_TRUSTED_ORIGINS=https://ваш-домен.railway.app` (важно для работы форм!)
5. Railway автоматически запустит миграции и соберет статические файлы

### 2. Render.com (Бесплатный тариф)

1. Зарегистрируйтесь на [Render.com](https://render.com)
2. Создайте новый Web Service
3. Подключите GitHub репозиторий
4. Настройки:
   - Build Command: `pip install -r requirements.txt && python manage.py collectstatic --noinput`
   - Start Command: `gunicorn tutoring.wsgi`
5. Добавьте переменные окружения (Environment Variables):
   - `SECRET_KEY` - новый секретный ключ
   - `DEBUG=False`
   - `ALLOWED_HOSTS=ваш-домен.onrender.com`
   - `CSRF_TRUSTED_ORIGINS=https://ваш-домен.onrender.com` (важно для работы форм!)
6. После деплоя выполните миграции через консоль Render

### 3. PythonAnywhere (Бесплатный тариф)

1. Зарегистрируйтесь на [PythonAnywhere.com](https://www.pythonanywhere.com)
2. Загрузите проект через Git или Files
3. Создайте Web App
4. Настройте WSGI файл
5. Выполните миграции через консоль
6. Соберите статические файлы: `python manage.py collectstatic`

### 4. Heroku (Платный, но есть бесплатные альтернативы)

1. Установите Heroku CLI
2. Выполните:
   ```bash
   heroku create ваше-имя-приложения
   heroku config:set SECRET_KEY=ваш-секретный-ключ
   heroku config:set DEBUG=False
   heroku config:set ALLOWED_HOSTS=ваше-имя-приложения.herokuapp.com
   git push heroku main
   heroku run python manage.py migrate
   heroku run python manage.py createsuperuser
   ```

## ⚠️ ВАЖНО: Настройка переменных окружения перед деплоем!

**Перед развертыванием ОБЯЗАТЕЛЬНО установите переменные окружения!**

См. подробную инструкцию в файле [ENV_SETUP.md](ENV_SETUP.md)

### Быстрая настройка:

1. **Сгенерируйте новый SECRET_KEY**:
   ```bash
   python manage.py shell -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
   ```

2. **Установите переменные окружения на вашей платформе**:
   - `SECRET_KEY` - секретный ключ Django (обязательно!)
   - `DEBUG=False` - отключите режим отладки
   - `ALLOWED_HOSTS` - список разрешенных доменов через запятую (например: `yourdomain.com,www.yourdomain.com`)
   - `CSRF_TRUSTED_ORIGINS` - домен с https:// для CSRF-запросов (например: `https://your-app.railway.app`) - **ОБЯЗАТЕЛЬНО для работы форм!**

3. **Соберите статические файлы** (на некоторых платформах делается автоматически):
   ```bash
   python manage.py collectstatic --noinput
   ```

4. **Выполните миграции**:
   ```bash
   python manage.py migrate
   ```

5. **Создайте суперпользователя**:
   ```bash
   python manage.py createsuperuser
   ```

## Переменные окружения

Установите следующие переменные окружения на вашей платформе:

- `SECRET_KEY` - секретный ключ Django (обязательно! НЕ используйте дефолтный!)
- `DEBUG=False` - отключите режим отладки для продакшена
- `ALLOWED_HOSTS` - список разрешенных доменов через запятую (без пробелов)
- `CSRF_TRUSTED_ORIGINS` - домен с https:// для CSRF-запросов (например: `https://your-app.railway.app`) - **ОБЯЗАТЕЛЬНО для работы форм регистрации и входа!**

## База данных

Проект автоматически использует PostgreSQL в продакшене и SQLite для локальной разработки:

- **Локально**: SQLite (автоматически)
- **На Railway/Render**: PostgreSQL (автоматически через `DATABASE_URL`)

### Как это работает:

1. **Railway**: При добавлении PostgreSQL сервиса, Railway автоматически устанавливает переменную `DATABASE_URL`
2. **Render**: При создании PostgreSQL базы, Render автоматически устанавливает `DATABASE_URL`
3. Проект автоматически определяет наличие `DATABASE_URL` и использует PostgreSQL, если он доступен

### Важно:

- **Не нужно** вручную настраивать базу данных - все работает автоматически
- **Не нужно** устанавливать переменную `DATABASE_URL` вручную на Railway/Render - она устанавливается автоматически при добавлении PostgreSQL сервиса
- Для локальной разработки SQLite используется автоматически (если `DATABASE_URL` не установлен)

