// Direction A, and the two mistakes it exists to correct.
//
// The first is the one a screenshot caught: the bottom bar drew five icons and
// no words. The label was in the source — destructured out of the tuple on the
// first line of the item builder — and passed to nothing, so a test that read
// the code would have found the string and concluded all was well. These pump
// the widget and look for the words on screen, which is the only version of the
// question that means anything.
//
// The second is quieter: an empty feed and a failed request look identical, and
// only one of them means "nothing is waiting for you".

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:mila/features/home/home_screen.dart';
import 'package:mila/features/more/more_screen.dart';
import 'package:mila/services/agentic/feed_controller.dart';
import 'package:mila/services/connectivity/connectivity_provider.dart';
import 'package:mila/services/storage/stores.dart';
import 'package:mila/features/shell/composer_bar.dart';
import 'package:mila/features/shell/shell_screen.dart';
import 'package:mila/core/i18n/mila_localizations.dart';
import 'package:mila/services/agentic/feed_models.dart';

// MilaLocalizations.of() falls back to English when no delegate is installed,
// so a test asserting Russian without this is asserting against the fallback
// and would pass on any string at all. Pinned, never inherited.
const _delegates = <LocalizationsDelegate<Object>>[
  MilaLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
const _ru = Locale('ru');
/// Nothing is persisted in a widget test, but profileProvider reads through a
/// store on build — without one the screen throws before drawing a row.
class _MemoryStore implements LocalStore {
  final _maps = <String, Map<String, dynamic>>{};
  final _strings = <String, String>{};

  @override
  Future<void> setAccountScope(String accountId) async {}

  @override
  List<Map<String, dynamic>> readList(String key) => const [];
  @override
  Map<String, dynamic>? readMap(String key) => _maps[key];
  @override
  String? readString(String key) => _strings[key];
  @override
  Future<void> writeString(String key, String value) async => _strings[key] = value;
  @override
  Future<void> writeJson(String key, Object value) async {}
  @override
  Future<void> delete(String key) async {
    _maps.remove(key);
    _strings.remove(key);
  }
}

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    locale: _ru,
    localizationsDelegates: _delegates,
    supportedLocales: MilaLocalizations.supportedLocales,
    home: child,
  ),
);

