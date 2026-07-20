import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class LlmAttachment {
  const LlmAttachment({required this.bytes, required this.mimeType});

  final List<int> bytes;
  final String mimeType;
}

class LlmMessage {
  const LlmMessage({
    required this.role,
    required this.content,
    this.attachments = const [],
  });

  final String role; // 'user' | 'assistant'
  final String content;
  final List<LlmAttachment> attachments;
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
      throw LlmException('Gemini access is not included in this build.');
    }
    final candidates = <String>[
      model,
      'gemini-2.5-flash',
      'gemini-flash-latest',
      'gemini-2.0-flash',
    ].where((value) => value.trim().isNotEmpty).toSet().toList();

    LlmException? retryableFailure;
    for (final candidate in candidates) {
      try {
        yield* _streamModel(
          model: candidate,
          messages: messages,
          systemPrompt: systemPrompt,
        );
        return;
      } on LlmException catch (error) {
        if (!_isRetryableGeminiModelError(error.message)) rethrow;
        retryableFailure = error;
      }
    }

    throw retryableFailure ??
        LlmException('Gemini could not answer with the configured models.');
  }

  Stream<String> _streamModel({
    required String model,
    required List<LlmMessage> messages,
    required String systemPrompt,
  }) async* {
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
                for (final attachment in m.attachments)
                  {
                    'inlineData': {
                      'mimeType': attachment.mimeType,
                      'data': base64Encode(attachment.bytes),
                    },
                  },
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

/// Gemini text provider backed by MILA's authenticated server proxy.
/// Provider keys stay on the server; the phone holds only a revocable session.
class MilaServerGeminiProvider implements LlmProvider {
  MilaServerGeminiProvider({
    required this.baseUrl,
    required this.sessionToken,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String sessionToken;
  final String model;
  final http.Client _client;

  @override
  Stream<String> streamChat({
    required List<LlmMessage> messages,
    required String systemPrompt,
  }) async* {
    if (baseUrl.trim().isEmpty || sessionToken.trim().isEmpty) {
      throw LlmException('Connect MILA to Agentic OS in Settings first.');
    }
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final response = await _client
        .post(
          Uri.parse('$root/v1/gemini/chat'),
          headers: {
            'Authorization': 'Bearer $sessionToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'systemPrompt': systemPrompt,
            'messages': [
              for (final message in messages)
                {
                  'role': message.role,
                  'content': message.content,
                  'attachments': [
                    for (final attachment in message.attachments)
                      {
                        'mimeType': attachment.mimeType,
                        'data': base64Encode(attachment.bytes),
                      },
                  ],
                },
            ],
          }),
        )
        .timeout(const Duration(seconds: 45));
    final json = _decodeServerJson(response.body);
    if (response.statusCode == 401) {
      throw LlmException('MILA session expired. Reconnect it in Settings.');
    }
    if (response.statusCode == 402) {
      throw LlmException('An active subscription is required.');
    }
    final text = json['text'] as String? ?? '';
    if (response.statusCode != 200 || text.isEmpty) {
      throw LlmException(
        json['error'] as String? ?? 'MILA server could not complete the chat.',
      );
    }
    yield text;
  }
}

Map<String, dynamic> _decodeServerJson(String body) {
  try {
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  } catch (_) {
    return const {};
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

bool _isRetryableGeminiModelError(String message) {
  return message.startsWith('Gemini error 404:') ||
      message.startsWith('Gemini error 429:') ||
      message.startsWith('Gemini error 500:') ||
      message.startsWith('Gemini error 503:');
}
