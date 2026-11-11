import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mila/services/storage/stores.dart';

void main() {
  test('private Hive data is isolated between signed-in accounts', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mila-account-scope-',
    );
    Hive.init(directory.path);
    final box = await Hive.openBox<String>('account-scope');
    final store = LocalStore(box);

    await box.put('chat', '[{"id":"legacy"}]');
    await store.setAccountScope('User-A');
    expect(store.readList('chat').single['id'], 'legacy');
    await store.writeJson('tasks', [
      {'id': 'task-a'},
    ]);

    await store.setAccountScope('User-B');
    expect(store.readList('chat'), isEmpty);
    expect(store.readList('tasks'), isEmpty);
    await store.writeJson('chat', [
      {'id': 'message-b'},
    ]);

    await store.setAccountScope('User-A');
    expect(store.readList('chat').single['id'], 'legacy');
    expect(store.readList('tasks').single['id'], 'task-a');

    await store.setAccountScope('User-B');
    expect(store.readList('chat').single['id'], 'message-b');
    await store.setAccountScope('');
    expect(store.readList('chat'), isEmpty);

    await box.close();
    await directory.delete(recursive: true);
  });
}