Future<void> _pumpShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(412, 915));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  GoRoute stub(String path) =>
      GoRoute(path: path, builder: (_, _) => const SizedBox.shrink());
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ShellScreen(shell: shell),
        branches: [
          StatefulShellBranch(routes: [stub('/home')]),
          StatefulShellBranch(routes: [stub('/tasks')]),
          StatefulShellBranch(routes: [stub('/day')]),
          StatefulShellBranch(routes: [stub('/more')]),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        locale: _ru,
        localizationsDelegates: _delegates,
        supportedLocales: MilaLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('the bottom bar', () {
    testWidgets('names every destination on screen, not only in the source', (
      tester,
    ) async {
      await _pumpShell(tester);
      // Every one of the four, including the three that are not selected. A
      // label shown only under the current tab leaves the rest a guess.
      for (final word in ['Лента', 'Задачи', 'День', 'Ещё']) {
        expect(
          find.text(word),
          findsWidgets,
          reason: '"$word" is not rendered — the bar is icons only again',
        );
      }
    });

    testWidgets('keeps the labels visible for unselected destinations', (
      tester,
    ) async {
      await _pumpShell(tester);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations, hasLength(4));
      expect(bar.selectedIndex, 0);
      // alwaysShow, not onlyShowSelected: this is the setting the whole test
      // file exists to defend.
      final theme = NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));
      expect(theme.labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
    });

    testWidgets('has exactly one door to MILA, and it is the composer', (
      tester,
    ) async {
      await _pumpShell(tester);
      // There used to be two orbs at once: one in the centre of the bar and a
      // 150px one on the home screen.
      expect(find.byType(ComposerBar), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    });

    testWidgets('every tab target is big enough to hit', (tester) async {
      await _pumpShell(tester);
      // 48 is the Material floor; this is used one-handed on a factory floor.
      for (final word in ['Лента', 'Задачи', 'День', 'Ещё']) {
        final box = tester.getRect(find.text(word).last);
        expect(box.width, greaterThan(0));
      }
      final bar = tester.getRect(find.byType(NavigationBar));
      expect(bar.height, greaterThanOrEqualTo(48));
      // The voice button's own box, not the glyph inside it: 44 square is the
      // floor for something pressed one-handed while carrying a bolt of cloth.
      final target = tester.getRect(find.byIcon(Icons.mic_none_rounded).first);
      expect(target.width, greaterThanOrEqualTo(44));
      expect(target.height, greaterThanOrEqualTo(44));
    });
  });

  group('More', () {
    testWidgets('finds a screen by a word that is not in its name', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap(const MoreScreen()));
      await tester.pump();

      // Fifteen buried screens is why this exists.
      expect(find.text('Календарь'), findsOneWidget);
      expect(find.text('Интеграции'), findsOneWidget);

      // "склад" appears only in the Integrations hint, never in its title.
      await tester.enterText(find.byType(TextField), 'склад');
      await tester.pump();
      expect(find.text('Интеграции'), findsOneWidget);
      expect(find.text('Календарь'), findsNothing);
    });

    testWidgets('says what it searched for when nothing matches', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap(const MoreScreen()));
      // The localisation delegate loads asynchronously, so the first frame is
      // still empty — without this the field does not exist yet.
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'ксилофон');
      await tester.pump();
      expect(find.text('Ничего не нашлось'), findsOneWidget);
      // The query is echoed in the message, so a typo is visible without
      // going back to the field. Matched on Text only: find.textContaining
      // also matches the EditableText the word was just typed into, so the
      // loose version of this passed even with the query dropped.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data ?? '').contains('ксилофон'),
        ),
        findsOneWidget,
      );
    });
  });

  group('feed models', () {
    test('an unknown severity sorts last rather than claiming the top', () {
      // A row nobody recognises must not outrank a blocker.
      const blocked = NeedsYouItem(
        id: '1', kind: 'blocked', title: 'a', detail: '', route: '',
      );
      const unknown = NeedsYouItem(
        id: '2', kind: 'brand-new-kind', title: 'b', detail: '', route: '',
      );
      expect(blocked.severity, lessThan(unknown.severity));
      expect(unknown.severity, 4);
    });

    test('a malformed payload yields an empty queue, never an exception', () {
      expect(NeedsYou.fromJson(const {}).items, isEmpty);
      expect(NeedsYou.fromJson(const {'items': 'not a list'}).items, isEmpty);
      // Rows with no title are dropped: a blank line in a queue is worse than
      // a shorter queue.
      final parsed = NeedsYou.fromJson(const {
        'items': [
          {'id': '1', 'kind': 'blocked', 'title': ''},
          {'id': '2', 'kind': 'waiting', 'title': 'Реальная строка'},
        ],
      });
      expect(parsed.items, hasLength(1));
      expect(parsed.items.single.title, 'Реальная строка');
    });

    test('the confirmation token survives the wire', () {
      // The widget tests build the model directly, so none of them would
      // notice this field being dropped in parsing — and a row with no token
      // renders as an ordinary line, silently un-answerable.
      final parsed = NeedsYou.fromJson(const {
        'items': [
          {
            'id': 'cnf_1', 'kind': 'confirmation',
            'title': 'Отменить встречу', 'detail': 'cancel_calendar_event',
            'route': 'personal', 'confirmationToken': 'tok_abc',
          },
        ],
      });
      expect(parsed.items.single.confirmationToken, 'tok_abc');
      expect(parsed.items.single.isConfirmation, isTrue);
    });

    test('a confirmation outranks everything else in the queue', () {
      const confirmation = NeedsYouItem(
        id: '1', kind: 'confirmation', title: 'a', detail: '', route: '',
        confirmationToken: 't',
      );
      const overdue = NeedsYouItem(
        id: '2', kind: 'overdue', title: 'b', detail: '', route: '',
      );
      // It is not late, it is stopped — and it stops for good in five minutes.
      expect(confirmation.severity, lessThan(overdue.severity));
    });

    test('total comes from the server when it says so', () {
      // The queue is capped for display; the count must still be the truth.
      final parsed = NeedsYou.fromJson(const {
        'items': [
          {'id': '1', 'kind': 'blocked', 'title': 'x'},
        ],
        'total': 9,
      });
      expect(parsed.total, 9);
      expect(parsed.items, hasLength(1));
    });

    test('a bad timestamp costs one row its clock, not the list', () {
      const entry = ActivityEntry(
        id: '1', kind: 'task', title: 't', detail: '', route: '', at: 'вчера-ish',
      );
      expect(entry.when, isNull);
      expect(entry.title, 't');
      const good = ActivityEntry(
        id: '2', kind: 'task', title: 't', detail: '', route: '',
        at: '2026-08-22T09:14:00.000Z',
      );
      expect(good.when, isNotNull);
    });
  });

  group('the feed itself', () {
    // A fixed state, so the screen is exercised with content rather than with
    // a spinner. The controller would otherwise reach the network.
    Future<void> pumpFeed(WidgetTester tester, FeedState state, GlobalKey key) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedProvider.overrideWith(
              (ref) => FeedController(ref, initial: state, autoRefresh: false),
            ),
            onlineProvider.overrideWith((ref) => Stream.value(true)),
            localStoreProvider.overrideWithValue(_MemoryStore()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(useMaterial3: true),
            locale: _ru,
            localizationsDelegates: _delegates,
            supportedLocales: MilaLocalizations.supportedLocales,
            home: RepaintBoundary(key: key, child: const HomeScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('shows what needs you above what already happened', (tester) async {
      final key = GlobalKey();
      await pumpFeed(tester, const FeedState(
        connected: true,
        needsYou: NeedsYou(total: 2, items: [
          NeedsYouItem(id: '1', kind: 'blocked', title: 'Закупка ткани: два поставщика',
            detail: 'Разница 8%, срок отличается на 5 дней', route: ''),
          NeedsYouItem(id: '2', kind: 'overdue', title: 'Партия 214 без замера',
            detail: 'Ждёт вас со вчера', route: ''),
        ]),
        activity: [
          ActivityEntry(id: 'a', kind: 'brief', title: 'Отчёт по остаткам отправлен',
            detail: 'В Telegram, вам', route: '', at: '2026-08-22T09:14:00.000Z'),
          ActivityEntry(id: 'b', kind: 'task', title: 'Три задачи из голосового',
            detail: 'Цех 2 · раскрой · упаковка', route: '', at: '2026-08-22T08:40:00.000Z'),
          ActivityEntry(id: 'c', kind: 'calendar', title: 'Встреча перенесена',
            detail: 'Ортиков — на 15:00', route: '', at: '2026-08-22T08:05:00.000Z'),
        ],
      ), key);

      expect(find.text('ТРЕБУЕТ ВАС'), findsOneWidget);
      expect(find.text('ПОКА ВАС НЕ БЫЛО'), findsOneWidget);
      expect(find.text('Закупка ткани: два поставщика'), findsOneWidget);
      expect(find.text('Отчёт по остаткам отправлен'), findsOneWidget);
      // The queue is above the history, always: it is the half that is asking
      // for something.
      expect(
        tester.getTopLeft(find.text('ТРЕБУЕТ ВАС')).dy,
        lessThan(tester.getTopLeft(find.text('ПОКА ВАС НЕ БЫЛО')).dy),
      );
      // The old screen's headline numbers are gone.
      expect(find.text('100%'), findsNothing);

      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/screen_feed.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });

    testWidgets('an action MILA is holding is answerable from the row itself', (tester) async {
      // The gate always refused to run an unconfirmed write. What it could not
      // do is be answered anywhere but by continuing the same conversation.
      await pumpFeed(tester, const FeedState(
        connected: true,
        needsYou: NeedsYou(total: 1, items: [
          NeedsYouItem(
            id: 'cnf_1', kind: 'confirmation',
            title: 'Отменить встречу с Ортиковым, 15:00',
            detail: 'cancel_calendar_event', route: 'personal',
            confirmationToken: 'tok_abc',
          ),
        ]),
      ), GlobalKey());

      expect(find.text('Отменить встречу с Ортиковым, 15:00'), findsOneWidget);
      expect(find.text('Подтвердить'), findsOneWidget);
      expect(find.text('Отклонить'), findsOneWidget);
    });

    testWidgets('an ordinary row gets no buttons', (tester) async {
      // Only a staged action is a question. An overdue task is not something
      // to approve, and offering to would teach the buttons to be ignored.
      await pumpFeed(tester, const FeedState(
        connected: true,
        needsYou: NeedsYou(total: 1, items: [
          NeedsYouItem(id: '1', kind: 'overdue', title: 'Партия 214',
            detail: '', route: ''),
        ]),
      ), GlobalKey());
      expect(find.text('Партия 214'), findsOneWidget);
      expect(find.text('Подтвердить'), findsNothing);
    });

    testWidgets('a confirmation row without a token is not answerable', (tester) async {
      // Defensive: a server that stopped sending the token would otherwise
      // render two buttons that answer nothing.
      await pumpFeed(tester, const FeedState(
        connected: true,
        needsYou: NeedsYou(total: 1, items: [
          NeedsYouItem(id: 'cnf_2', kind: 'confirmation', title: 'Что-то',
            detail: '', route: '', confirmationToken: ''),
        ]),
      ), GlobalKey());
      expect(find.text('Что-то'), findsOneWidget);
      expect(find.text('Подтвердить'), findsNothing);
    });

    testWidgets('an empty queue says so instead of showing a bare header', (tester) async {
      await pumpFeed(tester, const FeedState(connected: true), GlobalKey());
      // No section header over nothing, and a sentence that reads as an answer.
      expect(find.text('ТРЕБУЕТ ВАС'), findsNothing);
      expect(find.text('ПОКА ВАС НЕ БЫЛО'), findsNothing);
      expect(find.text('Ничего не ждёт'), findsOneWidget);
    });

    testWidgets('a failed request is named, never shown as emptiness', (tester) async {
      // The whole point: a broken queue and a quiet morning must not look the
      // same. This is the assertion that stops "nothing needs you" being a lie.
      await pumpFeed(tester, const FeedState(
        connected: true, queueError: 'Сервер не ответил',
      ), GlobalKey());
      expect(find.text('Очередь недоступна'), findsOneWidget);
      expect(find.text('Сервер не ответил'), findsOneWidget);
      expect(find.text('Ничего не ждёт'), findsNothing);
    });
  });
}
