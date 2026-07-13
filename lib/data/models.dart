import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum ChatRole { user, assistant }

enum ActionType {
  createTask,
  draftMessage,
  reminder,
  focusTime,
  saveMemory,
  unknown,
}

enum ActionStatus { pending, approved, dismissed }

/// Structured action proposed by the assistant (rendered as action cards,
/// executed only after user approval — screen 16 of the design).
class MilaAction {
  MilaAction({
    String? id,
    required this.type,
    required this.title,
    this.subtitle = '',
    Map<String, dynamic>? payload,
    this.status = ActionStatus.pending,
  }) : id = id ?? _uuid.v4(),
       payload = payload ?? {};

  final String id;
  final ActionType type;
  final String title;
  final String subtitle;
  final Map<String, dynamic> payload;
  ActionStatus status;

  static ActionType typeFrom(String raw) => switch (raw) {
    'create_task' => ActionType.createTask,
    'draft_message' || 'draft_email' => ActionType.draftMessage,
    'reminder' || 'set_reminder' => ActionType.reminder,
    'focus_time' || 'schedule_focus' => ActionType.focusTime,
    'save_memory' || 'remember' => ActionType.saveMemory,
    _ => ActionType.unknown,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'subtitle': subtitle,
    'payload': payload,
    'status': status.name,
  };

  factory MilaAction.fromJson(Map<String, dynamic> json) => MilaAction(
    id: json['id'] as String?,
    type: ActionType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => ActionType.unknown,
    ),
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
    payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
    status: ActionStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => ActionStatus.pending,
    ),
  );
}

