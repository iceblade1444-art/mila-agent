/// Models for the personal day plan and reminders, as `get_my_day_plan` and
/// `list_my_reminders` return them. The plan is built server-side from the real
/// calendar, open tasks and live ERP flags; the phone renders it and adds
/// nothing of its own.
library;

String _s(dynamic value) => (value ?? '').toString();

class AgendaItem {
  const AgendaItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.start,
    required this.end,
    required this.allDay,
  });

  final String id;

  /// `event` from the calendar, `focus` — a block the planner carved out of
  /// the day for an open task.
  final String kind;
  final String title;
  final String detail;
  final String start;
  final String end;
  final bool allDay;

  factory AgendaItem.fromJson(Map<String, dynamic> json) => AgendaItem(
    id: _s(json['id']),
    kind: _s(json['kind']),
    title: _s(json['title']),
    detail: _s(json['detail']),
    start: _s(json['start']),
    end: _s(json['end']),
    allDay: json['allDay'] == true,
  );
}

class DayAlert {
  const DayAlert({required this.id, required this.level, required this.title});

  final String id;

  /// `urgent` demands attention now, everything else is `normal`.
  final String level;
  final String title;

  factory DayAlert.fromJson(Map<String, dynamic> json) => DayAlert(
    id: _s(json['id']),
    level: _s(json['level']),
    title: _s(json['title']),
  );
}

class DayPlan {
  const DayPlan({
    required this.date,
    required this.summary,
    required this.agenda,
    required this.alerts,
    required this.calendarConnected,
  });

  final String date;
  final String summary;
  final List<AgendaItem> agenda;
  final List<DayAlert> alerts;
  final bool calendarConnected;

  factory DayPlan.fromJson(Map<String, dynamic> json) => DayPlan(
    date: _s(json['date']),
    summary: _s(json['summary']),
    agenda: ((json['agenda'] as List?) ?? const [])
        .whereType<Map>()
        .map((value) => AgendaItem.fromJson(value.cast<String, dynamic>()))
        .toList(growable: false),
    alerts: ((json['alerts'] as List?) ?? const [])
        .whereType<Map>()
        .map((value) => DayAlert.fromJson(value.cast<String, dynamic>()))
        .toList(growable: false),
    calendarConnected: (json['calendar'] as Map?)?['connected'] == true,
  );
}

class PersonalReminder {
  const PersonalReminder({
    required this.id,
    required this.title,
    required this.dueAt,
  });

  final String id;
  final String title;
  final String dueAt;

  factory PersonalReminder.fromJson(Map<String, dynamic> json) =>
      PersonalReminder(
        id: _s(json['id']),
        title: _s(json['title']),
        dueAt: _s(json['dueAt']),
      );
}
