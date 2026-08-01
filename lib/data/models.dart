import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum ChatRole { user, assistant }

enum ChatAttachmentType { image, file }

enum ChatDeliveryStatus { sending, sent, delivered, failed }

enum ChatCardType { info, task, reminder, progress, report }

class ChatRichCard {
  ChatRichCard({
    String? id,
    required this.type,
    required this.title,
    this.subtitle = '',
    this.metric = '',
    this.progress,
    List<String>? items,
    this.accent = 'violet',
  }) : id = id ?? _uuid.v4(),
       items = items ?? [];

  final String id;
  final ChatCardType type;
  final String title;
  final String subtitle;
  final String metric;
  final double? progress;
  final List<String> items;
  final String accent;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'subtitle': subtitle,
    'metric': metric,
    if (progress != null) 'progress': progress,
    'items': items,
    'accent': accent,
  };

  factory ChatRichCard.fromJson(Map<String, dynamic> json) => ChatRichCard(
    id: json['id'] as String?,
    type: ChatCardType.values.firstWhere(
      (type) => type.name == json['type'],
      orElse: () => ChatCardType.info,
    ),
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
    metric: json['metric']?.toString() ?? '',
    progress: switch (json['progress']) {
      final num value => value.toDouble().clamp(0.0, 1.0).toDouble(),
      _ => null,
    },
    items: ((json['items'] as List?) ?? [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .take(6)
        .toList(),
    accent: json['accent'] as String? ?? 'violet',
  );
}

class ChatAttachment {
  ChatAttachment({
    String? id,
    required this.name,
    required this.path,
    required this.mimeType,
    required this.type,
  }) : id = id ?? _uuid.v4();

  final String id;
  final String name;
  final String path;
  final String mimeType;
  final ChatAttachmentType type;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'mimeType': mimeType,
    'type': type.name,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
    id: json['id'] as String?,
    name: json['name'] as String? ?? 'Attachment',
    path: json['path'] as String? ?? '',
    mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
    type: ChatAttachmentType.values.firstWhere(
      (type) => type.name == json['type'],
      orElse: () => ChatAttachmentType.file,
    ),
  );
}

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
    List<ChatAttachment>? attachments,
    List<ChatRichCard>? cards,
    List<String>? suggestions,
    this.viaVoice = false,
    this.deliveryStatus = ChatDeliveryStatus.delivered,
    this.replyToText = '',
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now(),
       actions = actions ?? [],
       attachments = attachments ?? [],
       cards = cards ?? [],
       suggestions = suggestions ?? [];

  final String id;
  final ChatRole role;
  String text;
  final DateTime createdAt;
  final List<MilaAction> actions;
  final List<ChatAttachment> attachments;
  final List<ChatRichCard> cards;
  final List<String> suggestions;
  final bool viaVoice;
  final ChatDeliveryStatus deliveryStatus;
  final String replyToText;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'actions': actions.map((a) => a.toJson()).toList(),
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(),
    'cards': cards.map((card) => card.toJson()).toList(),
    'suggestions': suggestions,
    'viaVoice': viaVoice,
    'deliveryStatus': deliveryStatus.name,
    'replyToText': replyToText,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String?,
    role: json['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
    text: json['text'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    actions: ((json['actions'] as List?) ?? [])
        .map((a) => MilaAction.fromJson((a as Map).cast<String, dynamic>()))
        .toList(),
    attachments: ((json['attachments'] as List?) ?? [])
        .map(
          (attachment) => ChatAttachment.fromJson(
            (attachment as Map).cast<String, dynamic>(),
          ),
        )
        .toList(),
    cards: ((json['cards'] as List?) ?? [])
        .map(
          (card) =>
              ChatRichCard.fromJson((card as Map).cast<String, dynamic>()),
        )
        .toList(),
    suggestions: ((json['suggestions'] as List?) ?? [])
        .map((suggestion) => suggestion.toString())
        .toList(),
    viaVoice: json['viaVoice'] as bool? ?? false,
    deliveryStatus: ChatDeliveryStatus.values.firstWhere(
      (status) => status.name == json['deliveryStatus'],
      orElse: () => ChatDeliveryStatus.delivered,
    ),
    replyToText: json['replyToText'] as String? ?? '',
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

/// A task owned by the shared Hermes Kanban board in Agentic OS.
class AgenticTask {
  const AgenticTask({
    required this.id,
    required this.title,
    this.body = '',
    this.status = 'triage',
    this.assignee = 'default',
    this.summary = '',
    this.priority = 0,
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String status;
  final String assignee;
  final String summary;
  final int priority;
  final DateTime? createdAt;

  bool get complete => status == 'done' || status == 'archived';
  bool get active =>
      status == 'ready' || status == 'running' || status == 'doing';

  factory AgenticTask.fromJson(Map<String, dynamic> json) {
    final created = json['created_at'] ?? json['createdAt'];
    final priority = json['priority'];
    return AgenticTask(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled task',
      body: json['body'] as String? ?? json['detail'] as String? ?? '',
      status: json['status'] as String? ?? 'todo',
      assignee: json['assignee'] as String? ?? 'default',
      summary:
          json['latest_summary'] as String? ?? json['result'] as String? ?? '',
      priority: priority is num
          ? priority.toInt()
          : switch (priority) {
              'high' => 2,
              'low' => -1,
              _ => 0,
            },
      createdAt: created is num
          ? DateTime.fromMillisecondsSinceEpoch(created.toInt() * 1000)
          : DateTime.tryParse(created?.toString() ?? ''),
    );
  }
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

enum MilaConversationStyle { assistant, friend, operator, mentor }

enum MilaSpeakingPace { slow, medium, fast }

enum MilaDeliveryStyle { natural, warm, energetic, quiet, precise }

enum MilaListeningProfile { balanced, noisy, deliberate }

enum MilaResponseLength { brief, balanced }

enum MilaVoiceTransport { direct, livekit }

class AssistantPersonality {
  const AssistantPersonality({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.prompt,
  });

  final String id;
  final String title;
  final String subtitle;
  final String prompt;
}

const assistantPersonalities = <AssistantPersonality>[
  AssistantPersonality(
    id: 'warm',
    title: 'Warm & friendly',
    subtitle: 'Attentive, caring and natural',
    prompt:
        'Warm, attentive and friendly. Speak naturally, show empathy and gentle humor, while staying useful, honest and respectful.',
  ),
  AssistantPersonality(
    id: 'professional',
    title: 'Professional & brief',
    subtitle: 'Focused, calm and efficient',
    prompt:
        'Professional, calm and concise. Prioritize accuracy, clear structure and practical next steps. Avoid unnecessary small talk.',
  ),
  AssistantPersonality(
    id: 'playful',
    title: 'Playful & energetic',
    subtitle: 'Lively, curious and encouraging',
    prompt:
        'Lively, curious and encouraging. Use light humor and energetic phrasing without becoming childish, distracting or imprecise.',
  ),
];

const defaultAssistantPersonalityId = 'warm';

AssistantPersonality assistantPersonalityById(String id) =>
    assistantPersonalities.firstWhere(
      (personality) => personality.id == id,
      orElse: () => assistantPersonalities.first,
    );

const femaleVoiceName = 'Leda';
const legacyFemaleVoiceName = 'Aoede';
const maleVoiceName = 'Puck';
const legacyFemaleVoiceNames = {'Aoede', 'Laomedeia', 'Sulafat'};

const milaLiveVoiceNames = <String>[
  'Sulafat',
  'Achird',
  'Achernar',
  'Vindemiatrix',
  'Leda',
  'Algieba',
  'Despina',
  'Schedar',
  'Callirrhoe',
  'Umbriel',
  'Zubenelgenubi',
  'Aoede',
  'Zephyr',
  'Autonoe',
  'Puck',
  'Laomedeia',
  'Sadachbia',
  'Fenrir',
  'Charon',
  'Rasalgethi',
  'Iapetus',
  'Erinome',
  'Sadaltager',
  'Pulcherrima',
  'Kore',
  'Orus',
  'Alnilam',
  'Gacrux',
  'Algenib',
  'Enceladus',
];

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
    this.geminiModel = 'gemini-2.5-flash',
    this.anthropicModel = 'claude-sonnet-5',
    this.geminiLiveModel = 'gemini-3.1-flash-live-preview',
    this.voiceName = femaleVoiceName,
    this.assistantName = 'MILA',
    this.personalityId = defaultAssistantPersonalityId,
    this.personality =
        'Warm, attentive and friendly. Speak naturally, show empathy and gentle humor, while staying useful, honest and respectful.',
    this.language = 'Русский',
    this.conversationStyle = MilaConversationStyle.assistant,
    this.speakingPace = MilaSpeakingPace.medium,
    this.deliveryStyle = MilaDeliveryStyle.natural,
    this.listeningProfile = MilaListeningProfile.balanced,
    this.responseLength = MilaResponseLength.brief,
    this.voiceTransport = MilaVoiceTransport.direct,
    this.voiceDirection = '',
    this.affectiveDialog = true,
    this.proactiveAudio = true,
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
  final String assistantName;
  final String personalityId;
  final String personality;
  final String language;
  final MilaConversationStyle conversationStyle;
  final MilaSpeakingPace speakingPace;
  final MilaDeliveryStyle deliveryStyle;
  final MilaListeningProfile listeningProfile;
  final MilaResponseLength responseLength;
  final MilaVoiceTransport voiceTransport;
  final String voiceDirection;
  final bool affectiveDialog;
  final bool proactiveAudio;
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
    String? assistantName,
    String? personalityId,
    String? personality,
    String? language,
    MilaConversationStyle? conversationStyle,
    MilaSpeakingPace? speakingPace,
    MilaDeliveryStyle? deliveryStyle,
    MilaListeningProfile? listeningProfile,
    MilaResponseLength? responseLength,
    MilaVoiceTransport? voiceTransport,
    String? voiceDirection,
    bool? affectiveDialog,
    bool? proactiveAudio,
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
    assistantName: assistantName ?? this.assistantName,
    personalityId: personalityId ?? this.personalityId,
    personality: personality ?? this.personality,
    language: language ?? this.language,
    conversationStyle: conversationStyle ?? this.conversationStyle,
    speakingPace: speakingPace ?? this.speakingPace,
    deliveryStyle: deliveryStyle ?? this.deliveryStyle,
    listeningProfile: listeningProfile ?? this.listeningProfile,
    responseLength: responseLength ?? this.responseLength,
    voiceTransport: voiceTransport ?? this.voiceTransport,
    voiceDirection: voiceDirection ?? this.voiceDirection,
    affectiveDialog: affectiveDialog ?? this.affectiveDialog,
    proactiveAudio: proactiveAudio ?? this.proactiveAudio,
    conciseSummaries: conciseSummaries ?? this.conciseSummaries,
    autoMemory: autoMemory ?? this.autoMemory,
    assistantSetupDone: assistantSetupDone ?? this.assistantSetupDone,
    orbSkin: orbSkin ?? this.orbSkin,
  );

  Map<String, dynamic> toJson() => {
    'v': 12,
    'onboarded': onboarded,
    'permissionsDone': permissionsDone,
    'provider': provider.name,
    'openAiModel': openAiModel,
    'geminiModel': geminiModel,
    'anthropicModel': anthropicModel,
    'geminiLiveModel': geminiLiveModel,
    'voiceName': voiceName,
    'assistantName': assistantName,
    'personalityId': personalityId,
    'personality': personality,
    'language': language,
    'conversationStyle': conversationStyle.name,
    'speakingPace': speakingPace.name,
    'deliveryStyle': deliveryStyle.name,
    'listeningProfile': listeningProfile.name,
    'responseLength': responseLength.name,
    'voiceTransport': voiceTransport.name,
    'voiceDirection': voiceDirection,
    'affectiveDialog': affectiveDialog,
    'proactiveAudio': proactiveAudio,
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
    var geminiModel = json['geminiModel'] as String? ?? 'gemini-2.5-flash';
    if (version < 11 &&
        (geminiModel == 'gemini-3.5-flash' ||
            geminiModel == 'gemini-3.1-flash')) {
      geminiModel = 'gemini-2.5-flash';
    }
    var voiceName = json['voiceName'] as String? ?? femaleVoiceName;
    if (legacyFemaleVoiceNames.contains(voiceName)) {
      voiceName = femaleVoiceName;
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
      voiceName: voiceName,
      assistantName: json['assistantName'] as String? ?? 'MILA',
      personalityId:
          json['personalityId'] as String? ?? defaultAssistantPersonalityId,
      personality: personality,
      language: language,
      conversationStyle: _enumByName(
        MilaConversationStyle.values,
        json['conversationStyle'],
        MilaConversationStyle.assistant,
      ),
      speakingPace: _enumByName(
        MilaSpeakingPace.values,
        json['speakingPace'],
        MilaSpeakingPace.medium,
      ),
      deliveryStyle: _enumByName(
        MilaDeliveryStyle.values,
        json['deliveryStyle'],
        MilaDeliveryStyle.natural,
      ),
      listeningProfile: _enumByName(
        MilaListeningProfile.values,
        json['listeningProfile'],
        MilaListeningProfile.balanced,
      ),
      responseLength: _enumByName(
        MilaResponseLength.values,
        json['responseLength'],
        MilaResponseLength.brief,
      ),
      voiceTransport: _enumByName(
        MilaVoiceTransport.values,
        json['voiceTransport'],
        MilaVoiceTransport.direct,
      ),
      voiceDirection: (json['voiceDirection'] as String? ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
      affectiveDialog: json['affectiveDialog'] as bool? ?? true,
      proactiveAudio: json['proactiveAudio'] as bool? ?? true,
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

T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) =>
    values.firstWhere((item) => item.name == value, orElse: () => fallback);
