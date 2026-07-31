import 'package:flutter_test/flutter_test.dart';
import 'package:mila/data/models.dart';
import 'package:mila/services/llm/llm_service.dart';

void main() {
  group('ChatPresentation', () {
    test('extracts cards, suggestions and actions from one response', () {
      const raw = '''
Готово. Я собрала короткую сводку.

```cards
[{"type":"progress","title":"Подготовка кампании","subtitle":"Reach","metric":"68%","progress":0.68,"items":["Бриф согласован","Креатив создаётся"],"accent":"cyan"}]
```

```suggestions
["Показать бриф","Создать задачу"]
```

```actions
[{"type":"create_task","title":"Проверить кампанию","subtitle":"Сегодня"}]
```''';

      final result = LlmService.extractPresentation(raw);

      expect(result.text, 'Готово. Я собрала короткую сводку.');
      expect(result.cards, hasLength(1));
      expect(result.cards.single.type, ChatCardType.progress);
      expect(result.cards.single.progress, 0.68);
      expect(result.cards.single.items, hasLength(2));
      expect(result.suggestions, ['Показать бриф', 'Создать задачу']);
      expect(result.actions.single.type, ActionType.createTask);
    });

    test('drops malformed presentation blocks without dropping prose', () {
      const raw = '''
Ответ остаётся видимым.
```cards
not-json
```
```suggestions
{"wrong":true}
```''';

      final result = LlmService.extractPresentation(raw);

      expect(result.text, 'Ответ остаётся видимым.');
      expect(result.cards, isEmpty);
      expect(result.suggestions, isEmpty);
    });
  });

  test('old chat JSON remains backward compatible', () {
    final message = ChatMessage.fromJson({
      'id': 'legacy',
      'role': 'assistant',
      'text': 'Старое сообщение',
      'createdAt': '2026-07-31T10:00:00.000',
    });

    expect(message.cards, isEmpty);
    expect(message.suggestions, isEmpty);
    expect(message.deliveryStatus, ChatDeliveryStatus.delivered);
    expect(message.replyToText, isEmpty);
  });
}
