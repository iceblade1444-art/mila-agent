import 'package:flutter_test/flutter_test.dart';
import 'package:mila/services/voice/mila_live_tools.dart';

void main() {
  test('every personal tool name has a matching function declaration', () {
    final declared = milaLiveFunctionDeclarations
        .map((tool) => tool['name'] as String)
        .toSet();
    for (final name in milaPersonalToolNames) {
      expect(
        declared,
        contains(name),
        reason: '$name is routed to Agentic OS but never declared to Gemini',
      );
    }
    // Hermes hand-off keeps its own confirmation flow and is not a personal tool.
    expect(declared, contains('delegate_to_hermes'));
    expect(milaPersonalToolNames, isNot(contains('delegate_to_hermes')));
  });

  test('nothing that reaches other people is offered from the phone', () {
    final declared = milaLiveFunctionDeclarations
        .map((tool) => tool['name'] as String)
        .toSet();
    // Calendar writes and ERP actions need the approval UI the dashboard has;
    // declaring them here would let a voice call change a colleague's day with
    // no confirmation step in front of it.
    for (final forbidden in [
      'create_calendar_event',
      'reschedule_calendar_event',
      'cancel_calendar_event',
      'create_erp_task',
      'send_erp_notification',
      'write_obsidian_note',
      'ask_claude_code',
      'call_mcp_tool',
    ]) {
      expect(
        declared,
        isNot(contains(forbidden)),
        reason: '$forbidden must not be callable from a phone voice call',
      );
    }
    expect(declared, contains('list_my_calendar'), reason: 'reading is fine');
  });

  // Nested literals inside a const map are _ConstMap<dynamic, dynamic>, so they
  // have to be read as a plain Map rather than cast to Map<String, dynamic>.
  Map<dynamic, dynamic> mapAt(Map<dynamic, dynamic> owner, String key) =>
      owner[key] as Map<dynamic, dynamic>;

  test('declarations are shaped the way Gemini Live expects', () {
    for (final tool in milaLiveFunctionDeclarations) {
      final name = tool['name'] as String;
      expect(tool['description'], isA<String>(), reason: '$name needs a description');
      expect((tool['description'] as String).length, greaterThan(20));
      final parameters = mapAt(tool, 'parameters');
      expect(parameters['type'], 'OBJECT', reason: '$name parameters');
      final properties = mapAt(parameters, 'properties');
      for (final required in (parameters['required'] as List? ?? const [])) {
        expect(
          properties.keys,
          contains(required),
          reason: '$name requires $required but never declares it',
        );
      }
      for (final entry in properties.entries) {
        final type = (entry.value as Map<dynamic, dynamic>)['type'];
        expect(
          const ['STRING', 'INTEGER', 'BOOLEAN', 'NUMBER'],
          contains(type),
          reason: '$name.${entry.key} has an unsupported type $type',
        );
      }
    }
  });

  test('remind_me spells out that the time must be absolute', () {
    final remind = milaLiveFunctionDeclarations
        .firstWhere((tool) => tool['name'] == 'remind_me');
    final due = mapAt(mapAt(mapAt(remind, 'parameters'), 'properties'), 'dueAt');
    // A relative "in an hour" would be resolved by the server's clock, not the
    // user's, so the declaration has to demand an offset.
    expect(due['description'], contains('ISO 8601'));
    expect(due['description'], contains('offset'));
  });
}
