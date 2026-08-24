import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/voice_orb.dart';
import '../../services/agentic/feed_controller.dart';
import '../../services/agentic/feed_models.dart';
import '../../services/connectivity/connectivity_provider.dart';
import '../../services/storage/stores.dart';

/// The feed: what is waiting on you, and what MILA did while you were not
/// looking.
///
/// What this replaced answered neither question. Forty percent of the screen
/// was an orb under the caption "tap the orb or speak" — an instruction where
/// content belongs — and beneath it three numbers, two of which were zero:
/// 100% ready, 0 open, 0 blocked. A status readout tells you whether the system
/// is well. The person holding the phone wants to know whether anything is
/// waiting for them, and what happened in the two hours they spent in the
/// workshop. Those are different questions and neither was being asked.
///
/// The orb moved to the composer in the shell, where it is one thumb-reach away
/// from every tab instead of from one.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider).value ?? true;
    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          bottom: false,
          child: online ? const _FeedBody() : const _OfflineBody(),
        ),
      ),
    );
  }
}

class _FeedBody extends ConsumerWidget {
  const _FeedBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profile = ref.watch(profileProvider);
    final feed = ref.watch(feedProvider);
    final greeting = l10n.greeting(DateTime.now().hour);

    return RefreshIndicator(
      // Pull to refresh, because a feed that only updates on its own timer
      // makes people close and reopen the app to check.
      color: MilaColors.violet,
      backgroundColor: MilaColors.surface,
      onRefresh: () => ref.read(feedProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
        children: [
          _Header(greeting: greeting, name: profile.name),
          const SizedBox(height: 18),

          if (feed.queueError.isNotEmpty)
            _Trouble(
              message: l10n.pick(
                ru: 'Очередь недоступна',
                en: 'The queue is unavailable',
                uz: 'Navbat mavjud emas',
              ),
              detail: feed.queueError,
            ),

          // Needs you comes first and vanishes entirely when empty. A section
          // header over "0" is a way of insisting on being read.
          if (feed.needsYou.items.isNotEmpty) ...[
            _SectionLabel(
              text: l10n.pick(ru: 'Требует вас', en: 'Needs you', uz: 'Sizni kutadi'),
              count: feed.needsYou.total,
              accent: MilaColors.warning,
            ),
            const SizedBox(height: 8),
            _Grouped(
              children: [
                for (final item in feed.needsYou.items.take(6))
                  _NeedsYouRow(item: item),
              ],
            ),
            const SizedBox(height: 20),
          ],

          if (feed.activityError.isNotEmpty)
            _Trouble(
              message: l10n.pick(
                ru: 'История недоступна',
                en: 'The history is unavailable',
                uz: 'Tarix mavjud emas',
              ),
              detail: feed.activityError,
            ),

          if (feed.activity.isNotEmpty) ...[
            _SectionLabel(
              text: l10n.pick(
                ru: 'Пока вас не было',
                en: 'While you were away',
                uz: 'Siz yo‘qligingizda',
              ),
            ),
            const SizedBox(height: 8),
            _Grouped(
              children: [
                for (final entry in feed.activity.take(12))
                  _ActivityRow(entry: entry),
              ],
            ),
          ],

          if (feed.isRestingQuiet) const _AllClear(),
          if (feed.loading && !feed.hasAnything) const _Waiting(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.greeting, required this.name});

  final String greeting;
  final String name;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$greeting, $name', style: text.headlineSmall),
              const SizedBox(height: 2),
              Text(
                context.l10n.pick(
                  ru: 'Вот что накопилось',
                  en: 'Here is what has piled up',
                  uz: 'Mana nima to‘plandi',
                ),
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, this.count, this.accent});

  final String text;
  final int? count;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: MilaColors.textTertiary,
          ),
        ),
        if (count != null && count! > 0) ...[
          const Spacer(),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent ?? MilaColors.violet,
            ),
          ),
        ],
      ],
    );
  }
}

