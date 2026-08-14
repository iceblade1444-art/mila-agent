import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/app_config.dart';
import '../storage/stores.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.updateAvailable,
    required this.updateRequired,
    required this.latestVersion,
    required this.latestCode,
    required this.apkUrl,
    required this.notes,
  });

  final bool updateAvailable;
  final bool updateRequired;
  final String latestVersion;
  final int latestCode;
  final String apkUrl;
  final String notes;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
    updateAvailable: json['updateAvailable'] as bool? ?? false,
    updateRequired: json['updateRequired'] as bool? ?? false,
    latestVersion: json['latestVersion'] as String? ?? '',
    latestCode: json['latestCode'] as int? ?? 0,
    apkUrl: json['apkUrl'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
  );
}

class UpdateService {
  const UpdateService(this._ref);

  final Ref _ref;

  Future<PackageInfo> installedPackage() => PackageInfo.fromPlatform();

  Future<AppUpdateInfo> check() async {
    final package = await installedPackage();
    final currentVersion = package.version.trim().isEmpty
        ? '0.0.0'
        : package.version.trim();
    final currentVersionCode = int.tryParse(package.buildNumber.trim()) ?? 0;
    final secure = _ref.read(secureStoreProvider);
    final baseUrl = AppConfig.configuredBackendUrl(
      await secure.read(SecureStore.milaBackendUrl),
    );
    if (baseUrl.trim().isEmpty) {
      throw const FormatException('MILA server URL is not configured.');
    }

    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse(
      '$root/v1/app/update?platform=android&version=$currentVersion&versionCode=$currentVersionCode',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw FormatException('Update check failed: ${response.statusCode}');
    }
    return AppUpdateInfo.fromJson(
      (jsonDecode(response.body) as Map).cast<String, dynamic>(),
    );
  }
}

final updateServiceProvider = Provider<UpdateService>(UpdateService.new);

final installedPackageProvider = FutureProvider<PackageInfo>(
  (ref) => ref.watch(updateServiceProvider).installedPackage(),
);
