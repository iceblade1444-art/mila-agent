import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../services/agentic/agentic_os_service.dart';
import '../../services/agentic/day_plan_models.dart';

/// The personal day: the same live plan the web Personal tab shows and MILA
/// reads out — calendar, focus blocks and alerts merged server-side — plus the
/// pending reminders with a way to cancel one.
class DayPlanScreen extends ConsumerStatefulWidget {
  const DayPlanScreen({super.key});

  @override
  ConsumerState<DayPlanScreen> createState() => _DayPlanScreenState();
}

class _DayPlanScreenState extends ConsumerState<DayPlanScreen> {
  DayPlan? _plan;
  List<PersonalReminder> _reminders = const [];
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(agenticOsServiceProvider);
    // The two halves fail independently: a slow ERP must not take the
    // reminders down with it, nor the other way round.
    final results = await Future.wait<Object?>([
      service.dayPlan().then<Object?>((plan) => plan).catchError((e) => e),
      service
          .pendingReminders()
          .then<Object?>((items) => items)
          .catchError((e) => e),
    ]);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      final plan = results[0];
      final reminders = results[1];
      if (plan is DayPlan) {
        _plan = plan;
        _error = null;
      } else if (_plan == null) {
        _error = plan.toString();
      }
      if (reminders is List<PersonalReminder>) _reminders = reminders;
    });
  }

  Future<void> _cancelReminder(PersonalReminder reminder) async {
    try {
      await ref.read(agenticOsServiceProvider).cancelReminder(reminder.id);
      setState(
        () => _reminders = _reminders
            .where((item) => item.id != reminder.id)
            .toList(growable: false),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _clock(String iso) {
    final time = DateTime.tryParse(iso)?.toLocal();
    if (time == null) return '';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pick(ru: 'Мой день', en: 'My day', uz: 'Kunim')),
        backgroundColor: Colors.transparent,
      ),
      body: MilaBackground(child: SafeArea(child: _body(l10n))),
    );
  }

  Widget _body(MilaLocalizations l10n) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final plan = _plan;
    if (plan == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ??
                l10n.pick(
                  ru: 'План дня недоступен',
                  en: 'Day plan unavailable',
                  uz: 'Kun rejasi mavjud emas',
                ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: MilaColors.textTertiary),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
        children: [
          if (plan.summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                plan.summary,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          for (final alert in plan.alerts) _alertCard(alert),
          if (plan.alerts.isNotEmpty) const SizedBox(height: 10),
          _section(l10n.pick(ru: 'Расписание', en: 'Agenda', uz: 'Jadval')),
          if (plan.agenda.isEmpty)
            _muted(
              plan.calendarConnected
                  ? l10n.pick(
                      ru: 'На сегодня ничего не запланировано.',
                      en: 'Nothing scheduled for today.',
                      uz: 'Bugunga hech narsa rejalanmagan.',
                    )
                  : l10n.pick(
                      ru: 'Календарь не подключён — расписание пустое. Подключить можно в веб-версии.',
                      en: 'Calendar is not connected, so the agenda is empty. Connect it from the web dashboard.',
                      uz: 'Kalendar ulanmagan — jadval bo‘sh. Uni veb-versiyadan ulash mumkin.',
                    ),
            ),
          for (final item in plan.agenda) _agendaTile(l10n, item),
          const SizedBox(height: 18),
          _section(
            l10n.pick(ru: 'Напоминания', en: 'Reminders', uz: 'Eslatmalar'),
          ),
          if (_reminders.isEmpty)
            _muted(
              l10n.pick(
                ru: 'Напоминаний нет. Скажите MILA «напомни мне…» — придёт уведомление.',
                en: 'No reminders. Tell MILA "remind me…" and a notification will come.',
                uz: 'Eslatma yo‘q. MILA ga «menga eslat…» deng — bildirishnoma keladi.',
              ),
            ),
          for (final reminder in _reminders) _reminderTile(l10n, reminder),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: MilaColors.textTertiary,
        letterSpacing: 0.6,
      ),
    ),
  );

  Widget _muted(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(color: MilaColors.textTertiary)),
  );

  Widget _alertCard(DayAlert alert) {
    final urgent = alert.level == 'urgent';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (urgent ? MilaColors.pink : MilaColors.cyan).withValues(
          alpha: 0.1,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (urgent ? MilaColors.pink : MilaColors.cyan).withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            urgent ? Icons.priority_high_rounded : Icons.info_outline_rounded,
            size: 18,
            color: urgent ? MilaColors.pink : MilaColors.cyan,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(alert.title)),
        ],
      ),
    );
  }

  Widget _agendaTile(MilaLocalizations l10n, AgendaItem item) {
    final focus = item.kind == 'focus';
    final time = item.allDay
        ? l10n.pick(ru: 'Весь день', en: 'All day', uz: 'Kun bo‘yi')
        : '${_clock(item.start)}–${_clock(item.end)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2232),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 12,
                color: MilaColors.textTertiary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Icon(
            focus ? Icons.center_focus_strong_rounded : Icons.event_rounded,
            size: 17,
            color: focus ? MilaColors.violet : MilaColors.cyan,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (item.detail.isNotEmpty)
                  Text(
                    item.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MilaColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reminderTile(MilaLocalizations l10n, PersonalReminder reminder) {
    final due = DateTime.tryParse(reminder.dueAt)?.toLocal();
    final label = due == null
        ? ''
        : '${due.day.toString().padLeft(2, '0')}.${due.month.toString().padLeft(2, '0')} ${_clock(reminder.dueAt)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2, right: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2232),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.alarm_rounded, size: 17, color: MilaColors.violet),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reminder.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: MilaColors.textTertiary,
            ),
          ),
          IconButton(
            onPressed: () => _cancelReminder(reminder),
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: l10n.pick(
              ru: 'Отменить напоминание',
              en: 'Cancel reminder',
              uz: 'Eslatmani bekor qilish',
            ),
          ),
        ],
      ),
    );
  }
}
