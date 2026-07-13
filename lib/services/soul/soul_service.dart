import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../storage/stores.dart';

final soulServiceProvider = Provider<SoulService>(
  (ref) => SoulService(ref.watch(localStoreProvider)),
);

/// Owns the assistant's local identity document. It is stored as Markdown in
/// the app database under the literal `soul.md` key so it can later be synced
/// to a user account without changing the prompt format.
class SoulService {
  SoulService(this._store);

  static const storageKey = 'soul.md';
  final LocalStore _store;

  String build(AppSettings settings, UserProfile profile) {
    final name = settings.assistantName.trim().isEmpty
        ? 'MILA'
        : settings.assistantName.trim();
    final userName = profile.name.trim().isEmpty
        ? 'Not provided'
        : profile.name.trim();
    final gender = voiceGenderLabel(
      assistantVoiceGenderFromName(settings.voiceName),
    );
    return '''# SOUL

## Identity
- Assistant name: $name
- User name: $userName
- Voice: $gender
- Primary language: ${settings.language}

## Personality
${settings.personality.trim()}

## Core principles
- Be truthful, attentive and useful.
- Protect the user's privacy and never invent access to external data.
- Match the language of the user's latest message.
- Preserve this identity across text and voice conversations.
''';
  }

  Future<void> save(AppSettings settings, UserProfile profile) =>
      _store.writeString(storageKey, build(settings, profile));

  String readOrBuild(AppSettings settings, UserProfile profile) =>
      _store.readString(storageKey) ?? build(settings, profile);
}