/// One rounded container with hairline dividers, so a run of rows reads as one
/// object rather than a stack of floating cards.
class _Grouped extends StatelessWidget {
  const _Grouped({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MilaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MilaColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: MilaColors.divider),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Severity is carried by a glyph and a colour together. Colour alone fails for
/// the eight percent of men who cannot separate these two hues, and this is a
/// factory floor, not a design portfolio.
({IconData icon, Color colour}) _severityMark(String kind) => switch (kind) {
  'confirmation' => (icon: Icons.pan_tool_outlined, colour: MilaColors.violet),
  'blocked' => (icon: Icons.block_rounded, colour: MilaColors.danger),
  'waiting' => (icon: Icons.help_outline_rounded, colour: MilaColors.warning),
  'overdue' => (icon: Icons.schedule_rounded, colour: MilaColors.warning),
  'attention' => (icon: Icons.priority_high_rounded, colour: MilaColors.violet),
  _ => (icon: Icons.circle_outlined, colour: MilaColors.textTertiary),
};

({IconData icon, Color colour}) _kindMark(String kind) => switch (kind) {
  'reminder' => (icon: Icons.alarm_rounded, colour: MilaColors.violet),
  'task' => (icon: Icons.check_circle_outline, colour: MilaColors.success),
  'calendar' => (icon: Icons.event_available_outlined, colour: MilaColors.cyan),
  'message' => (icon: Icons.chat_bubble_outline, colour: MilaColors.cyan),
  'brief' => (icon: Icons.wb_twilight_rounded, colour: MilaColors.warning),
  'lead' => (icon: Icons.trending_up_rounded, colour: MilaColors.success),
  'erp' => (icon: Icons.inventory_2_outlined, colour: MilaColors.warning),
  _ => (icon: Icons.notifications_none_rounded, colour: MilaColors.textTertiary),
};

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.iconColour,
    required this.title,
    required this.detail,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColour;
  final String title;
  final String detail;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        // 56 is the floor for a row someone taps while holding something else.
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: iconColour.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: iconColour),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: MilaColors.textPrimary,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: MilaColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: MilaColors.textTertiary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NeedsYouRow extends ConsumerStatefulWidget {
  const _NeedsYouRow({required this.item});

  final NeedsYouItem item;

  @override
  ConsumerState<_NeedsYouRow> createState() => _NeedsYouRowState();
}

class _NeedsYouRowState extends ConsumerState<_NeedsYouRow> {
  bool _busy = false;

