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

## Важные шаги перед деплоем

1. **Сгенерируйте новый SECRET_KEY**:
   ```bash
   python manage.py shell -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
   ```

2. **Соберите статические файлы** (на некоторых платформах делается автоматически):
   ```bash
   python manage.py collectstatic --noinput
   ```

3. **Выполните миграции**:
   ```bash
   python manage.py migrate
   ```

4. **Создайте суперпользователя**:
   ```bash
   python manage.py createsuperuser
   ```

## Переменные окружения

Установите следующие переменные окружения на вашей платформе:

- `SECRET_KEY` - секретный ключ Django (обязательно!)
- `DEBUG=False` - отключите режим отладки
- `ALLOWED_HOSTS` - список разрешенных доменов через запятую

## База данных

По умолчанию используется SQLite. Для production рекомендуется использовать PostgreSQL:
- Railway и Render предоставляют бесплатные PostgreSQL базы
- Обновите `DATABASES` в settings.py для использования PostgreSQL