class ChatMessage {
  ChatMessage({
    String? id,
    required this.role,
    required this.text,
    DateTime? createdAt,
    List<MilaAction>? actions,
    this.viaVoice = false,
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now(),
       actions = actions ?? [];

  final String id;
  final ChatRole role;
  String text;
  final DateTime createdAt;
  final List<MilaAction> actions;
  final bool viaVoice;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'actions': actions.map((a) => a.toJson()).toList(),
    'viaVoice': viaVoice,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String?,
    role: json['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
    text: json['text'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    actions: ((json['actions'] as List?) ?? [])
        .map((a) => MilaAction.fromJson((a as Map).cast<String, dynamic>()))
        .toList(),
    viaVoice: json['viaVoice'] as bool? ?? false,
  );
}

class TaskItem {
  TaskItem({
    String? id,
    required this.title,
    this.subtitle = '',
    this.enabled = true,
    this.isAutomation = false,
    this.done = false,
    DateTime? createdAt,
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  String subtitle;
  bool enabled;
  bool isAutomation;
  bool done;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'enabled': enabled,
    'isAutomation': isAutomation,
    'done': done,
    'createdAt': createdAt.toIso8601String(),
  };

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
    id: json['id'] as String?,
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    isAutomation: json['isAutomation'] as bool? ?? false,
    done: json['done'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );
}

enum MemoryCategory { people, preferences, facts }

class MemoryItem {
  MemoryItem({
    String? id,
    required this.text,
    this.category = MemoryCategory.facts,
    DateTime? createdAt,
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  String text;
  MemoryCategory category;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'category': category.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory MemoryItem.fromJson(Map<String, dynamic> json) => MemoryItem(
    id: json['id'] as String?,
    text: json['text'] as String? ?? '',
    category: MemoryCategory.values.firstWhere(
      (c) => c.name == json['category'],
      orElse: () => MemoryCategory.facts,
    ),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );
}

class UserProfile {
  const UserProfile({this.name = '', this.email = '', this.signedIn = false});

  final String name;
  final String email;
  final bool signedIn;

  UserProfile copyWith({String? name, String? email, bool? signedIn}) =>
      UserProfile(
        name: name ?? this.name,
        email: email ?? this.email,
        signedIn: signedIn ?? this.signedIn,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'signedIn': signedIn,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    signedIn: json['signedIn'] as bool? ?? false,
  );
}

enum LlmProviderKind { openaiAccount, openai, gemini, claude }

enum AssistantVoiceGender { female, male }

const femaleVoiceName = 'Aoede';
const maleVoiceName = 'Puck';

AssistantVoiceGender assistantVoiceGenderFromName(String voiceName) {
  const knownMaleVoices = {'Puck', 'Charon', 'Fenrir', 'Orus'};
  return knownMaleVoices.contains(voiceName)
      ? AssistantVoiceGender.male
      : AssistantVoiceGender.female;
}

String voiceNameForGender(AssistantVoiceGender gender) =>
    gender == AssistantVoiceGender.female ? femaleVoiceName : maleVoiceName;

String voiceGenderLabel(AssistantVoiceGender gender) =>
    gender == AssistantVoiceGender.female ? 'Female' : 'Male';

/// App settings persisted locally. API keys live in secure storage, not here.
class AppSettings {
  const AppSettings({
    this.onboarded = false,
    this.permissionsDone = false,
    this.provider = LlmProviderKind.gemini,
    this.openAiModel = 'gpt-5.5',
    this.geminiModel = 'gemini-3.5-flash',
    this.anthropicModel = 'claude-sonnet-5',
    this.geminiLiveModel = 'gemini-3.1-flash-live-preview',
    this.voiceName = femaleVoiceName,
    this.personality =
        'An elegant, warm and slightly playful assistant: intelligent, attentive and professional. Pleasant, natural tone, always respectful, useful and business-focused; never overly emotional or childish.',
    this.language = 'Русский',
    this.conciseSummaries = true,
    this.autoMemory = true,
    this.assistantSetupDone = false,
    this.orbSkin = 'nebula',
  });

  final bool onboarded;
  final bool permissionsDone;
  final LlmProviderKind provider;
  final String openAiModel;
  final String geminiModel;
  final String anthropicModel;
  final String geminiLiveModel;
  final String voiceName;
  final String personality;
  final String language;
  final bool conciseSummaries;
  final bool autoMemory;
  final bool assistantSetupDone;
  final String orbSkin;

  AppSettings copyWith({
    bool? onboarded,
    bool? permissionsDone,
    LlmProviderKind? provider,
    String? openAiModel,
    String? geminiModel,
    String? anthropicModel,
    String? geminiLiveModel,
    String? voiceName,
    String? personality,
    String? language,
    bool? conciseSummaries,
    bool? autoMemory,
    bool? assistantSetupDone,
    String? orbSkin,
  }) => AppSettings(
    onboarded: onboarded ?? this.onboarded,
    permissionsDone: permissionsDone ?? this.permissionsDone,
    provider: provider ?? this.provider,
    openAiModel: openAiModel ?? this.openAiModel,
    geminiModel: geminiModel ?? this.geminiModel,
    anthropicModel: anthropicModel ?? this.anthropicModel,
    geminiLiveModel: geminiLiveModel ?? this.geminiLiveModel,
    voiceName: voiceName ?? this.voiceName,
    personality: personality ?? this.personality,
    language: language ?? this.language,
    conciseSummaries: conciseSummaries ?? this.conciseSummaries,
    autoMemory: autoMemory ?? this.autoMemory,
    assistantSetupDone: assistantSetupDone ?? this.assistantSetupDone,
    orbSkin: orbSkin ?? this.orbSkin,
  );

  Map<String, dynamic> toJson() => {
    'v': 9,
    'onboarded': onboarded,
    'permissionsDone': permissionsDone,
    'provider': provider.name,
    'openAiModel': openAiModel,
    'geminiModel': geminiModel,
    'anthropicModel': anthropicModel,
    'geminiLiveModel': geminiLiveModel,
    'voiceName': voiceName,
    'personality': personality,
    'language': language,
    'conciseSummaries': conciseSummaries,
    'autoMemory': autoMemory,
    'assistantSetupDone': assistantSetupDone,
    'orbSkin': orbSkin,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    // Older settings carry retired default models: upgrade defaults but
    // keep any custom value the user typed in.
    final version = json['v'] as int? ?? 1;
    var openAiModel = json['openAiModel'] as String? ?? 'gpt-5.5';
    if (version < 2 && openAiModel == 'gpt-4o-mini') {
      openAiModel = 'gpt-5.5';
    }
    var liveModel =
        json['geminiLiveModel'] as String? ?? 'gemini-3.1-flash-live-preview';
    if (version < 4 &&
        (liveModel == 'gemini-2.0-flash-live-001' ||
            liveModel == 'gemini-live-2.5-flash-native-audio')) {
      liveModel = 'gemini-3.1-flash-live-preview';
    }
    var language = json['language'] as String? ?? 'Русский';
    if (version < 5 && language == 'English') {
      language = 'Русский'; // old default; primary language is Russian now
    }
    const oldFemalePersonality =
        'A young female assistant with an elegant, warm and slightly playful style — intelligent, attentive and professional. Light, pleasant tone, but always respectful, useful and business-focused; never overly emotional or childish.';
    const newPersonality =
        'An elegant, warm and slightly playful assistant: intelligent, attentive and professional. Pleasant, natural tone, always respectful, useful and business-focused; never overly emotional or childish.';
    var personality = json['personality'] as String? ?? newPersonality;
    if (version < 6 &&
        personality ==
            'Warm, concise and proactive. Keep answers short and useful.') {
      personality = newPersonality;
    }
    if (version < 9 && personality == oldFemalePersonality) {
      personality = newPersonality;
    }
    var geminiModel = json['geminiModel'] as String? ?? 'gemini-3.5-flash';
    if (version < 8 && geminiModel == 'gemini-2.5-flash') {
      geminiModel = 'gemini-3.5-flash';
    }
    final rawProvider = LlmProviderKind.values.firstWhere(
      (k) => k.name == json['provider'],
      orElse: () => LlmProviderKind.gemini,
    );
    final provider = switch (rawProvider) {
      LlmProviderKind.openaiAccount ||
      LlmProviderKind.openai => LlmProviderKind.gemini,
      _ => rawProvider,
    };
    return AppSettings(
      onboarded: json['onboarded'] as bool? ?? false,
      permissionsDone: json['permissionsDone'] as bool? ?? false,
      provider: provider,
      openAiModel: openAiModel,
      geminiModel: geminiModel,
      anthropicModel: json['anthropicModel'] as String? ?? 'claude-sonnet-5',
      geminiLiveModel: liveModel,
      voiceName: json['voiceName'] as String? ?? femaleVoiceName,
      personality: personality,
      language: language,
      conciseSummaries: json['conciseSummaries'] as bool? ?? true,
      autoMemory: json['autoMemory'] as bool? ?? true,
      // Existing installs skip the new setup step; they can adjust
      // everything in Settings.
      assistantSetupDone:
          json['assistantSetupDone'] as bool? ??
          (json['permissionsDone'] as bool? ?? false),
      orbSkin: json['orbSkin'] as String? ?? 'nebula',
    );
  }
}