  Future<void> _answer(bool approve) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    try {
      await ref
          .read(feedProvider.notifier)
          .answer(widget.item.confirmationToken, approve: approve);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      // Said out loud. A confirmation that failed quietly is indistinguishable
      // from one that succeeded, and they are opposite outcomes.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MilaColors.dangerFill,
          content: Text(
            l10n.pick(
              ru: 'Не удалось ответить. Действие осталось в очереди.',
              en: 'Could not answer. The action is still waiting.',
              uz: 'Javob berilmadi. Amal navbatda qoldi.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final l10n = context.l10n;
    final mark = _severityMark(item.kind);
    final row = _Row(
      icon: mark.icon,
      iconColour: mark.colour,
      title: item.title,
      detail: item.detail,
      // A route the server chose, opened only if it is one this app has. A
      // confirmation is answered here, so it is not also a link away.
      onTap: item.isConfirmation || !item.route.startsWith('/')
          ? null
          : () => context.push(item.route),
    );
    if (!item.isConfirmation) return row;

    // Two buttons, and the destructive one is not the easy one. Both are
    // spelled out: "Yes" and "No" beside a sentence is how people approve
    // things they did not read.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
          child: Row(
            children: [
              Expanded(
                child: _GateButton(
                  label: l10n.pick(ru: 'Отклонить', en: 'Decline', uz: 'Rad etish'),
                  primary: false,
                  busy: _busy,
                  onPressed: () => _answer(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GateButton(
                  label: l10n.pick(ru: 'Подтвердить', en: 'Confirm', uz: 'Tasdiqlash'),
                  primary: true,
                  busy: _busy,
                  onPressed: () => _answer(true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GateButton extends StatelessWidget {
  const _GateButton({
    required this.label,
    required this.primary,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool primary;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !busy,
      label: label,
      child: Material(
        color: primary ? MilaColors.violetFill : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: busy ? null : onPressed,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: primary ? MilaColors.violetFill : MilaColors.cardBorder,
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MilaColors.textSecondary,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: primary ? Colors.white : MilaColors.textSecondary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final mark = _kindMark(entry.kind);
    return _Row(
      icon: mark.icon,
      iconColour: mark.colour,
      title: entry.title,
      detail: entry.detail,
      trailing: _shortWhen(context, entry.when),
      onTap: entry.route.startsWith('/') ? () => context.push(entry.route) : null,
    );
  }
}

/// "09:14" for today, a weekday for this week, a date beyond that. A relative
/// string ("2 h ago") would need rebuilding every minute to stay true.
String? _shortWhen(BuildContext context, DateTime? when) {
  if (when == null) return null;
  final now = DateTime.now();
  final sameDay = when.year == now.year && when.month == now.month && when.day == now.day;
  if (sameDay) {
    return '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
  }
  final days = now.difference(when).inDays;
  if (days == 1 || (days < 1 && !sameDay)) {
    return context.l10n.pick(ru: 'вчера', en: 'yesterday', uz: 'kecha');
  }
  return '${when.day.toString().padLeft(2, '0')}.${when.month.toString().padLeft(2, '0')}';
}

class _Trouble extends StatelessWidget {
  const _Trouble({required this.message, required this.detail});

  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    // Named rather than swallowed: an empty section and a failed request look
    // identical, and only one of them means "nothing is waiting".
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: MilaColors.warning.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MilaColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 17, color: MilaColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: MilaColors.textPrimary,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: const TextStyle(fontSize: 12, color: MilaColors.textTertiary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          const AdaptiveOrb(size: 92),
          const SizedBox(height: 20),
          Text(
            l10n.pick(
              ru: 'Ничего не ждёт',
              en: 'Nothing is waiting',
              uz: 'Hech narsa kutmaydi',
            ),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: MilaColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              // An empty feed is an answer, not a failure. It says so, and
              // points at the one thing worth doing from here.
              l10n.pick(
                ru: 'Ни блоков, ни решений за вами. Спросите MILA, если нужно что-то начать.',
                en: 'Nothing blocked, nothing awaiting your decision. Ask MILA if you want to start something.',
                uz: 'Bloklar ham, qarorlar ham yo‘q. Biror ish boshlash uchun MILA’dan so‘rang.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: MilaColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 60),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: MilaColors.violet),
        ),
      ),
    );
  }
}

/// Offline state (screen 17 of the design).
class _OfflineBody extends ConsumerWidget {
  const _OfflineBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: MilaColors.cardBorder, width: 1.5),
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              size: 36,
              color: MilaColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.pick(
              ru: 'Нет подключения к интернету',
              en: 'No Internet Connection',
              uz: 'Internet aloqasi yo\'q',
            ),
            style: text.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.pick(
              ru: 'MILA сейчас офлайн. Часть функций станет доступна после подключения.',
              en: 'MILA is offline right now. Some features are unavailable until you\'re back online.',
              uz: 'MILA hozir oflayn. Baʼzi funksiyalar internet qaytganda ishlaydi.',
            ),
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
          const SizedBox(height: 28),
          GradientButton(
            label: l10n.pick(
              ru: 'Повторить',
              en: 'Try Again',
              uz: 'Qayta urinish',
            ),
            expanded: false,
            onPressed: () => ref.invalidate(onlineProvider),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () => context.go('/tasks'),
            child: Text(
              l10n.pick(
                ru: 'Работать офлайн',
                en: 'Work Offline',
                uz: 'Oflayn ishlash',
              ),
              style: text.labelLarge?.copyWith(color: MilaColors.cyan),
            ),
          ),
          const Spacer(),
          const AdaptiveOrb(size: 120, mood: OrbMood.offline),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}
