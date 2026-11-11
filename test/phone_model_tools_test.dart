// The personal production view reaching the phone's own tool list.
//
// Three surfaces got the model tools when they were built — the browser, the
// server-served channels and the LiveKit agent — and the phone did not, because
// on its default transport it does not read any of those lists. It declares its
// own tools here and builds its own prompt locally.
//
// The failure that followed is the one this file exists to prevent: asked about
// a real model, MILA answered that it was not in the warehouse or in the near
// orders. She was right about that and it was the wrong answer — the ERP block
// pasted into her prompt carries only those two things, the catalogue was never
// in it, and she had no tool with which to look anywhere else.

import 'package:flutter_test/flutter_test.dart';
import 'package:mila/services/voice/mila_live_tools.dart';

void main() {
  const production = ['get_my_production_intelligence'];

  test('the phone can run the scoped production tool', () {
    for (final name in production) {
      expect(
        milaPersonalToolNames,
        contains(name),
        reason: '$name is not forwarded to /api/mila/actions from the phone',
      );
    }
  });

  test('and is told it exists, which is a separate thing', () {
    // A name in the forward list with no declaration is a tool the model is
    // never offered; a declaration with no name in the list fails mid-call.
    final declared = milaLiveFunctionDeclarations
        .map((tool) => (tool['name'] ?? '').toString())
        .toSet();
    for (final name in production) {
      expect(declared, contains(name), reason: '$name has no declaration');
    }
  });

  test('every declared tool is one the phone can actually run', () {
    // A name declared to the model and handled by nothing answers
    // {'status': 'unsupported'} mid-conversation — the phone's own version of
    // announcing a tool that does not exist.
    //
    // delegate_to_hermes is the one deliberate exception: it is not forwarded
    // straight through because it stages a proposal the person confirms in
    // chat, so voice_controller gives it its own branch. Named here rather than
    // skipped, so a second exception has to be added on purpose.
    const handledElsewhere = {'delegate_to_hermes'};
    for (final tool in milaLiveFunctionDeclarations) {
      final name = (tool['name'] ?? '').toString();
      if (handledElsewhere.contains(name)) continue;
      expect(
        milaPersonalToolNames,
        contains(name),
        reason: '\$name is declared to the model but nothing runs it',
      );
    }
  });

  test('company ERP tools are absent from an employee phone', () {
    final names = milaLiveFunctionDeclarations
        .map((tool) => tool['name'])
        .toSet();
    for (final name in [
      'get_models_overview',
      'find_models',
      'get_model_details',
    ]) {
      expect(names, isNot(contains(name)));
      expect(milaPersonalToolNames, isNot(contains(name)));
    }
  });
}
