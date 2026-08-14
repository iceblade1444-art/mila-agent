import 'package:flutter_test/flutter_test.dart';
import 'package:mila/services/agentic/day_plan_models.dart';
import 'package:mila/services/agentic/team_chat_models.dart';

void main() {
  // These payloads mirror what the Agentic OS messenger and personal actions
  // actually return — publicConversation/publicMessage in server/lib/messenger.js
  // and get_my_day_plan in server/lib/mila-actions.js. If a field is renamed
  // server-side, this is the test that should notice, not a user mid-call.
  test('conversation list parses the server shape', () {
    final home = TeamChatHome.fromJson({
      'me': {'id': 'creator', 'name': 'Бахадыр', 'role': 'Creator'},
      'people': [
        {
          'id': 'usr_2',
          'name': 'Шавкат',
          'handle': 'шавкат',
          'role': 'Member',
          'kind': 'person',
          'online': true,
        },
        {
          'id': 'agent:mila',
          'name': 'Mila',
          'role': 'Assistant',
          'kind': 'agent',
          'online': true,
        },
      ],
      'conversations': [
        {
          'id': 'conv_1',
          'kind': 'channel',
          'name': 'производство',
          'topic': '',
          'memberIds': ['creator', 'usr_2', 'agent:mila'],
          'unread': 3,
          'mentioned': true,
          'lastMessage': {
            'id': 'msg_9',
            'authorId': 'usr_2',
            'authorName': 'Шавкат',
            'kind': 'user',
            'text': 'Отгрузка готова',
            'createdAt': '2026-08-14T05:00:00.000Z',
            'attachments': [],
            'reactions': {},
            'mentions': [],
            'replyTo': null,
          },
          'lastActivityAt': '2026-08-14T05:00:00.000Z',
        },
        {
          'id': 'conv_2',
          'kind': 'direct',
          // The server titles a direct thread by the other person before it
          // ever reaches a client — the phone must not need to.
          'name': 'Шавкат',
          'otherId': 'usr_2',
          'memberIds': ['creator', 'usr_2'],
          'unread': 0,
          'mentioned': false,
          'lastMessage': null,
          'lastActivityAt': '2026-08-13T10:00:00.000Z',
        },
      ],
    });

    expect(home.meId, 'creator');
    expect(home.people, hasLength(2));
    expect(home.people.last.isAgent, isTrue);
    expect(home.conversations.first.unread, 3);
    expect(home.conversations.first.mentioned, isTrue);
    expect(home.conversations.first.lastMessage?.text, 'Отгрузка готова');
    expect(home.conversations.last.name, 'Шавкат');
    expect(home.conversations.last.lastMessage, isNull);
  });

  test('a deleted message keeps its place but carries no content', () {
    final message = TeamMessage.fromJson({
      'id': 'msg_1',
      'conversationId': 'conv_1',
      'authorId': 'usr_2',
      'authorName': 'Шавкат',
      'kind': 'user',
      'text': '',
      'deleted': true,
      'attachments': [],
      'reactions': {},
      'mentions': [],
      'replyTo': null,
      'createdAt': '2026-08-14T05:00:00.000Z',
    });
    expect(message.deleted, isTrue);
    expect(message.text, isEmpty);
  });

  test('the day plan parses agenda, alerts and the calendar flag', () {
    final plan = DayPlan.fromJson({
      'date': '2026-08-14',
      'timezone': 'Asia/Tashkent',
      'summary': 'Сегодня 2 встречи и 1 срочный сигнал.',
      'agenda': [
        {
          'id': 'evt_1',
          'kind': 'event',
          'title': 'Встреча с закупщиком',
          'detail': 'офис',
          'start': '2026-08-14T05:00:00.000Z',
          'end': '2026-08-14T06:00:00.000Z',
          'allDay': false,
          'source': 'calendar',
        },
        {
          'id': 'focus_t1',
          'kind': 'focus',
          'title': 'Проверить отгрузку',
          'detail': '',
          'start': '2026-08-14T07:00:00.000Z',
          'end': '2026-08-14T08:00:00.000Z',
          'allDay': false,
          'source': 'task',
          'taskId': 't1',
          'priority': 'high',
        },
      ],
      'alerts': [
        {
          'id': 'erp_late',
          'level': 'urgent',
          'source': 'erp',
          'title': 'Просрочен заказ №451',
          'route': '#/erp',
        },
      ],
      'calendar': {'connected': true},
      'stats': {'meetings': 1},
      'workday': {'start': '09:00', 'end': '18:00'},
    });

    expect(plan.summary, contains('встречи'));
    expect(plan.agenda, hasLength(2));
    expect(plan.agenda.first.kind, 'event');
    expect(plan.agenda.last.kind, 'focus');
    expect(plan.alerts.single.level, 'urgent');
    expect(plan.calendarConnected, isTrue);
  });

  test('a reminder needs nothing beyond id, title and time', () {
    final reminder = PersonalReminder.fromJson({
      'id': 'rem_1',
      'title': 'Позвонить на фабрику',
      'dueAt': '2026-08-14T10:00:00.000Z',
      'createdAt': '2026-08-14T05:00:00.000Z',
    });
    expect(reminder.id, 'rem_1');
    expect(reminder.title, isNotEmpty);
    expect(reminder.dueAt, isNotEmpty);
  });
}
