/// The tools MILA can actually run from the phone.
///
/// Agentic OS exposes far more, but everything here shares one property: it
/// runs in a single step against the signed-in account's own desk, with no
/// confirmation round trip and no reach beyond the owner. Calendar writes and
/// ERP actions are deliberately absent — those touch other people and need the
/// approval UI the dashboard has.
///
/// Names must match the Agentic OS action names exactly: they are sent both as
/// Gemini function declarations and, on `/api/mila/voice-instruction`, as the
/// list that decides which parts of the shared prompt this device is told about.
library;

const List<String> milaPersonalToolNames = [
  'get_my_day_plan',
  'list_my_tasks',
  'create_my_task',
  'update_my_task',
  'list_my_notes',
  'save_my_note',
  'remind_me',
  'list_my_reminders',
  'cancel_reminder',
  'list_my_calendar',
];

/// Gemini Live function declarations for [milaPersonalToolNames], plus the
/// long-standing Hermes hand-off, which keeps its confirmation-in-chat flow.
const List<Map<String, dynamic>> milaLiveFunctionDeclarations = [
  {
    'name': 'delegate_to_hermes',
    'description':
        'Propose a concrete task for Hermes Agentic OS. The user must approve it in the MILA chat before execution.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'title': {'type': 'STRING', 'description': 'Short task title'},
        'details': {
          'type': 'STRING',
          'description': 'Context, constraints and definition of done',
        },
      },
      'required': ['title'],
    },
  },
  {
    'name': 'get_my_day_plan',
    'description':
        'Read the live plan for today: calendar events, focus blocks built from open tasks, and alerts about overdue tasks, clashing meetings and ERP problems. Use it for any question about the day, the schedule or what to do next, and never answer those from memory.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'refresh': {
          'type': 'BOOLEAN',
          'description': 'Force a fresh ERP read instead of the cached digest',
        },
      },
    },
  },
  {
    'name': 'list_my_tasks',
    'description':
        "Read the owner's private tasks. These are separate from Hermes Kanban tasks.",
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'status': {'type': 'STRING', 'description': 'todo, doing or done'},
        'limit': {'type': 'INTEGER'},
      },
    },
  },
  {
    'name': 'create_my_task',
    'description':
        'Add a private task. Runs immediately, with no confirmation step.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'title': {'type': 'STRING'},
        'detail': {'type': 'STRING'},
        'priority': {'type': 'STRING', 'description': 'low, normal or high'},
        'dueDate': {'type': 'STRING', 'description': 'YYYY-MM-DD'},
      },
      'required': ['title'],
    },
  },
  {
    'name': 'update_my_task',
    'description':
        'Change a private task: close it, move its due date or change its priority.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'taskId': {'type': 'STRING'},
        'title': {'type': 'STRING'},
        'status': {'type': 'STRING', 'description': 'todo, doing or done'},
        'priority': {'type': 'STRING', 'description': 'low, normal or high'},
        'dueDate': {'type': 'STRING', 'description': 'YYYY-MM-DD'},
      },
      'required': ['taskId'],
    },
  },
  {
    'name': 'list_my_notes',
    'description': "Read the owner's private notes, optionally filtered.",
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'query': {'type': 'STRING'},
        'limit': {'type': 'INTEGER'},
      },
    },
  },
  {
    'name': 'save_my_note',
    'description':
        'Save a private note — a decision, a number, something said in passing worth keeping. Runs immediately.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'title': {'type': 'STRING'},
        'content': {'type': 'STRING'},
      },
      'required': ['title', 'content'],
    },
  },
  {
    'name': 'remind_me',
    'description':
        'Set a reminder that fires at a specific moment and arrives as a phone notification. Use it for "напомни мне в 15:00" or "через час", and always compute the absolute time from the current local time.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'title': {'type': 'STRING'},
        'body': {'type': 'STRING'},
        'dueAt': {
          'type': 'STRING',
          'description':
              'Absolute ISO 8601 timestamp with offset, for example 2026-08-10T15:00:00+05:00',
        },
        'priority': {'type': 'STRING', 'description': 'normal or high'},
      },
      'required': ['title', 'dueAt'],
    },
  },
  {
    'name': 'list_my_reminders',
    'description': 'List reminders that have not fired yet.',
    'parameters': {'type': 'OBJECT', 'properties': {}},
  },
  {
    'name': 'cancel_reminder',
    'description': 'Cancel a pending reminder by id.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'reminderId': {'type': 'STRING'},
      },
      'required': ['reminderId'],
    },
  },
  {
    'name': 'list_my_calendar',
    'description':
        'Read real calendar events in a time range. Reading only: creating or moving an event has to be done in the Agentic OS dashboard.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'from': {'type': 'STRING', 'description': 'ISO 8601, defaults to now'},
        'to': {
          'type': 'STRING',
          'description': 'ISO 8601, defaults to a week ahead',
        },
        'limit': {'type': 'INTEGER'},
      },
    },
  },
];
