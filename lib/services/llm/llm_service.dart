import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/models.dart';
import '../agentic/agentic_os_service.dart';
import '../integrations/integration_service.dart';
import '../soul/soul_service.dart';
import '../storage/stores.dart';
import 'llm_provider.dart';

/// True while a chat completion is streaming.
final chatBusyProvider = StateProvider<bool>((ref) => false);

final llmServiceProvider = Provider<LlmService>((ref) => LlmService(ref));

/// A user-facing result for an action that was explicitly approved in chat.
/// Keeping this separate from [IntegrationResult] lets local-only actions
/// (such as adding a task) and calendar hand-offs use one UI flow.
class ActionExecutionResult {
  const ActionExecutionResult(this.ok, this.message);

  final bool ok;
  final String message;
}

String _styleInstruction(MilaConversationStyle style) => switch (style) {
  MilaConversationStyle.assistant =>
    'Act as a capable personal assistant: practical, calm and attentive.',
  MilaConversationStyle.friend =>
    'Sound like a trusted, thoughtful friend: warm and relaxed, without unnecessary chatter.',
  MilaConversationStyle.operator =>
    'Act as a task operator: decisive, precise and focused on the next useful action.',
  MilaConversationStyle.mentor =>
    'Act as a patient mentor: give the answer first, then one short reason or next step when useful.',
};

String _paceInstruction(MilaSpeakingPace pace) => switch (pace) {
  MilaSpeakingPace.slow =>
    'Speak a little slower than normal and leave natural pauses between ideas.',
  MilaSpeakingPace.medium =>
    'Speak at a natural, unhurried conversational pace.',
  MilaSpeakingPace.fast =>
    'Speak briskly but keep every word clear and natural.',
};

String _deliveryInstruction(MilaDeliveryStyle delivery) => switch (delivery) {
  MilaDeliveryStyle.natural =>
    'Deliver lines the way people speak in a relaxed conversation.',
  MilaDeliveryStyle.warm =>
    'Deliver lines with extra warmth and care, as if speaking to someone you like.',
  MilaDeliveryStyle.energetic =>
    'Deliver lines with visible energy and momentum, without shouting or rushing the words together.',
  MilaDeliveryStyle.quiet =>
    'Deliver lines softly and closely, keeping volume low but articulation clear.',
  MilaDeliveryStyle.precise =>
    'Deliver lines dryly and efficiently, like a professional briefing, with minimal emotional colour.',
};

class ChatPresentation {
  const ChatPresentation({
    required this.text,
    this.actions = const [],
    this.cards = const [],
    this.suggestions = const [],
  });

  final String text;
  final List<MilaAction> actions;
  final List<ChatRichCard> cards;
  final List<String> suggestions;
}

/// Orchestrates text conversations: builds the system prompt from the
/// user's memory vault and personality settings, streams tokens from the
/// active provider into the chat store, and extracts structured actions
/// proposed by the model.
class LlmService {
  LlmService(this._ref);

  final Ref _ref;

  Future<LlmProvider> _activeProvider() async {
    final settings = _ref.read(settingsProvider);
    final secure = _ref.read(secureStoreProvider);
    final sessionToken =
        await secure.read(SecureStore.openAiAccountToken) ?? '';
    if (sessionToken.isNotEmpty) {
      return MilaServerGeminiProvider(
        baseUrl: AppConfig.configuredBackendUrl(
          await secure.read(SecureStore.milaBackendUrl),
        ),
        sessionToken: sessionToken,
        model: settings.geminiModel,
      );
    }
    switch (settings.provider) {
      case LlmProviderKind.openaiAccount:
      case LlmProviderKind.openai:
        final key =
            await secure.read(SecureStore.geminiKey) ??
            const String.fromEnvironment('GEMINI_API_KEY');
        return GeminiTextProvider(apiKey: key, model: settings.geminiModel);
      case LlmProviderKind.gemini:
        final key =
            await secure.read(SecureStore.geminiKey) ??
            const String.fromEnvironment('GEMINI_API_KEY');
        return GeminiTextProvider(apiKey: key, model: settings.geminiModel);
      case LlmProviderKind.claude:
        final key =
            await secure.read(SecureStore.anthropicKey) ??
            const String.fromEnvironment('ANTHROPIC_API_KEY');
        return AnthropicProvider(apiKey: key, model: settings.anthropicModel);
    }
  }

