#!/bin/bash
# Скрипт для сборки проекта на некоторых платформах
python manage.py collectstatic --noinput
python manage.py migrate

