import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../services/agentic/agentic_os_service.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen>
    with WidgetsBindingObserver {
  GoogleCalendarStatus? _status;
  GoogleCalendarFeed? _feed;
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  AgenticOsService get _service => ref.read(agenticOsServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      final status = await _service.googleCalendarStatus();
      final feed = status.connected
          ? await _service.googleCalendarEvents()
          : const GoogleCalendarFeed();
      if (!mounted) return;
      setState(() {
        _status = status;
        _feed = feed;
        _error = '';
        _loading = false;
      });
      ref.invalidate(googleCalendarStatusProvider);
    } on AgenticOsException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final locale = Localizations.localeOf(context).languageCode;
      final uri = await _service.beginGoogleCalendarConnect(locale: locale);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw const AgenticOsException('Could not open Google authorization.');
      }
    } on AgenticOsException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          l10n.pick(
            ru: 'Отключить календарь?',
            en: 'Disconnect calendar?',
            uz: 'Kalendar uzilsinmi?',
          ),
        ),
        content: Text(
          l10n.pick(
            ru: 'События исчезнут из MILA, но останутся в Google Calendar.',
            en: 'Events will disappear from MILA but remain in Google Calendar.',
            uz: 'Tadbirlar MILAʼdan yo‘qoladi, ammo Google Calendarʼda qoladi.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              l10n.pick(ru: 'Отмена', en: 'Cancel', uz: 'Bekor qilish'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              l10n.pick(ru: 'Отключить', en: 'Disconnect', uz: 'Uzish'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _service.disconnectGoogleCalendar();
      await _refresh();
    } on AgenticOsException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connected = _status?.connected == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pick(ru: 'Календарь', en: 'Calendar', uz: 'Kalendar')),
        actions: [
          IconButton(
            tooltip: l10n.pick(ru: 'Обновить', en: 'Refresh', uz: 'Yangilash'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: MilaBackground(
        glowTop: false,
        child: _loading && _status == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    _connectionPanel(context, connected),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _errorPanel(context),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.pick(
                              ru: 'Ближайшие события',
                              en: 'Upcoming events',
                              uz: 'Yaqin tadbirlar',
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (_feed?.syncedAt != null)
                          Text(
                            DateFormat.Hm().format(_feed!.syncedAt!.toLocal()),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!connected)
                      _emptyPanel(
                        context,
                        icon: Icons.calendar_month_outlined,
                        title: l10n.pick(
                          ru: 'Календарь не подключён',
                          en: 'Calendar is not connected',
                          uz: 'Kalendar ulanmagan',
                        ),
                        text: l10n.pick(
                          ru: 'Подключите Google один раз. События будут доступны на вебе и телефоне в одном аккаунте.',
                          en: 'Connect Google once. Events will be available on web and phone in the same account.',
                          uz: 'Googleʼni bir marta ulang. Tadbirlar bir akkaunt orqali web va telefonda ishlaydi.',
                        ),
                      )
                    else if (_feed?.events.isEmpty ?? true)
                      _emptyPanel(
                        context,
                        icon: Icons.event_available_outlined,
                        title: l10n.pick(
                          ru: 'Событий пока нет',
                          en: 'No events yet',
                          uz: 'Hozircha tadbirlar yo‘q',
                        ),
                        text: l10n.pick(
                          ru: 'В ближайшие 30 дней календарь свободен.',
                          en: 'Your calendar is clear for the next 30 days.',
                          uz: 'Keyingi 30 kun uchun kalendar bo‘sh.',
                        ),
                      )
                    else
                      for (final event in _feed!.events) ...[
                        _eventTile(context, event),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _connectionPanel(BuildContext context, bool connected) {
    final l10n = context.l10n;
    final configured = _status?.configured == true;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TileIcon(
                icon: Icons.calendar_month_outlined,
                color: connected ? MilaColors.success : const Color(0xFF4285F4),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Google Calendar'),
                    const SizedBox(height: 3),
                    Text(
                      connected
                          ? l10n.pick(
                              ru: 'Синхронизирован с Agentic OS',
                              en: 'Synchronized with Agentic OS',
                              uz: 'Agentic OS bilan sinxronlangan',
                            )
                          : configured
                          ? l10n.pick(
                              ru: 'Готов к подключению',
                              en: 'Ready to connect',
                              uz: 'Ulanishga tayyor',
                            )
                          : l10n.pick(
                              ru: 'Не настроен на сервере',
                              en: 'Not configured on the server',
                              uz: 'Serverda sozlanmagan',
                            ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                connected
                    ? Icons.check_circle_rounded
                    : Icons.cloud_off_outlined,
                color: connected ? MilaColors.success : MilaColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (connected)
            GhostButton(
              label: l10n.pick(ru: 'Отключить', en: 'Disconnect', uz: 'Uzish'),
              icon: Icons.link_off_rounded,
              danger: true,
              onPressed: _busy ? null : _disconnect,
            )
          else
            GradientButton(
              label: l10n.pick(
                ru: 'Подключить Google',
                en: 'Connect Google',
                uz: 'Googleʼni ulash',
              ),
              icon: Icons.open_in_browser_rounded,
              busy: _busy,
              onPressed: configured ? _connect : null,
            ),
        ],
      ),
    );
  }

  Widget _errorPanel(BuildContext context) {
    return GlassCard(
      borderColor: MilaColors.danger.withValues(alpha: 0.45),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: MilaColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_error, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _emptyPanel(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 44, color: MilaColors.textTertiary),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _eventTile(BuildContext context, GoogleCalendarEvent event) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final localStart = event.start?.toLocal();
    final date = localStart == null
        ? ''
        : event.allDay
        ? DateFormat.yMMMd(locale).format(localStart)
        : DateFormat.MMMd(locale).add_Hm().format(localStart);
    return GlassCard(
      onTap: event.htmlLink.isEmpty
          ? null
          : () => launchUrl(
              Uri.parse(event.htmlLink),
              mode: LaunchMode.externalApplication,
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TileIcon(
            icon: event.allDay
                ? Icons.event_available_outlined
                : Icons.schedule_rounded,
            color: MilaColors.cyan,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 5),
                Text(date, style: Theme.of(context).textTheme.bodySmall),
                if (event.location.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: MilaColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (event.htmlLink.isNotEmpty)
            const Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: MilaColors.textTertiary,
            ),
        ],
      ),
    );
  }
}
