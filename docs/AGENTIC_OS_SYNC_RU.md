# MILA и Agentic OS: карта синхронизации

## Роли компонентов

```text
MILA Mobile
  |  MILA session token
  v
MILA Backend (/mila)
  |  private AGENTIC_OS_TOKEN
  v
Agentic OS API
  |  shared board and vault
  +--> Hermes Kanban --> Scout / Scribe / Reach / Dev
  +--> Obsidian Vault
```

- **MILA Mobile** отвечает за голос, чат, камеру, файлы, подтверждения и
  компактное отображение результата.
- **MILA Backend** выдаёт короткоживущие Gemini Live tokens и проксирует только
  разрешённые мобильные операции. Секрет Agentic OS не попадает в приложение.
- **Hermes** принимает подтверждённую цель в `triage`, планирует её и назначает
  профиль. Специалисты работают в отдельных профилях и возвращают handoff.
- **Agentic OS** остаётся источником истины для Kanban и административной
  панелью. **Obsidian** остаётся источником синхронизированной памяти.

## Подключение устройства

1. Creator создаёт восьмизначный одноразовый код в Agentic OS:
   `Integrations -> MILA Voice -> Connect mobile app`.
2. Телефон отправляет код в `POST /v1/auth/device`.
3. MILA backend удаляет использованный код и возвращает мобильную сессию.
4. Сессия хранится в Android Keystore или iOS Keychain.
5. Ни Gemini API key, ни `AGENTIC_OS_TOKEN` телефону не передаются.

## Синхронизация задач

- `GET /v1/tasks` читает общую доску Hermes.
- `POST /v1/tasks` создаёт подтверждённую цель в `triage` у `default` Hermes.
- Телефон обновляет список каждые восемь секунд и при ручном refresh.
- В карточке видны `status`, `assignee`, описание и последний handoff.
- Завершение с телефона поддерживается через ограниченный `PATCH`.
- До подключения Agentic OS задачи остаются локальными и явно помечаются.

## Голос и подтверждения

Gemini Live имеет функцию `delegate_to_hermes`. Она не запускает работу сразу:
MILA создаёт action card в чате и сообщает голосом, что требуется подтверждение.
Только после подтверждения задача отправляется Hermes.

## Синхронизация памяти

- Для мобильной сессии используется отдельная заметка
  `MILA/mobile-<anonymous-owner-hash>.md`.
- Добавление записывает Markdown-строку с категорией.
- Удаление пишет tombstone, поэтому удалённая память не появляется снова.
- После загрузки серверные записи объединяются с локальными без дублей.
- Содержимое памяти никогда не включается в telemetry или connection code.

## Серверная конфигурация

В `/opt/mila/backend/.env` должны находиться:

```dotenv
AGENTIC_OS_URL=http://172.16.10.6:8787
AGENTIC_OS_TOKEN=<same value as Agentic OS AUTH_TOKEN>
```

После изменения backend:

```bash
cd /opt/mila
./deploy.sh
```

## Следующие этапы

- Push notifications о `done`, `blocked` и approval gates.
- Детальный экран задачи с комментариями и дочерними задачами.
- История устройств и отзыв отдельной мобильной сессии.
- Фоновая синхронизация при восстановлении сети.
