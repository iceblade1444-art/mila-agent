import 'dart:convert';

import 'package:http/http.dart' as http;

class MilaAccountSession {
  const MilaAccountSession({
    required this.token,
    required this.label,
    this.accountToken = '',
    this.ownerId = '',
    this.ownerName = '',
    this.ownerEmail = '',
    this.ownerRole = 'Member',
  });

  /// Token used only with the MILA voice gateway.
  final String token;

  /// Agentic OS account token used for personal tasks, notes and profile data.
  final String accountToken;
  final String ownerId;
  final String label;
  final String ownerName;
  final String ownerEmail;
  final String ownerRole;
}

class MilaMfaRequiredException implements Exception {
  const MilaMfaRequiredException({
    required this.challenge,
    required this.expiresInSeconds,
    this.ownerName = '',
    this.ownerRole = 'Member',
  });

  final String challenge;
  final int expiresInSeconds;
  final String ownerName;
  final String ownerRole;
}

class MilaAccountService {
  const MilaAccountService();

  Future<MilaAccountSession> signIn({
    required String baseUrl,
    required String email,
    required String password,
    http.Client? client,
  }) => _authenticate(
    baseUrl: baseUrl,
    body: {'email': email.trim(), 'password': password},
    register: false,
    client: client,
  );

  Future<MilaAccountSession> register({
    required String baseUrl,
    required String name,
    required String email,
    required String password,
    http.Client? client,
  }) => _authenticate(
    baseUrl: baseUrl,
    body: {'name': name.trim(), 'email': email.trim(), 'password': password},
    register: true,
    client: client,
  );