  /// Builds the system prompt. [forVoice] produces a spoken-conversation
  /// variant: no markdown/action-block instructions (a voice model would
  /// read them out loud), strict "numbers as words" rules and recent chat
  /// context for continuity between voice sessions.
  String buildSystemPrompt({bool forVoice = false}) {
    final settings = _ref.read(settingsProvider);
    final profile = _ref.read(profileProvider);
    final memories = _ref.read(memoriesProvider);
    final tasks = _ref.read(tasksProvider);
    final now = DateTime.now();

    final soul = _ref.read(soulServiceProvider).build(settings, profile);
    final buffer = StringBuffer()
      ..writeln(soul)
      ..writeln(
        'Treat the SOUL document above as your stable identity and follow it in every response.',
      );
    buffer.writeln(
      'CURRENT LOCAL TIME: ${now.toIso8601String()} (use this as the reference for relative dates such as "tomorrow"; never guess the current date).',
    );
    if (profile.name.isNotEmpty) {
      buffer.writeln(
        'The user\'s name is ${profile.name}. Address them by name, warmly.',
      );
    }
    buffer
      ..writeln('\nPERSONALITY')
      ..writeln(settings.personality)
      ..writeln('''

LANGUAGE RULES
- Primary language: ${settings.language}. You are fluent in Russian, English and Uzbek (both Latin and Cyrillic script; prefer Uzbek Latin).
- Always detect the language of the user's LATEST message and reply in that same language.
- Switch seamlessly whenever the user switches. Do not switch back until they do.
- If the user mixes languages, answer in the language that dominates their message.
- When the language is unclear, default to ${settings.language}.
- When the user writes or speaks Uzbek, answer in Uzbek without substituting Russian. Preserve the script they used; if they mix scripts or do not specify one, use Uzbek Latin. Use natural Uzbek names, greetings and number forms rather than transliterating Russian phrasing.

BEHAVIOR
- You are the same MILA assistant as in Agentic OS. Keep the same identity, tone and priorities across web, mobile text and live voice.
- You are first a personal assistant with your own warm, attentive personality. Help directly whenever you can: answer questions, think with the user, plan the day, suggest reminders, draft messages, organize tasks and keep the conversation alive.
- Agentic OS is your operating system and Hermes is your orchestrator, not a cage. Use them for actions, memory, files, agents, long-running work and anything that must be saved or verified across devices.
- For fresh public information such as news, trends, prices, releases, places, competitors or market facts, use the connected Gemini/server search capability when available. If the information cannot be checked inside the current session, say exactly what you need to check and offer to route a research task through Agentic OS/Hermes.
- Be precise. Never invent facts, numbers, prices, dates or events.
- If you don't know something, say so directly. If information is missing, name exactly what is missing.
- Do not claim access to the user's private calendar, email, files, money or accounts unless that data is present in this conversation or returned by a connected tool.
- Be gently proactive: when the user sounds ready to organize something, offer a concrete next step, a reminder, a daily plan or a short follow-up question.
- Separate facts from assumptions. Give recommendations with one line of reasoning.
- For a complex task, confirm: what you understood → what will be done → the immediate next step.
- Ask one short clarifying question instead of guessing.''');
    if (settings.conciseSummaries) {
      buffer.writeln('- Prefer short, useful answers over long ones.');
    }
    if (memories.isNotEmpty) {
      buffer.writeln('\nVERIFIED FACTS YOU REMEMBER ABOUT THE USER');
      for (final m in memories.take(40)) {
        buffer.writeln('- ${m.text}');
      }
    }
    final openTasks = tasks
        .where((task) => !task.done && task.enabled)
        .take(30);
    if (openTasks.isNotEmpty) {
      buffer.writeln('\nCURRENT OPEN TASKS (local to the user\'s device)');
      for (final task in openTasks) {
        final detail = task.subtitle.trim();
        buffer.writeln('- ${task.title}${detail.isEmpty ? '' : ': $detail'}');
      }
    }

    // Only the live voice path attaches the Gemini function declarations, so
    // only it is told the tools exist. Without this the phone had the tools and
    // no idea what they were for: it would answer a question about prices from
    // whatever it happened to remember, which is the exact thing the company
    // knowledge base was built to stop. The web MILA gets the same rules from
    // the shared prompt; this file is the phone's own copy, because the direct
    // Live path never asks the server for one.
    if (forVoice) {
      buffer.writeln('''

YOUR TOOLS — use them, do not answer from memory instead
- Company facts (prices, terms, fabrics, size charts, export rules per country,
  who is responsible for what): call search_company_knowledge FIRST and answer
  only from what comes back. If it finds nothing, say so and say who would know.
  Never answer a question about the business from memory.
- The user's day, tasks, notes and reminders: get_my_day_plan, list_my_tasks,
  create_my_task, save_my_note, remind_me and list_my_calendar act on their own
  private desk and run immediately. Reminders need an absolute time computed
  from the current local time above, with an explicit offset.
- What they tell you about themselves — a person they work with and how, a
  preference, a standing commitment, a date that matters — call
  remember_about_me. Record only what they actually said or confirmed, never a
  conclusion you drew from how they behaved. Use read_about_me to be genuinely
  useful, forget_about_me when they ask you to drop something. This profile is
  theirs alone: never repeat any of it to anyone else.
- "Пришли мне это в телеграм" — compose the content as a ready-to-read message
  and call send_telegram. It reaches only their own linked chat. If it returns
  linked:false, tell them to link Telegram on the Personal page of Agentic OS.
- A tool result is the only proof an action happened. If a call fails, say
  plainly that it did not happen — never describe it as done.''');

      final pace = _paceInstruction(settings.speakingPace);
      final delivery = _deliveryInstruction(settings.deliveryStyle);
      final style = _styleInstruction(settings.conversationStyle);
      final length = settings.responseLength == MilaResponseLength.brief
          ? 'Answer briefly, usually in one to three sentences. If the answer would be long, give a short summary first and offer more detail.'
          : 'Keep voice answers focused. For complex questions, give the conclusion first and then a concise explanation.';
      final voiceDirection = settings.voiceDirection.trim();
      buffer.writeln('''

SPOKEN CONVERSATION RULES — you are talking OUT LOUD in a live voice call
- $style
- Sound alive and natural: warm, calm, confident and natural. Avoid a robotic, theatrical or overly formal tone.
- $pace
- $delivery
- $length
- Never use markdown, bullet points, numbered lists, emojis, headings or code — this is speech.
- CRITICAL: pronounce ALL numbers, dates, times, prices, percentages and phone numbers as WORDS in the language you are currently speaking. In Russian say «двадцать пять процентов», «пятнадцатого марта», «в три часа дня» — never say digits in English while speaking Russian or Uzbek. This rule has no exceptions.
- Never mix two languages inside one sentence unless the user does it first.
- If you could not hear or understand the user, briefly ask them to repeat (in Uzbek: "Kechirasiz, aniq eshitmadim. Iltimos, qayta ayting."). For Uzbek names, places, phone numbers and dates, ask for confirmation instead of guessing.
- Confirm important details — names, amounts, dates — by repeating them back in words.
- For live news, trends, prices, competitor research or fresh external facts, answer from connected search/tool results when they are available. If live search is not available in this voice session, say briefly that you can check it through Agentic OS or Hermes and ask whether to start that check.
- Be a real personal assistant, and use the tools rather than describing them. For anything about today — the schedule, what is next, what is urgent — call get_my_day_plan and answer only from it; never invent a meeting or a time. Capture promises as you hear them with create_my_task, save_my_note and remind_me: they run immediately, so do them instead of offering to. For a reminder, work out the absolute time from the current local time and send it with an offset — "через час" means one hour from now, not a vague later.
- Before discussing what the day looks like, read list_my_calendar. From this device you can only read the calendar: to create or move an event, say it has to be done in the Agentic OS dashboard rather than pretending to do it here.
- If a tool answers with ok=false or an error, say plainly that it did not happen. Never confirm a task or a reminder that failed to save.
- When the user asks you to perform substantial work, call delegate_to_hermes with a short title and a precise definition of done. Explain briefly that the proposal must be confirmed in MILA chat. Never claim it was started before confirmation.
- Never write or read stage directions, emotion labels or narration of your own behavior: no [warmly], no [laughs], no *smiles*. Convey feeling through how you say the line.
- If the user asks you to whisper, calm down, speed up, slow down, sound happier or be more serious, change your delivery immediately and keep it until they ask otherwise.
- ${settings.proactiveAudio ? 'Stay quiet when speech was not aimed at you; ignore background noise and uncertain fragments.' : 'Respond to direct user speech even if the room is noisy; ask for repetition when unclear.'}
- ${settings.affectiveDialog ? 'When the model supports it, hear the user tone and answer in kind without becoming dramatic.' : 'Do not lean on emotional mirroring; keep the tone stable and practical.'}
- Do not read out URLs, file paths or JSON.''');
      if (voiceDirection.isNotEmpty) {
        buffer.writeln(
          'ADDITIONAL VOICE DIRECTION FROM THE USER: $voiceDirection',
        );
      }

      final recent = _ref
          .read(chatProvider)
          .where((m) => m.text.isNotEmpty && !m.text.startsWith('⚠️'))
          .toList();
      if (recent.isNotEmpty) {
        buffer.writeln(
          '\nRECENT CONVERSATION WITH THE USER (for continuity — do not repeat it back):',
        );
        for (final m in recent.reversed.take(12).toList().reversed) {
          final who = m.role == ChatRole.user ? 'User' : settings.assistantName;
          final line = m.text.length > 220
              ? '${m.text.substring(0, 220)}…'
              : m.text;
          buffer.writeln('$who: $line');
        }
      }
    } else {
      buffer.writeln('''

RESPONSE FORMAT (text chat)
- Simple question → direct short answer.
- Substantial business request → structure it: summary, key points, recommended action, next step.
- Messages, letters or instructions → write ready-to-use text.

When the user asks for something actionable (a task for Hermes, a reminder, a message
draft, focus time), first answer normally, then append a fenced block that
proposes actions the app can execute after user approval:

```actions
 [{"type":"create_task","title":"Review Q2 report","subtitle":"Due tomorrow"},
 {"type":"reminder","title":"Call James","subtitle":"Tomorrow at 10:00","payload":{"start":"2026-07-12T10:00:00","durationMinutes":15}},
 {"type":"focus_time","title":"Prepare Q2 report","subtitle":"Tomorrow at 14:00","payload":{"start":"2026-07-12T14:00:00","durationMinutes":90}},
 {"type":"draft_message","title":"Reply to James","subtitle":"Re: Project Update","payload":{"to":"James","subject":"Re: Project Update","body":"..."}},
 {"type":"save_memory","title":"Prefers morning meetings before 11 AM","payload":{"category":"preferences"}}]
```

Allowed types: create_task, reminder, draft_message, focus_time, save_memory.
For reminder and focus_time, include payload.start as a local ISO-8601 date
and time plus payload.durationMinutes when the user gave enough timing detail.
Do not fabricate a time: omit start when it is not known.
Use save_memory whenever the user shares a stable fact about themselves
(name, people, preferences, work) that is not already in your memory list;
category is one of people|preferences|facts.
Only include the block when there is a concrete action. Never mention the
block itself in your prose.

When structured information would be clearer than prose, append one optional
fenced `cards` JSON array. Use only facts already present in the conversation
or returned by a connected tool. Never invent live weather, prices, analytics,
deadlines or task status just to fill a card.

```cards
[{"type":"report","title":"Trend research complete","subtitle":"Scout · today","metric":"12 findings","items":["3 high-confidence opportunities","Report saved to Knowledge"],"accent":"cyan"},
 {"type":"progress","title":"Campaign preparation","subtitle":"Reach","metric":"68%","progress":0.68,"items":["Brief approved","Creative generation running"],"accent":"violet"}]
```

Allowed card types: info, task, reminder, progress, report. Keep at most three
cards and six short items per card.

When a natural next turn exists, append an optional `suggestions` JSON array
with two or three short user replies:

```suggestions
["Show the report","Create a task","Remind me tomorrow"]
```

Do not include suggestions for errors, sensitive confirmations, or when a
clarifying question already requires a free-form answer. Never mention these
structured blocks in your prose.''');
    }
    return buffer.toString();
  }

