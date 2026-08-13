import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mila/services/voice/mila_live_tools.dart';

void main() {
  // The direct Gemini Live path builds its instruction on the phone and never
  // asks the server for one, so nothing reconciles the declarations with the
  // prompt. This is that reconciliation: a tool the phone can run has to be a
  // tool the prompt actually tells her about, or she has it and never uses it.
  test('the voice prompt mentions the tools the phone can run', () {
    final source = File(
      'lib/services/llm/llm_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('YOUR TOOLS');
    expect(start, greaterThan(-1), reason: 'the voice prompt must describe them');
    final block = source.substring(start, start + 1600);

    for (final name in [
      'search_company_knowledge',
      'get_my_day_plan',
      'remember_about_me',
      'read_about_me',
      'forget_about_me',
    ]) {
      expect(
        block,
        contains(name),
        reason: '$name is declared to Gemini but the prompt never mentions it',
      );
      expect(milaPersonalToolNames, contains(name));
    }

    // The rules that make the tools worth having at all.
    expect(block, contains('Never answer a question about the business from memory'));
    expect(block, contains('never repeat any of it to anyone else'));
    expect(block, contains('never describe it as done'));
  });

  test('the header no longer claims the server gates this list', () {
    final source = File(
      'lib/services/voice/mila_live_tools.dart',
    ).readAsStringSync();
    final header = source.substring(0, source.indexOf('library;'));
    // It said the names were sent to /api/mila/voice-instruction "as the list
    // that decides which parts of the shared prompt this device is told about".
    // They are not sent there at all, and reasoning from that sentence leads
    // straight to the wrong conclusion about what agrees with what.
    expect(header, isNot(contains('as the\n/// list that decides')));
    expect(header, contains('/api/mila/actions'));
  });
}
