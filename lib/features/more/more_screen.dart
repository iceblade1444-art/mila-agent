import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/mila_localizations.dart';
import '../../core/theme/mila_theme.dart';

/// Everything the four tabs do not carry, findable by name.
///
/// Nineteen screens existed and four were reachable; the calendar, the memory
/// vault, the team threads, the integrations and the command centre were all
/// built and then buried. A rail of four is only honest if the rest can be
/// found by typing, so this is the other fifteen with a search field over them
/// — the same bargain the web console makes with its command palette.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreDestination {
  const _MoreDestination({
    required this.icon,
    required this.route,
    required this.ru,
    required this.en,
    required this.uz,
    required this.hintRu,
    required this.hintEn,
    required this.hintUz,
  });

  final IconData icon;
  final String route;
  final String ru, en, uz;
  final String hintRu, hintEn, hintUz;
}

// Grouped the way a person looks for them, not the way the code is laid out.
const _groups = <(String, String, String, List<_MoreDestination>)>[
  (
    'Разговор',
    'Conversation',
    'Suhbat',
    [
      _MoreDestination(
        icon: Icons.forum_outlined, route: '/chat',
        ru: 'Чат с MILA', en: 'Chat with MILA', uz: 'MILA bilan chat',
        hintRu: 'Вся переписка', hintEn: 'The whole thread', hintUz: 'Butun yozishma',
      ),
      _MoreDestination(
        icon: Icons.groups_outlined, route: '/team',
        ru: 'Команда', en: 'Team', uz: 'Jamoa',
        hintRu: 'Обсуждения с людьми', hintEn: 'Threads with people', hintUz: 'Odamlar bilan',
      ),
    ],
  ),
  (
    'Работа',
    'Work',
    'Ish',
    [
      _MoreDestination(
        icon: Icons.calendar_month_outlined, route: '/calendar',
        ru: 'Календарь', en: 'Calendar', uz: 'Kalendar',
        hintRu: 'Встречи и события', hintEn: 'Meetings and events', hintUz: 'Uchrashuvlar',
      ),
      _MoreDestination(
        icon: Icons.dashboard_customize_outlined, route: '/command',
        ru: 'Центр команд', en: 'Command centre', uz: 'Buyruqlar markazi',
        hintRu: 'Быстрые действия', hintEn: 'Quick actions', hintUz: 'Tezkor amallar',
      ),
    ],
  ),
  (
    'MILA',
    'MILA',
    'MILA',
    [
      _MoreDestination(
        icon: Icons.mic_none_outlined, route: '/voice',
        ru: 'Голосовой звонок', en: 'Voice call', uz: 'Ovozli qo‘ng‘iroq',
        hintRu: 'Живой разговор', hintEn: 'Live conversation', hintUz: 'Jonli suhbat',
      ),
      _MoreDestination(
        icon: Icons.psychology_outlined, route: '/memory',
        ru: 'Память', en: 'Memory', uz: 'Xotira',
        hintRu: 'Что MILA о вас знает', hintEn: 'What MILA knows about you',
        hintUz: 'MILA siz haqingizda',
      ),
    ],
  ),
  (
    'Настройка',
    'Setup',
    'Sozlash',
    [
      _MoreDestination(
        icon: Icons.link_outlined, route: '/integrations',
        ru: 'Интеграции', en: 'Integrations', uz: 'Integratsiyalar',
        hintRu: 'Telegram, календарь, склад', hintEn: 'Telegram, calendar, stock',
        hintUz: 'Telegram, kalendar, ombor',
      ),
      _MoreDestination(
        icon: Icons.settings_outlined, route: '/settings',
        ru: 'Настройки', en: 'Settings', uz: 'Sozlamalar',
        hintRu: 'Язык, версия, аккаунт', hintEn: 'Language, version, account',
        hintUz: 'Til, versiya, hisob',
      ),
    ],
  ),
];

class _MoreScreenState extends State<MoreScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _query.trim().toLowerCase();

    String label(_MoreDestination d) => l10n.pick(ru: d.ru, en: d.en, uz: d.uz);
    String hint(_MoreDestination d) =>
        l10n.pick(ru: d.hintRu, en: d.hintEn, uz: d.hintUz);

    // Matched on the label and the hint in the current language, so searching
    // "склад" finds Integrations even though the word is not in its name.
    bool matches(_MoreDestination d) =>
        query.isEmpty ||
        label(d).toLowerCase().contains(query) ||
        hint(d).toLowerCase().contains(query);

    final groups = _groups
        .map((g) => (g, g.$4.where(matches).toList()))
        .where((pair) => pair.$2.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: MilaColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: Row(
                children: [
                  Text(
                    l10n.pick(ru: 'Ещё', en: 'More', uz: 'Yana'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: TextField(
                controller: _controller,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 15, color: MilaColors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: MilaColors.surface,
                  hintText: l10n.pick(
                    ru: 'Найти экран или действие',
                    en: 'Find a screen or action',
                    uz: 'Ekran yoki amalni topish',
                  ),
                  hintStyle: const TextStyle(color: MilaColors.textTertiary, fontSize: 15),
                  prefixIcon: const Icon(Icons.search, size: 20, color: MilaColors.textTertiary),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: MilaColors.textTertiary,
                          tooltip: l10n.pick(ru: 'Очистить', en: 'Clear', uz: 'Tozalash'),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: MilaColors.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: MilaColors.cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: MilaColors.violet),
                  ),
                ),
              ),
            ),
            Expanded(
              child: groups.isEmpty
                  ? _NothingFound(query: _query)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final (group, items) = groups[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(top: index == 0 ? 4 : 20, bottom: 8),
                              child: Text(
                                l10n.pick(ru: group.$1, en: group.$2, uz: group.$3)
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                  color: MilaColors.textTertiary,
                                ),
                              ),
                            ),
                            for (final d in items)
                              _MoreRow(
                                icon: d.icon,
                                label: label(d),
                                hint: hint(d),
                                onTap: () => context.push(d.route),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: MilaColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            // 56 rather than the 48 a list row would take: this is the screen
            // people reach for when they are holding something in the other
            // hand.
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MilaColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(icon, size: 21, color: MilaColors.cyan),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: MilaColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        hint,
                        style: const TextStyle(fontSize: 12.5, color: MilaColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: MilaColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NothingFound extends StatelessWidget {
  const _NothingFound({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 34, color: MilaColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              l10n.pick(
                ru: 'Ничего не нашлось',
                en: 'Nothing found',
                uz: 'Hech narsa topilmadi',
              ),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: MilaColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            // Says what was searched for, so a typo is visible without going
            // back to the field.
            Text(
              l10n.pick(
                ru: 'По запросу «$query». Спросите MILA — она найдёт и сделает.',
                en: 'For “$query”. Ask MILA — she can find it and act.',
                uz: '«$query» bo‘yicha. MILA’dan so‘rang — u topadi.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: MilaColors.textTertiary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
