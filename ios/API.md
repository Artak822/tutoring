# Контракт API v1.0

Базовый путь: `/api/v1/`. Все ответы — JSON, кодировка UTF-8.

## Аутентификация

Токен DRF в заголовке каждого запроса:

```
Authorization: Token 9944b09199c62bcf9418ad846dd0e4bbdfc6ee4b
```

| Метод | Путь | Тело | Ответ |
|-------|------|------|-------|
| POST | `auth/login/` | `{username, password}` | `{token}` |
| POST | `auth/register/` | `{username, email, first_name, last_name, phone?, password1, password2}` | `201 {token}` |
| POST | `auth/logout/` | — | `204` (токен удаляется) |

Ошибки: `401` — токена нет или он отозван; `403` — пользователь без профиля репетитора.

## Правила, важные для клиента

- **Деньги — всегда строки с двумя знаками**: `"1500.00"`. Парсить в `Decimal`, никогда в `Double`.
- **Даты** — `"2026-07-25"`, **время** — `"15:00:00"`. Без часовых поясов: это календарная дата занятия, конвертировать её не нужно.
- **Баланс предоплаты клиент не считает сам.** `prepaid_balance` только для чтения; после любого действия берём значение из ответа сервера.
- **Списки пагинированы** (`count`, `next`, `previous`, `results`), размер — `?page_size=` до 200. Исключение — `lessons/calendar/`, там пагинации нет.

## Справочники

`GET meta/` → `api_version`, `currency`, `payment_methods`, `cancellation_reasons`,
`lesson_statuses`, `attendance_statuses`, `recurring_periods`. Каждый справочник —
массив `{value, label}`; подписи брать отсюда, а не хардкодить в приложении.

## Профиль и сводка

| Метод | Путь | Ответ |
|-------|------|-------|
| GET | `me/` | `{id, username, first_name, last_name, phone, created_at, students_count}` |
| GET | `dashboard/` | `students_count`, `profit_all_time/month/week`, `lessons_all_time/month/week` |
| GET | `reports/profit/?start_date=&end_date=` | `total_profit`, `profit_by_day[]`, `profit_by_student[]`, `profit_by_method[]`, `lessons_count`, `avg_per_lesson`, `avg_per_day`, `days_count` |

По умолчанию отчёт строится с первого числа текущего месяца по сегодня.
Перепутанные местами даты сервер меняет сам, ошибку не возвращает.

## Ученики

| Метод | Путь | Назначение |
|-------|------|------------|
| GET | `students/?is_active=&group=&search=&page_size=` | список; `search` ищет по имени, фамилии, телефону, telegram |
| POST/GET/PATCH/DELETE | `students/`, `students/{id}/` | CRUD |
| GET | `students/debts/` | `{total_debt, students[{id, first_name, last_name, phone, debt, prepaid_balance}]}`, отсортировано по убыванию долга |
| POST | `students/{id}/clear-debts/` | `{payment_method: cash\|transfer, payment_date?, notes?}` → сначала гасит с предоплаты, остаток — платежами |
| POST | `students/{id}/archive/` | мягкое удаление (`is_active=false`) |
| POST | `students/{id}/restore/` | вернуть из архива |

Поле `total_debt` в карточке ученика считается только по занятиям, где он был отмечен
присутствующим и оплаты нет. `prepaid_balance` — только для чтения.

## Занятия

| Метод | Путь | Назначение |
|-------|------|------------|
| GET | `lessons/?date_from=&date_to=&student=&status=` | список с фильтрами |
| GET | `lessons/calendar/?year=&month=` | весь месяц одним ответом, без пагинации |
| POST/GET/PATCH/DELETE | `lessons/`, `lessons/{id}/` | CRUD |
| GET | `lessons/{id}/state/` | посещаемость и оплата всех учеников занятия |
| POST | `lessons/recurring/` | `{students[], start_date, time, duration, lesson_price, period, notes?}` → `201 {created_count, lessons[]}` |
| POST | `lessons/{id}/quick-action/` | см. ниже |
| POST | `lessons/{id}/cancel/` | `{reason?, note?}` — возвращает списанные деньги на баланс |
| POST | `lessons/{id}/restore/` | снять отмену |

`status` и `cancellation_*` через PATCH не меняются — только через `cancel/` и `restore/`,
иначе деньги не вернутся ученикам на предоплату.

### Быстрое закрытие занятия

`POST lessons/{id}/quick-action/`

```json
{"action": "mark_present", "student": 12}
{"action": "mark_absent",  "student": 12}
{"action": "add_payment",  "student": 12, "amount": "1500", "method": "cash"}
{"action": "reset_payment","student": 12}
```

Ответ всегда одинаковый:

```json
{
  "attendance_status": "present",
  "payment": {"amount": "1500.00", "method": "cash", "method_display": "Наличные", "is_balance": false},
  "student_balance": "500.00",
  "lesson_price": "1000.00"
}
```

Поведение сервера, которое клиент **не должен повторять у себя**:

- `mark_present` — если на балансе хватает денег, оплата спишется автоматически (`is_balance: true`).
- `add_payment` — переплата уходит на баланс предоплаты, затем автоматически гасятся старые долги.
- `mark_absent` — оплата отменяется, списанное с баланса возвращается.
- `reset_payment` — удаляет оплату, при необходимости возвращая деньги на баланс.

### Состояние занятия

`GET lessons/{id}/state/`

```json
{
  "lesson_id": 42, "lesson_price": "1000.00", "status": "scheduled",
  "present_count": 1, "total_price": "1000.00",
  "students": [
    {"student_id": 12, "first_name": "Иван", "last_name": "Петров",
     "attendance_status": "present", "payment": {…}, "student_balance": "0.00"}
  ]
}
```

`attendance_status: null` — ученик ещё не отмечен.

## Группы

`GET/POST groups/`, `GET/PATCH/DELETE groups/{id}/` — поля `name`, `description`,
`is_active`, `students_count`.

## Изоляция данных

Каждый запрос ограничен текущим репетитором. Чужой `id` даёт `404`, а не `403` — факт
существования чужой записи не раскрывается. Попытка привязать чужого ученика к занятию
или чужую группу к ученику даёт `400` с текстом ошибки в поле соответствующего поля.