  /// Sends [text] and streams the reply into the chat store.
  /// Returns the assistant message id, or null on failure.
  Future<String?> send(
    String text, {
    bool viaVoice = false,
    List<ChatAttachment> attachments = const [],
    String replyToText = '',
  }) async {
    final chat = _ref.read(chatProvider.notifier);
    final busy = _ref.read(chatBusyProvider.notifier);

    chat.add(
      ChatMessage(
        role: ChatRole.user,
        text: text,
        attachments: attachments,
        viaVoice: viaVoice,
        deliveryStatus: ChatDeliveryStatus.sent,
        replyToText: replyToText,
      ),
    );

    final assistant = ChatMessage(
      role: ChatRole.assistant,
      text: '',
      deliveryStatus: ChatDeliveryStatus.sending,
    );
    chat.add(assistant);
    busy.state = true;

    try {
      final provider = await _activeProvider();
      final storedHistory = _ref
          .read(chatProvider)
          .where((m) => m.text.isNotEmpty || m.attachments.isNotEmpty)
          .toList()
          .reversed
          .take(24)
          .toList()
          .reversed
          .toList();
      final history = <LlmMessage>[];
      for (var index = 0; index < storedHistory.length; index++) {
        final message = storedHistory[index];
        final inline = <LlmAttachment>[];
        // Re-sending every historical image can cross Gemini's inline request
        // limit very quickly. The current turn gets its files; older turns are
        // represented by their text and the model's prior answer.
        final currentAttachments = index == storedHistory.length - 1
            ? message.attachments
            : const <ChatAttachment>[];
        for (final attachment in currentAttachments) {
          final file = File(attachment.path);
          if (!await file.exists()) continue;
          final size = await file.length();
          if (size > 15 * 1024 * 1024) continue;
          inline.add(
            LlmAttachment(
              bytes: await file.readAsBytes(),
              mimeType: attachment.mimeType,
            ),
          );
        }
        history.add(
          LlmMessage(
            role: message.role == ChatRole.user ? 'user' : 'assistant',
            content: message.text.isEmpty
                ? 'Please inspect the attached content.'
                : message.text,
            attachments: inline,
          ),
        );
      }

      final full = StringBuffer();
      await for (final delta in provider.streamChat(
        messages: history,
        systemPrompt: buildSystemPrompt(),
      )) {
        full.write(delta);
        chat.appendText(assistant.id, delta);
      }

      final presentation = extractPresentation(full.toString());
      // Memory updates are local and harmless: apply them silently when
      // auto-memory is on (the card still shows what was saved).
      if (_ref.read(settingsProvider).autoMemory) {
        for (final action in presentation.actions.where(
          (a) => a.type == ActionType.saveMemory,
        )) {
          _saveMemoryAction(action);
          action.status = ActionStatus.approved;
        }
      }
      chat.replace(
        ChatMessage(
          id: assistant.id,
          role: ChatRole.assistant,
          text: presentation.text,
          createdAt: assistant.createdAt,
          actions: presentation.actions,
          cards: presentation.cards,
          suggestions: presentation.suggestions,
          deliveryStatus: ChatDeliveryStatus.delivered,
        ),
      );
      return assistant.id;
    } on LlmException catch (e) {
      chat.replace(
        ChatMessage(
          id: assistant.id,
          role: ChatRole.assistant,
          text: '⚠️ ${e.message}',
          createdAt: assistant.createdAt,
          deliveryStatus: ChatDeliveryStatus.failed,
        ),
      );
      return null;
    } catch (e) {
      chat.replace(
        ChatMessage(
          id: assistant.id,
          role: ChatRole.assistant,
          text: '⚠️ Something went wrong: $e',
          createdAt: assistant.createdAt,
          deliveryStatus: ChatDeliveryStatus.failed,
        ),
      );
      return null;
    } finally {
      busy.state = false;
      _ref.read(chatSyncProvider.notifier).schedule();
    }
  }

