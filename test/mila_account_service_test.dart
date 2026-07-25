import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mila/services/auth/mila_account_service.dart';

void main() {
  test('signs in once and creates account plus voice sessions', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/auth/mobile/login') {
        expect(jsonDecode(request.body), {
          'email': 'member@example.com',
          'password': 'long-password',
        });
        return http.Response(
          jsonEncode({
            'accessToken': 'account-token',
            'user': {
              'id': 'usr_member',
              'name': 'Member',
              'email': 'member@example.com',
              'role': 'Member',
            },
          }),
          200,
        );
      }
      expect(request.url.path, '/mila/v1/auth/agentic');
      expect(request.headers['authorization'], 'Bearer account-token');
      return http.Response(
        jsonEncode({'token': 'voice-token', 'label': 'member@example.com'}),
        201,
      );
    });

    final session = await const MilaAccountService().signIn(
      baseUrl: 'https://agent.example.test/mila',
      email: 'member@example.com',
      password: 'long-password',
      client: client,
    );

    expect(requests.length, 2);
    expect(session.accountToken, 'account-token');
    expect(session.token, 'voice-token');
    expect(session.ownerName, 'Member');
    expect(session.ownerRole, 'Member');
  });

  test('exchanges a normalized one-time code for a MILA session', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://example.test/v1/auth/device');
      expect(jsonDecode(request.body), {'code': 'AB12CD34'});
      return http.Response(
        jsonEncode({
          'token': 'session-token',
          'label': 'Mobile user',
          'owner': {'name': 'Creator', 'email': 'creator@example.com'},
        }),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    });

    final session = await const MilaAccountService().exchangeCode(
      baseUrl: 'https://example.test/',
      code: 'ab12cd34',
      client: client,
    );

    expect(session.token, 'session-token');
    expect(session.label, 'Mobile user');
    expect(session.ownerName, 'Creator');
    expect(session.ownerEmail, 'creator@example.com');
  });

  test('rejects an invalid connection code before making a request', () async {
    expect(
      () => const MilaAccountService().exchangeCode(
        baseUrl: 'https://example.test',
        code: 'bad',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
