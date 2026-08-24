/// Models for the two questions the home screen now asks: what is waiting on
/// me, and what did MILA do while I was not looking.
///
/// Both come from the server already ordered and already scoped to the person
/// asking — `/api/needs-you` decides which sources a caller may see from their
/// role, and `/api/activity` takes no user parameter at all. The phone renders
/// what it is handed and adds nothing of its own, so neither list can be made
/// to show somebody else's work by anything happening here.
library;

String _s(dynamic value) => (value ?? '').toString();

/// One thing blocked on a person. Worst first, as the server sorts it.
class NeedsYouItem {
  const NeedsYouItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.route,
  });

  final String id;

  /// `blocked`, `waiting`, `overdue`, `attention` — the server's severity
  /// vocabulary, worst first. Kept as a string rather than an enum: an unknown
  /// kind from a newer server must render as a plain row, never crash the feed.
  final String kind;
  final String title;
  final String detail;
  final String route;

  factory NeedsYouItem.fromJson(Map<String, dynamic> json) => NeedsYouItem(
    id: _s(json['id']),
    kind: _s(json['kind']),
    title: _s(json['title']),
    detail: _s(json['detail'] ?? json['summary']),
    route: _s(json['route'] ?? json['href']),
  );

  /// Severity rank for anything the phone needs to order or colour itself.
  /// Unknown kinds sort last rather than first — a row nobody recognises must
  /// not claim the top of a queue.
  int get severity => switch (kind) {
    'blocked' => 0,
    'waiting' => 1,
    'overdue' => 2,
    'attention' => 3,
    _ => 4,
  };
}

class NeedsYou {
  const NeedsYou({required this.items, required this.total});

  final List<NeedsYouItem> items;
  final int total;

  static const empty = NeedsYou(items: [], total: 0);

  bool get isEmpty => items.isEmpty;

  factory NeedsYou.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((item) => NeedsYouItem.fromJson(item.cast<String, dynamic>()))
              .where((item) => item.title.isNotEmpty)
              .toList()
        : <NeedsYouItem>[];
    final total = json['total'];
    return NeedsYou(
      items: items,
      total: total is int ? total : items.length,
    );
  }
}

/// One thing MILA did. Carries a route, never content — the row is a pointer,
/// so a feed left open on a desk cannot show something that has since changed.
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.route,
    required this.at,
  });

  final String id;

  /// `reminder`, `task`, `calendar`, `message`, `brief`, `lead`, `erp`,
  /// `system`. Unknown values render with the neutral glyph.
  final String kind;
  final String title;
  final String detail;
  final String route;

  /// ISO-8601 from the server. Parsed lazily so a malformed stamp costs one
  /// row's timestamp rather than the whole list.
  final String at;

  DateTime? get when => DateTime.tryParse(at)?.toLocal();

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
    id: _s(json['id']),
    kind: _s(json['kind']),
    title: _s(json['title']),
    detail: _s(json['detail']),
    route: _s(json['route']),
    at: _s(json['at']),
  );
}
