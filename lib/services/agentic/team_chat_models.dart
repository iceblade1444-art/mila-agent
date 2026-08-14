/// Models for the corporate chat.
///
/// These mirror what the Agentic OS messenger returns to the web client, and
/// deliberately parse only what the phone shows: membership is enforced by the
/// server, so anything the phone receives is already something this account may
/// read.
library;

String _s(dynamic value) => (value ?? '').toString();

class TeamPerson {
  const TeamPerson({
    required this.id,
    required this.name,
    required this.role,
    required this.online,
  });

  final String id;
  final String name;
  final String role;
  final bool online;

  bool get isAgent => id.startsWith('agent:');

  factory TeamPerson.fromJson(Map<String, dynamic> json) => TeamPerson(
    id: _s(json['id']),
    name: _s(json['name']),
    role: _s(json['role']),
    online: json['online'] == true,
  );
}

class TeamMessage {
  const TeamMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.text,
    required this.deleted,
    required this.createdAt,
    required this.attachmentCount,
  });

  final String id;
  final String authorId;
  final String authorName;

  /// `user` for a person, `agent` for MILA's own messages.
  final String kind;
  final String text;
  final bool deleted;
  final String createdAt;
  final int attachmentCount;

  factory TeamMessage.fromJson(Map<String, dynamic> json) => TeamMessage(
    id: _s(json['id']),
    authorId: _s(json['authorId']),
    authorName: _s(json['authorName']),
    kind: _s(json['kind']),
    text: _s(json['text']),
    deleted: json['deleted'] == true,
    createdAt: _s(json['createdAt']),
    attachmentCount: (json['attachments'] as List?)?.length ?? 0,
  );
}

class TeamConversation {
  const TeamConversation({
    required this.id,
    required this.kind,
    required this.name,
    required this.unread,
    required this.mentioned,
    required this.lastMessage,
    required this.lastActivityAt,
    required this.memberIds,
  });

  final String id;

  /// `channel` or `direct`. A direct thread arrives already titled by the
  /// other person's name — the server decorates it, the phone never guesses.
  final String kind;
  final String name;
  final int unread;
  final bool mentioned;
  final TeamMessage? lastMessage;
  final String lastActivityAt;
  final List<String> memberIds;

  factory TeamConversation.fromJson(Map<String, dynamic> json) =>
      TeamConversation(
        id: _s(json['id']),
        kind: _s(json['kind']),
        name: _s(json['name']),
        unread: (json['unread'] as num?)?.toInt() ?? 0,
        mentioned: json['mentioned'] == true,
        lastMessage: json['lastMessage'] is Map
            ? TeamMessage.fromJson(
                (json['lastMessage'] as Map).cast<String, dynamic>(),
              )
            : null,
        lastActivityAt: _s(json['lastActivityAt']),
        memberIds: ((json['memberIds'] as List?) ?? const [])
            .map(_s)
            .toList(growable: false),
      );
}

/// The one response behind the conversation list: who I am, who exists, and
/// every thread I am a member of.
class TeamChatHome {
  const TeamChatHome({
    required this.meId,
    required this.people,
    required this.conversations,
  });

  final String meId;
  final List<TeamPerson> people;
  final List<TeamConversation> conversations;

  factory TeamChatHome.fromJson(Map<String, dynamic> json) => TeamChatHome(
    meId: _s((json['me'] as Map?)?['id']),
    people: ((json['people'] as List?) ?? const [])
        .whereType<Map>()
        .map((value) => TeamPerson.fromJson(value.cast<String, dynamic>()))
        .toList(growable: false),
    conversations: ((json['conversations'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (value) => TeamConversation.fromJson(value.cast<String, dynamic>()),
        )
        .toList(growable: false),
  );
}
