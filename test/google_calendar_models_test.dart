import 'package:flutter_test/flutter_test.dart';
import 'package:mila/services/agentic/agentic_os_service.dart';

void main() {
  test('Google Calendar status preserves server connection state', () {
    final status = GoogleCalendarStatus.fromJson({
      'configured': true,
      'connected': true,
      'scopes': ['calendar.readonly'],
      'connectedAt': '2026-07-29T08:00:00.000Z',
    });

    expect(status.configured, isTrue);
    expect(status.connected, isTrue);
    expect(status.scopes, ['calendar.readonly']);
    expect(status.connectedAt, DateTime.utc(2026, 7, 29, 8));
  });

  test('Google Calendar feed parses timed and all-day events', () {
    final feed = GoogleCalendarFeed.fromJson({
      'timeZone': 'Asia/Tashkent',
      'syncedAt': '2026-07-29T08:05:00.000Z',
      'events': [
        {
          'id': 'timed',
          'title': 'Product review',
          'start': '2026-07-30T10:00:00+05:00',
          'end': '2026-07-30T11:00:00+05:00',
          'allDay': false,
          'location': 'Agentic OS',
        },
        {
          'id': 'all-day',
          'title': 'Launch day',
          'start': '2026-08-01',
          'end': '2026-08-02',
          'allDay': true,
        },
      ],
    });

    expect(feed.timeZone, 'Asia/Tashkent');
    expect(feed.events, hasLength(2));
    expect(feed.events.first.title, 'Product review');
    expect(feed.events.first.location, 'Agentic OS');
    expect(feed.events.last.allDay, isTrue);
  });
}