  /// Splits the model output into prose and a parsed ```actions``` block.
  static (String, List<MilaAction>) extractActions(String raw) {
    final match = RegExp(
      r'```actions\s*([\s\S]*?)```',
      multiLine: true,
    ).firstMatch(raw);
    if (match == null) return (raw.trim(), <MilaAction>[]);

    final clean = raw.replaceRange(match.start, match.end, '').trim();
    try {
      final list = jsonDecode(match.group(1)!.trim()) as List;
      final actions = list.map((e) {
        final map = (e as Map).cast<String, dynamic>();
        return MilaAction(
          type: MilaAction.typeFrom(map['type'] as String? ?? ''),
          title: map['title'] as String? ?? 'Action',
          subtitle: map['subtitle'] as String? ?? '',
          payload: (map['payload'] as Map?)?.cast<String, dynamic>(),
        );
      }).toList();
      return (clean, actions);
    } catch (_) {
      return (clean, <MilaAction>[]);
    }
  }

  static ChatPresentation extractPresentation(String raw) {
    final (withoutActions, actions) = extractActions(raw);
    var clean = withoutActions;
    final cards = <ChatRichCard>[];
    final suggestions = <String>[];

    final cardsMatch = RegExp(
      r'```cards\s*([\s\S]*?)```',
      multiLine: true,
    ).firstMatch(clean);
    if (cardsMatch != null) {
      clean = clean.replaceRange(cardsMatch.start, cardsMatch.end, '').trim();
      try {
        final decoded = jsonDecode(cardsMatch.group(1)!.trim()) as List;
        for (final value in decoded.take(3)) {
          final map = (value as Map).cast<String, dynamic>();
          final title = map['title']?.toString().trim() ?? '';
          if (title.isEmpty) continue;
          cards.add(
            ChatRichCard(
              type: ChatCardType.values.firstWhere(
                (type) => type.name == map['type'],
                orElse: () => ChatCardType.info,
              ),
              title: title,
              subtitle: map['subtitle']?.toString() ?? '',
              metric: map['metric']?.toString() ?? '',
              progress: switch (map['progress']) {
                final num value => value.toDouble().clamp(0.0, 1.0).toDouble(),
                _ => null,
              },
              items: ((map['items'] as List?) ?? [])
                  .map((item) => item.toString().trim())
                  .where((item) => item.isNotEmpty)
                  .take(6)
                  .toList(),
              accent: map['accent']?.toString() ?? 'violet',
            ),
          );
        }
      } catch (_) {
        cards.clear();
      }
    }

    final suggestionsMatch = RegExp(
      r'```suggestions\s*([\s\S]*?)```',
      multiLine: true,
    ).firstMatch(clean);
    if (suggestionsMatch != null) {
      clean = clean
          .replaceRange(suggestionsMatch.start, suggestionsMatch.end, '')
          .trim();
      try {
        final decoded = jsonDecode(suggestionsMatch.group(1)!.trim()) as List;
        suggestions.addAll(
          decoded
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty && value.length <= 80)
              .take(3),
        );
      } catch (_) {
        suggestions.clear();
      }
    }

