import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../core/theme/mila_theme.dart';
import '../../core/widgets/common.dart';
import '../../services/storage/stores.dart';

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  final Map<String, bool> _granted = {
    'mic': false,
    'notifications': false,
    'memory': true,
    'calendar': false,
    'contacts': false,
  };

  Future<void> _request(String key) async {
    // Browsers have no OS permission dialogs: the mic prompt comes from
    // getUserMedia, everything else is granted at time of use.
    if (kIsWeb) {
      bool webResult = !(_granted[key] ?? false);
      if (key == 'mic' && webResult) {
        final recorder = AudioRecorder();
        try {
          webResult = await recorder.hasPermission();
        } catch (_) {
          webResult = false;
        } finally {
          recorder.dispose();
        }
      }
      if (mounted) setState(() => _granted[key] = webResult);
      return;
    }

    final permission = switch (key) {
      'mic' => Permission.microphone,
      'notifications' => Permission.notification,
      'calendar' => Permission.calendarFullAccess,
      'contacts' => Permission.contacts,
      _ => null,
    };
    bool result = _granted[key] ?? false;
    if (permission == null) {
      result = !result; // app-level flag (memory)
    } else if (!result) {
      try {
        final status = await permission.request();
        result = status.isGranted || status.isLimited;
        if (!result && (status.isPermanentlyDenied || status.isRestricted)) {
          await openAppSettings();
        }
      } catch (_) {
        // Platform without this permission (e.g. web preview): flag only.
        result = true;
      }
    } else {
      result = false; // visual off; real revoke happens in OS settings
    }
    if (mounted) setState(() => _granted[key] = result);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const items = [
      (
        'mic',
        Icons.mic_none_rounded,
        MilaColors.cyan,
        'Microphone',
        'Required for voice input'
      ),
      (
        'notifications',
        Icons.notifications_none_rounded,
        MilaColors.violet,
        'Notifications',
        'Send important updates'
      ),
      (
        'memory',
        Icons.bookmark_outline_rounded,
        MilaColors.purple,
        'Memory',
        'Remember facts and preferences'
      ),
      (
        'calendar',
        Icons.calendar_today_outlined,
        MilaColors.cyan,
        'Calendar',
        'Manage events and reminders'
      ),
      (
        'contacts',
        Icons.person_outline_rounded,
        MilaColors.pink,
        'Contacts',
        'Find and connect with people'
      ),
    ];

    return Scaffold(
      body: MilaBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text('MILA needs access to\nwork at its best',
                    textAlign: TextAlign.center,
                    style: text.headlineMedium),
                const SizedBox(height: 10),
                Text(
                  'You\'re in control. You can change these anytime in settings.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
                const SizedBox(height: 28),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      for (final (key, icon, color, title, subtitle) in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            child: Row(
                              children: [
                                TileIcon(icon: icon, color: color),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(title, style: text.titleSmall),
                                      const SizedBox(height: 3),
                                      Text(subtitle, style: text.bodySmall),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _granted[key] ?? false,
                                  onChanged: (_) => _request(key),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                GradientButton(
                  label: 'Continue',
                  onPressed: () {
                    ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(permissionsDone: true));
                    context.go('/home');
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
