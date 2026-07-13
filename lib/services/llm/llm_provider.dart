import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class LlmMessage {
  const LlmMessage({required this.role, required this.content});

  final String role; // 'user' | 'assistant'
  final String content;
}

class LlmException implements Exception {
  LlmException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Provider-agnostic streaming chat interface. Implementations exist for
/// Gemini and Claude; adding another vendor only requires a new subclass.
abstract class LlmProvider {
  Stream<String> streamChat({
    required List<LlmMessage> messages,
    required String systemPrompt,
  });
}

/// Shared SSE line-stream helper.
Stream<String> sseLines(http.StreamedResponse response) =>
    response.stream.transform(utf8.decoder).transform(const LineSplitter());

class GeminiTextProvider implements LlmProvider {
  GeminiTextProvider({
    required this.apiKey,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  @override
  Stream<String> streamChat({
    required List<LlmMessage> messages,
    required String systemPrompt,
  }) async* {
    if (apiKey.isEmpty) {
      throw LlmException(
        'Gemini API key is missing. Add it in Settings → AI Providers.',
      );
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?alt=sse',
    );
    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      })
      ..body = jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
        'contents': [
          for (final m in messages)
            {
              'role': m.role == 'assistant' ? 'model' : 'user',
              'parts': [
                {'text': m.content},
              ],
            },
        ],
      });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      throw LlmException('Could not reach Gemini. Check your connection.');
    }

    if (response.statusCode == 400 || response.statusCode == 403) {
      throw LlmException('Gemini rejected the API key. Check it in Settings.');
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw LlmException(
        'Gemini error ${response.statusCode}: ${_apiErrorMessage(body)}',
      );
    }

    await for (final line in sseLines(response)) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final parts =
            ((((json['candidates'] as List?)?.firstOrNull as Map?)?['content']
                    as Map?)?['parts']
                as List?) ??
            [];
        for (final part in parts) {
          final text = (part as Map)['text'] as String?;
          if (text != null && text.isNotEmpty) yield text;
        }
      } catch (_) {
        // Ignore malformed chunks.
      }
    }
  }
}

class AnthropicProvider implements LlmProvider {
  AnthropicProvider({
    required this.apiKey,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  @override
  Stream<String> streamChat({
    required List<LlmMessage> messages,
    required String systemPrompt,
  }) async* {
    if (apiKey.isEmpty) {
      throw LlmException(
        'Claude API key is missing. Add it in Settings → AI Providers.',
      );
    }
    final request =
        http.Request('POST', Uri.parse('https://api.anthropic.com/v1/messages'))
          ..headers.addAll({
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'model': model,
            'max_tokens': 4096,
            'stream': true,
            'system': systemPrompt,
            'messages': [
              for (final m in messages) {'role': m.role, 'content': m.content},
            ],
          });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      throw LlmException('Could not reach Claude. Check your connection.');
    }

    if (response.statusCode == 401) {
      throw LlmException('Claude rejected the API key. Check it in Settings.');
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw LlmException(
        'Claude error ${response.statusCode}: ${_apiErrorMessage(body)}',
      );
    }

    await for (final line in sseLines(response)) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        if (json['type'] == 'content_block_delta') {
          final text = (json['delta'] as Map?)?['text'] as String?;
          if (text != null && text.isNotEmpty) yield text;
        }
      } catch (_) {
        // Ignore ping/other events.
      }
    }
  }
}

String _apiErrorMessage(String body) {
  try {
    final json = jsonDecode(body);
    return ((json as Map)['error'] as Map?)?['message'] as String? ?? body;
  } catch (_) {
    return body.length > 200 ? body.substring(0, 200) : body;
  }
}
