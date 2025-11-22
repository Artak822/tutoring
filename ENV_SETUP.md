# Настройка переменных окружения для деплоя

## Важно перед деплоем!

Перед развертыванием приложения в продакшене необходимо установить следующие переменные окружения:

### Обязательные переменные:

1. **SECRET_KEY** - секретный ключ Django
   - Сгенерируйте новый ключ командой:
     ```bash
     python manage.py shell -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
     ```
   - Или используйте онлайн-генератор Django secret key
   - **НИКОГДА не используйте ключ из settings.py в продакшене!**

2. **DEBUG** - режим отладки
   - Для продакшена: `DEBUG=False`
   - Для разработки: `DEBUG=True`

3. **ALLOWED_HOSTS** - разрешенные домены
   - Укажите ваш домен через запятую (без пробелов)
   - Пример: `ALLOWED_HOSTS=yourdomain.com,www.yourdomain.com,your-app.railway.app`

### Для локальной разработки (опционально):

Создайте файл `.env` в корне проекта:

```env
SECRET_KEY=ваш-секретный-ключ-для-разработки
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1
```

**Важно:** Файл `.env` уже добавлен в `.gitignore` и не будет загружен в репозиторий.

### Где установить переменные окружения:

#### Railway:
1. Откройте ваш проект на Railway
2. Перейдите в Settings → Environment Variables
3. Добавьте все переменные

#### Render:
1. Откройте ваш сервис на Render
2. Перейдите в Environment
3. Добавьте все переменные

#### Heroku:
```bash
heroku config:set SECRET_KEY=ваш-секретный-ключ
heroku config:set DEBUG=False
heroku config:set ALLOWED_HOSTS=ваш-домен.herokuapp.com
```

#### PythonAnywhere:
1. Откройте Web → Web app → Environment variables
2. Добавьте все переменные

### Проверка перед деплоем:

1. ✅ SECRET_KEY установлен и отличается от дефолтного
2. ✅ DEBUG=False для продакшена
3. ✅ ALLOWED_HOSTS содержит ваш домен
4. ✅ Статические файлы собраны (`python manage.py collectstatic`)
5. ✅ Миграции выполнены (`python manage.py migrate`)