  Future<MilaAccountSession> _authenticate({
    required String baseUrl,
    required Map<String, String> body,
    required bool register,
    http.Client? client,
  }) async {
    final milaRoot = _root(baseUrl);
    final agenticRoot = _agenticRoot(milaRoot);
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final accountResponse = await httpClient
          .post(
            Uri.parse(
              '$agenticRoot/api/auth/mobile/${register ? 'register' : 'login'}',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
      final accountJson = _decode(accountResponse.body);
      if (accountResponse.statusCode == 202 &&
          accountJson['mfaRequired'] == true) {
        final challenge = accountJson['challenge'] as String? ?? '';
        if (challenge.isEmpty) {
          throw const FormatException(
            'The server did not return an MFA challenge.',
          );
        }
        final owner = ((accountJson['user'] as Map?) ?? const {})
            .cast<String, dynamic>();
        throw MilaMfaRequiredException(
          challenge: challenge,
          expiresInSeconds:
              (accountJson['expiresInSeconds'] as num?)?.toInt() ?? 300,
          ownerName: owner['name'] as String? ?? '',
          ownerRole: owner['role'] as String? ?? 'Member',
        );
      }
      final accountToken = accountJson['accessToken'] as String? ?? '';
      final owner = ((accountJson['user'] as Map?) ?? const {})
          .cast<String, dynamic>();
      if (accountResponse.statusCode < 200 ||
          accountResponse.statusCode >= 300 ||
          accountToken.isEmpty) {
        throw FormatException(
          accountJson['error'] as String? ?? 'Could not sign in to Agentic OS.',
        );
      }

      return await _createSession(
        milaRoot: milaRoot,
        accountToken: accountToken,
        owner: owner,
        client: httpClient,
      );
    } finally {
      if (shouldClose) httpClient.close();
    }
  }

  Future<MilaAccountSession> verifyMfa({
    required String baseUrl,
    required String challenge,
    required String code,
    http.Client? client,
  }) async {
    final milaRoot = _root(baseUrl);
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final response = await httpClient
          .post(
            Uri.parse('${_agenticRoot(milaRoot)}/api/auth/mfa/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'challenge': challenge,
              'code': code.trim().replaceAll(' ', ''),
            }),
          )
          .timeout(const Duration(seconds: 12));
      final json = _decode(response.body);
      final accountToken = json['accessToken'] as String? ?? '';
      final owner = ((json['user'] as Map?) ?? const {})
          .cast<String, dynamic>();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          accountToken.isEmpty) {
        throw FormatException(
          json['error'] as String? ?? 'Could not verify the MFA code.',
        );
      }
      return await _createSession(
        milaRoot: milaRoot,
        accountToken: accountToken,
        owner: owner,
        client: httpClient,
      );
    } finally {
      if (shouldClose) httpClient.close();
    }
  }

  Future<MilaAccountSession> _createSession({
    required String milaRoot,
    required String accountToken,
    required Map<String, dynamic> owner,
    required http.Client client,
  }) async {
    final voiceResponse = await client
        .post(
          Uri.parse('$milaRoot/v1/auth/agentic'),
          headers: {'Authorization': 'Bearer $accountToken'},
        )
        .timeout(const Duration(seconds: 12));
    final voiceJson = _decode(voiceResponse.body);
    final voiceToken = voiceJson['token'] as String? ?? '';
    if (voiceResponse.statusCode < 200 ||
        voiceResponse.statusCode >= 300 ||
        voiceToken.isEmpty) {
      throw FormatException(
        voiceJson['error'] as String? ??
            'Could not create the MILA voice session.',
      );
    }

    return MilaAccountSession(
      token: voiceToken,
      accountToken: accountToken,
      ownerId: owner['id'] as String? ?? '',
      label: (owner['email'] as String? ?? '').trim().isNotEmpty
          ? owner['email'] as String
          : (owner['name'] as String? ?? 'MILA user'),
      ownerName: owner['name'] as String? ?? '',
      ownerEmail: owner['email'] as String? ?? '',
      ownerRole: owner['role'] as String? ?? 'Member',
    );
  }

  Future<MilaAccountSession> exchangeCode({
    required String baseUrl,
    required String code,
    http.Client? client,
  }) async {
    final root = _root(baseUrl);
    if (root.isEmpty) {
      throw const FormatException('MILA server URL is required.');
    }
    final normalizedCode = code.trim().toUpperCase();
    if (!RegExp(r'^[A-F0-9]{8}$').hasMatch(normalizedCode)) {
      throw const FormatException('Enter the 8-character connection code.');
    }

    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final response = await httpClient
          .post(
            Uri.parse('$root/v1/auth/device'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': normalizedCode}),
          )
          .timeout(const Duration(seconds: 12));
      final json = _decode(response.body);
      final token = json['token'] as String? ?? '';
      final label = json['label'] as String? ?? 'MILA user';
      var owner = ((json['owner'] as Map?) ?? const {}).cast<String, dynamic>();
      if (response.statusCode != 200 || token.isEmpty) {
        throw FormatException(
          json['error'] as String? ?? 'Could not connect the MILA account.',
        );
      }
      var accountToken = '';
      final accountGrant = json['accountGrant'] as String? ?? '';
      if (accountGrant.isNotEmpty) {
        final accountResponse = await httpClient
            .post(
              Uri.parse('${_agenticRoot(root)}/api/auth/mobile/exchange'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'grant': accountGrant}),
            )
            .timeout(const Duration(seconds: 12));
        final accountJson = _decode(accountResponse.body);
        accountToken = accountJson['accessToken'] as String? ?? '';
        if (accountResponse.statusCode < 200 ||
            accountResponse.statusCode >= 300 ||
            accountToken.isEmpty) {
          throw FormatException(
            accountJson['error'] as String? ??
                'Could not connect the Agentic OS account.',
          );
        }
        owner = ((accountJson['user'] as Map?) ?? owner)
            .cast<String, dynamic>();
      }
      return MilaAccountSession(
        token: token,
        accountToken: accountToken,
        ownerId: owner['id'] as String? ?? '',
        label: label,
        ownerName: owner['name'] as String? ?? '',
        ownerEmail: owner['email'] as String? ?? '',
        ownerRole: owner['role'] as String? ?? 'Member',
      );
    } finally {
      if (shouldClose) httpClient.close();
    }
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    } catch (_) {
      return const {};
    }
  }

  static String _root(String baseUrl) {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    if (root.isEmpty) {
      throw const FormatException('MILA server URL is required.');
    }
    return root;
  }

  static String _agenticRoot(String milaRoot) {
    final uri = Uri.parse(milaRoot);
    final path = uri.path.replaceFirst(RegExp(r'/mila$'), '');
    return uri
        .replace(path: path, query: null, fragment: null)
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }
}