    return ChatPresentation(
      text: clean,
      actions: actions,
      cards: cards,
      suggestions: suggestions,
    );
  }

  /// Executes an approved action. Hermes tasks go to the shared Agentic OS
  /// Kanban when the mobile account is connected.
  Future<ActionExecutionResult> applyAction(
    String messageId,
    MilaAction action,
  ) async {
    final tasks = _ref.read(tasksProvider.notifier);
    var result = const ActionExecutionResult(true, 'Action completed');
    switch (action.type) {
      case ActionType.createTask:
        final agentic = _ref.read(agenticOsServiceProvider);
        if (await agentic.isConnected()) {
          try {
            // This card comes from delegate_to_hermes, which the user approved
            // believing the work goes to Hermes. It used to POST /api/member/tasks
            // — the private personal desk — and then say "Sent to Hermes", so the
            // task existed only as a note to themselves while they were told a
            // fleet had picked it up. Call the action she actually offered.
            // A write action is staged first and executed only against its
            // token. Approving this card is the human confirmation the server is
            // waiting for, so the two calls happen together — but the second one
            // is what actually sends it, and without it "Sent to Hermes" would
            // still be a sentence about something that had not happened.
            final staged = await agentic.runMilaAction('delegate_to_hermes', {
              'title': action.title,
              if (action.subtitle.isNotEmpty) 'details': action.subtitle,
            });
            if (staged['confirmationToken'] case final String token) {
              await agentic.runMilaAction('delegate_to_hermes', {
                'confirmationToken': token,
              });
            }
            await _ref
                .read(agenticTasksProvider.notifier)
                .refresh(silent: true);
            result = ActionExecutionResult(
              true,
              'Sent to Hermes: ${action.title}',
            );
          } on AgenticOsException catch (error) {
            // Delegating is operator work, so an employee's phone is refused it.
            // Saying that is the answer; quietly writing a personal task and
            // calling it Hermes is how this went wrong in the first place.
            return ActionExecutionResult(false, error.message);
          }
        } else {
          tasks.add(TaskItem(title: action.title, subtitle: action.subtitle));
          result = ActionExecutionResult(
            true,
            'Saved locally. Connect Agentic OS to delegate it to Hermes.',
          );
        }
      case ActionType.reminder:
        tasks.add(
          TaskItem(
            title: action.title,
            subtitle: action.subtitle.isEmpty ? 'Reminder' : action.subtitle,
          ),
        );
        result = await _addToCalendarIfScheduled(action, 'Reminder');
      case ActionType.focusTime:
        tasks.add(
          TaskItem(
            title: 'Focus time — ${action.title}',
            subtitle: action.subtitle,
          ),
        );
        result = await _addToCalendarIfScheduled(action, 'Focus time');
      case ActionType.saveMemory:
        _saveMemoryAction(action);
        result = const ActionExecutionResult(true, 'Saved to Memory Vault');
      case ActionType.draftMessage:
      case ActionType.unknown:
        return const ActionExecutionResult(
          false,
          'This action needs review before it can be completed.',
        );
    }
    _ref
        .read(chatProvider.notifier)
        .setActionStatus(messageId, action.id, ActionStatus.approved);
    return result;
  }

  Future<ActionExecutionResult> _addToCalendarIfScheduled(
    MilaAction action,
    String kind,
  ) async {
    final rawStart = action.payload['start'] as String?;
    final start = rawStart == null ? null : DateTime.tryParse(rawStart);
    if (start == null) {
      return ActionExecutionResult(true, '$kind added to Tasks');
    }
    final minutes = action.payload['durationMinutes'];
    final durationMinutes = minutes is num ? minutes.toInt() : 60;
    final safeDurationMinutes = durationMinutes.clamp(5, 480).toInt();
    final calendar = await _ref
        .read(integrationServiceProvider)
        .addCalendarEvent(
          title: action.title,
          description: action.subtitle,
          start: start,
          duration: Duration(minutes: safeDurationMinutes),
        );
    return ActionExecutionResult(
      calendar.ok,
      calendar.ok
          ? '$kind added to Tasks; review it in your calendar'
          : '$kind added to Tasks. ${calendar.message}',
    );
  }

  void _saveMemoryAction(MilaAction action) {
    final text = (action.payload['text'] as String?) ?? action.title;
    if (text.trim().isEmpty) return;
    final item = MemoryItem(
      text: text.trim(),
      category: _categoryFrom(action.payload['category'] as String?),
    );
    _ref.read(memoriesProvider.notifier).add(item);
    unawaited(_syncMemory(item));
  }

  Future<void> _syncMemory(MemoryItem item) async {
    final agentic = _ref.read(agenticOsServiceProvider);
    if (!await agentic.isConnected()) return;
    try {
      final remote = await agentic.appendMemory(item);
      _ref.read(memoriesProvider.notifier).mergeRemote([remote]);
    } on AgenticOsException {
      // The local memory remains available and the Memory screen can retry.
    }
  }

  static MemoryCategory _categoryFrom(String? raw) => switch (raw) {
    'people' => MemoryCategory.people,
    'preferences' => MemoryCategory.preferences,
    _ => MemoryCategory.facts,
  };

  /// After a voice session, mine the transcript for stable user facts and
  /// store them in the Memory Vault (runs in the background, silent).
  Future<void> mineMemoriesFromTranscript(List<String> transcript) async {
    final settings = _ref.read(settingsProvider);
    if (!settings.autoMemory || transcript.isEmpty) return;
    try {
      final provider = await _activeProvider();
      final existing = _ref
          .read(memoriesProvider)
          .take(40)
          .map((m) => '- ${m.text}')
          .join('\n');
      final prompt =
          '''
Below is a voice conversation transcript between a user and their assistant.
Extract up to 3 NEW stable facts about the user worth remembering long-term
(name, people, preferences, work, recurring plans). Skip small talk and
anything already known.

Already known:
$existing

Transcript:
${transcript.join('\n')}

Respond with ONLY a JSON array like
[{"text":"...","category":"people|preferences|facts"}] — or [] if nothing.''';

      final buffer = StringBuffer();
      await for (final delta in provider.streamChat(
        messages: [LlmMessage(role: 'user', content: prompt)],
        systemPrompt:
            'You extract long-term user memory facts. Output strictly JSON.',
      )) {
        buffer.write(delta);
      }

      final raw = buffer
          .toString()
          .replaceAll(RegExp(r'```(json)?'), '')
          .trim();
      final start = raw.indexOf('[');
      final end = raw.lastIndexOf(']');
      if (start < 0 || end <= start) return;
      final list = jsonDecode(raw.substring(start, end + 1)) as List;
      final memories = _ref.read(memoriesProvider.notifier);
      for (final item in list.take(3)) {
        final map = (item as Map).cast<String, dynamic>();
        final text = (map['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          memories.add(
            MemoryItem(
              text: text,
              category: _categoryFrom(map['category'] as String?),
            ),
          );
        }
      }
    } catch (_) {
      // Memory mining is best-effort; never surface errors to the user.
    }
  }
}
