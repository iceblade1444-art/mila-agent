/// State for the home screen: what is waiting on the person, and what MILA did
/// while they were not looking.
///
/// The two lists are fetched together and land together, because the screen is
/// meaningless with one of them: "nothing needs you" is only reassuring next to
/// evidence that something has been happening. A half-loaded feed reads as a
/// broken feed.
///
/// Both calls are allowed to fail independently. A down Hermes bridge empties
/// the queue but must not blank the history, and vice versa — the screen shows
/// what it has and says what it is missing, rather than becoming a spinner.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agentic_os_service.dart';
import 'feed_models.dart';

class FeedState {
  const FeedState({
    this.needsYou = NeedsYou.empty,
    this.activity = const [],
    this.connected = false,
    this.loading = false,
    this.queueError = '',
    this.activityError = '',
  });

  final NeedsYou needsYou;
  final List<ActivityEntry> activity;
  final bool connected;
  final bool loading;

  /// Kept apart so the screen can say which half is missing. One error string
  /// for two requests turns "the queue is unavailable" into "the feed is
  /// broken", which is a different and worse message.
  final String queueError;
  final String activityError;

  bool get hasAnything => needsYou.items.isNotEmpty || activity.isNotEmpty;

  /// True only when the server answered and genuinely had nothing — never
  /// while loading, and never after a failure, or a quiet morning and a broken
  /// connection look identical.
  bool get isRestingQuiet =>
      connected && !loading && !hasAnything && queueError.isEmpty && activityError.isEmpty;

  FeedState copyWith({
    NeedsYou? needsYou,
    List<ActivityEntry>? activity,
    bool? connected,
    bool? loading,
    String? queueError,
    String? activityError,
  }) => FeedState(
    needsYou: needsYou ?? this.needsYou,
    activity: activity ?? this.activity,
    connected: connected ?? this.connected,
    loading: loading ?? this.loading,
    queueError: queueError ?? this.queueError,
    activityError: activityError ?? this.activityError,
  );
}

class FeedController extends StateNotifier<FeedState> {
  /// [initial] and [autoRefresh] exist so a test can render this screen with
  /// content instead of a spinner. Nothing in the app passes them; the override
  /// in a test supplies the same real Ref the provider would.
  FeedController(this._ref, {FeedState? initial, bool autoRefresh = true})
    : super(initial ?? const FeedState()) {
    if (!autoRefresh) return;
    unawaited(refresh());
    // Slower than the dashboard's twenty seconds: this is a catch-up surface,
    // not a monitor, and a feed that reshuffles under a reading thumb is worse
    // than one a minute stale.
    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  final Ref _ref;
  Timer? _timer;

  Future<void> refresh({bool silent = false}) async {
    final service = _ref.read(agenticOsServiceProvider);
    if (!await service.isConnected()) {
      state = const FeedState();
      return;
    }
    if (!silent) {
      state = state.copyWith(
        connected: true,
        loading: true,
        queueError: '',
        activityError: '',
      );
    }

    // Both at once, and neither waits for the other's failure.
    final results = await Future.wait([
      service.needsYou().then<Object>((value) => value).catchError((Object e) => e),
      service.activity().then<Object>((value) => value).catchError((Object e) => e),
    ]);

    final queue = results[0];
    final history = results[1];
    if (!mounted) return;

    state = FeedState(
      needsYou: queue is NeedsYou ? queue : state.needsYou,
      activity: history is List<ActivityEntry> ? history : state.activity,
      connected: true,
      loading: false,
      queueError: queue is NeedsYou ? '' : _message(queue),
      activityError: history is List<ActivityEntry> ? '' : _message(history),
    );
  }

  static String _message(Object error) =>
      error is AgenticOsException ? error.message : 'Не удалось загрузить';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final feedProvider = StateNotifierProvider<FeedController, FeedState>(
  FeedController.new,
);
