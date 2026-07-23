import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mila/services/auth/mila_account_service.dart';

void main() {
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
