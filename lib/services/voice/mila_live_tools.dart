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
  // Company knowledge is read-only from a phone: looking up a price or who to
  // ask is the point; rewriting the company's own pages is not.
  'search_company_knowledge',
  'read_company_knowledge',
  'list_company_knowledge',
  // The owner's private profile: hers alone, stored per account outside the
  // shared vault, and only ever what they said about themselves.
  'remember_about_me',
  'read_about_me',
  'forget_about_me',
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
    'name': 'remember_about_me',
    'description':
        "Remember one fact the owner told you about themselves — a person they work with and how, a preference, a standing commitment, a date that matters. Only ever record what they actually said or confirmed: never your own conclusions, and never something inferred from their behaviour. Runs immediately; say back what you wrote.",
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'fact': {'type': 'STRING', 'description': "One short sentence, in the owner's own words where possible"},
        'category': {'type': 'STRING', 'description': 'people, preferences, commitments, dates or other'},
      },
      'required': ['fact'],
    },
  },
  {
    'name': 'read_about_me',
    'description':
        'Read what the owner has told you about themselves, to be genuinely useful. Never repeat any of it to anyone else.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'category': {'type': 'STRING', 'description': 'people, preferences, commitments, dates or other'},
      },
    },
  },
  {
    'name': 'forget_about_me',
    'description': 'Remove one fact from the personal profile when the owner asks you to forget it or says it is wrong.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'factId': {'type': 'STRING'},
      },
      'required': ['factId'],
    },
  },
  {
    'name': 'search_company_knowledge',
    'description':
        'Search the Milana company knowledge base: prices and terms, fabrics and size charts, export rules per country, who is responsible for what, and standard answers to customer questions. Use it before answering any question about the business that is not live ERP data, and never answer such a question from memory.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'query': {'type': 'STRING', 'description': "What to look for, in the user's own words"},
      },
      'required': ['query'],
    },
  },
  {
    'name': 'read_company_knowledge',
    'description': 'Read one whole page of the company knowledge base.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'page': {'type': 'STRING', 'description': 'products-and-prices, who-does-what, export-by-country or customer-questions'},
      },
      'required': ['page'],
    },
  },
  {
    'name': 'list_company_knowledge',
    'description': 'List the pages of the company knowledge base and what each one holds.',
    'parameters': {'type': 'OBJECT', 'properties': {}},
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
