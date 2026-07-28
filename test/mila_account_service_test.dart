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

  test('Creator can sign in without an email address', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/mobile/login') {
        expect(jsonDecode(request.body), {
          'email': '',
          'password': 'creator-password',
        });
        return http.Response(
          jsonEncode({
            'accessToken': 'creator-account-token',
            'user': {
              'id': 'creator',
              'name': 'Creator',
              'email': '',
              'role': 'Creator',
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'token': 'creator-voice-token'}), 201);
    });

    final session = await const MilaAccountService().signIn(
      baseUrl: 'https://agent.example.test/mila',
      email: '',
      password: 'creator-password',
      client: client,
    );

    expect(session.label, 'Creator');
    expect(session.ownerRole, 'Creator');
  });

  test(
    'completes a mobile MFA challenge before creating voice session',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/auth/mobile/login') {
          return http.Response(
            jsonEncode({
              'mfaRequired': true,
              'challenge': 'short-lived-challenge',
              'expiresInSeconds': 300,
              'user': {'name': 'Creator', 'role': 'Creator'},
            }),
            202,
          );
        }
        if (request.url.path == '/api/auth/mfa/verify') {
          expect(jsonDecode(request.body), {
            'challenge': 'short-lived-challenge',
            'code': '123456',
          });
          return http.Response(
            jsonEncode({
              'accessToken': 'mfa-account-token',
              'user': {
                'name': 'Creator',
                'email': 'creator@example.com',
                'role': 'Creator',
              },
            }),
            200,
          );
        }
        expect(request.url.path, '/mila/v1/auth/agentic');
        expect(request.headers['authorization'], 'Bearer mfa-account-token');
        return http.Response(jsonEncode({'token': 'mfa-voice-token'}), 201);
      });

      MilaMfaRequiredException? challenge;
      try {
        await const MilaAccountService().signIn(
          baseUrl: 'https://agent.example.test/mila',
          email: '',
          password: 'creator-password',
          client: client,
        );
      } on MilaMfaRequiredException catch (error) {
        challenge = error;
      }

      expect(challenge?.challenge, 'short-lived-challenge');
      expect(challenge?.expiresInSeconds, 300);
      expect(requests.length, 1);

      final session = await const MilaAccountService().verifyMfa(
        baseUrl: 'https://agent.example.test/mila',
        challenge: challenge!.challenge,
        code: '123 456',
        client: client,
      );

      expect(requests.length, 3);
      expect(session.accountToken, 'mfa-account-token');
      expect(session.token, 'mfa-voice-token');
      expect(session.ownerRole, 'Creator');
    },
  );

  test('exchanges a normalized one-time code for a MILA session', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/mila/v1/auth/device') {
        expect(jsonDecode(request.body), {'code': 'AB12CD34'});
        return http.Response(
          jsonEncode({
            'token': 'session-token',
            'label': 'Mobile user',
            'accountGrant': 'short-lived-pairing-grant',
            'owner': {'name': 'Creator', 'email': 'creator@example.com'},
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }
      expect(request.url.path, '/api/auth/mobile/exchange');
      expect(jsonDecode(request.body), {'grant': 'short-lived-pairing-grant'});
      return http.Response(
        jsonEncode({
          'accessToken': 'agentic-account-token',
          'user': {
            'name': 'Creator',
            'email': 'creator@example.com',
            'role': 'Creator',
          },
        }),
        200,
      );
    });

    final session = await const MilaAccountService().exchangeCode(
      baseUrl: 'https://example.test/mila',
      code: 'ab12cd34',
      client: client,
    );

    expect(requests.length, 2);
    expect(session.token, 'session-token');
    expect(session.accountToken, 'agentic-account-token');
    expect(session.label, 'Mobile user');
    expect(session.ownerName, 'Creator');
    expect(session.ownerEmail, 'creator@example.com');
    expect(session.ownerRole, 'Creator');
  });

  test(
    'legacy voice-only code still connects without an account grant',
    () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'token': 'voice-only-token', 'label': 'Voice only'}),
          200,
        ),
      );
      final session = await const MilaAccountService().exchangeCode(
        baseUrl: 'https://example.test/mila',
        code: 'AB12CD34',
        client: client,
      );
      expect(session.token, 'voice-only-token');
      expect(session.accountToken, isEmpty);
    },
  );

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
