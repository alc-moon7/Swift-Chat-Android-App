import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

enum AppUpdateCheckStatus {
  updateAvailable,
  upToDate,
  noPublishedRelease,
  unsupportedPlatform,
  failed,
}

class InstalledAppInfo {
  final String versionName;
  final String buildNumber;
  final String packageName;

  const InstalledAppInfo({
    required this.versionName,
    required this.buildNumber,
    required this.packageName,
  });

  String get displayVersion =>
      buildNumber.isNotEmpty ? 'v$versionName ($buildNumber)' : 'v$versionName';
}

class AppUpdateInfo {
  final AppUpdateCheckStatus status;
  final InstalledAppInfo? installedAppInfo;
  final String? latestVersion;
  final String? releaseName;
  final String? releaseNotes;
  final String? releaseUrl;
  final String? downloadUrl;
  final String message;

  const AppUpdateInfo({
    required this.status,
    required this.message,
    this.installedAppInfo,
    this.latestVersion,
    this.releaseName,
    this.releaseNotes,
    this.releaseUrl,
    this.downloadUrl,
  });

  bool get hasUpdate => status == AppUpdateCheckStatus.updateAvailable;
}

class AppUpdateService {
  static const String _repoOwner = 'alc-moon7';
  static const String _repoName = 'Swift-Chat-Android-App';
  static const String _releasesApiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const String _releasesPageUrl =
      'https://github.com/$_repoOwner/$_repoName/releases';
  static const MethodChannel _platformChannel = MethodChannel(
    'swift_chat/system',
  );

  static Future<InstalledAppInfo?> getInstalledAppInfo() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }

    try {
      final rawInfo = await _platformChannel.invokeMapMethod<String, dynamic>(
        'getAppVersion',
      );
      if (rawInfo == null) {
        return null;
      }

      return InstalledAppInfo(
        versionName: (rawInfo['versionName'] ?? '').toString(),
        buildNumber: (rawInfo['buildNumber'] ?? '').toString(),
        packageName: (rawInfo['packageName'] ?? '').toString(),
      );
    } catch (error) {
      debugPrint('Could not read installed app info: $error');
      return null;
    }
  }

  static Future<AppUpdateInfo> checkForUpdate() async {
    final installedAppInfo = await getInstalledAppInfo();

    if (installedAppInfo == null) {
      return const AppUpdateInfo(
        status: AppUpdateCheckStatus.unsupportedPlatform,
        message: 'GitHub update check is available on Android devices.',
      );
    }

    try {
      final response = await http.get(
        Uri.parse(_releasesApiUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Swift-Chat-Updater',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );

      if (response.statusCode == 404) {
        return AppUpdateInfo(
          status: AppUpdateCheckStatus.noPublishedRelease,
          installedAppInfo: installedAppInfo,
          message:
              'No GitHub release is published yet. Publish a release with an APK asset first.',
          releaseUrl: _releasesPageUrl,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return AppUpdateInfo(
          status: AppUpdateCheckStatus.failed,
          installedAppInfo: installedAppInfo,
          message:
              'Could not reach GitHub Releases right now. Please try again.',
          releaseUrl: _releasesPageUrl,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersion = _normalizeVersionTag(
        (data['tag_name'] ?? data['name'] ?? '').toString(),
      );
      final currentVersion = _normalizeVersionTag(installedAppInfo.versionName);
      final assets = (data['assets'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      Map<String, dynamic>? apkAsset;
      for (final asset in assets) {
        if ((asset['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
          apkAsset = asset;
          break;
        }
      }

      final releaseUrl = (data['html_url'] ?? _releasesPageUrl).toString();
      final downloadUrl = apkAsset != null
          ? (apkAsset['browser_download_url'] ?? '').toString()
          : releaseUrl;
      final comparison = _compareVersions(latestVersion, currentVersion);

      if (latestVersion.isEmpty) {
        return AppUpdateInfo(
          status: AppUpdateCheckStatus.failed,
          installedAppInfo: installedAppInfo,
          message: 'GitHub release version could not be read.',
          releaseUrl: releaseUrl,
        );
      }

      if (comparison <= 0) {
        return AppUpdateInfo(
          status: AppUpdateCheckStatus.upToDate,
          installedAppInfo: installedAppInfo,
          latestVersion: latestVersion,
          releaseName: (data['name'] ?? '').toString(),
          releaseUrl: releaseUrl,
          downloadUrl: downloadUrl,
          message: 'You are already using the latest version.',
        );
      }

      return AppUpdateInfo(
        status: AppUpdateCheckStatus.updateAvailable,
        installedAppInfo: installedAppInfo,
        latestVersion: latestVersion,
        releaseName: (data['name'] ?? '').toString(),
        releaseNotes: (data['body'] ?? '').toString(),
        releaseUrl: releaseUrl,
        downloadUrl: downloadUrl,
        message: 'A newer version is available on GitHub.',
      );
    } catch (error) {
      debugPrint('GitHub update check failed: $error');
      return AppUpdateInfo(
        status: AppUpdateCheckStatus.failed,
        installedAppInfo: installedAppInfo,
        message: 'Could not check for updates right now.',
        releaseUrl: _releasesPageUrl,
      );
    }
  }

  static Future<bool> openUpdateUrl(String url) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final didOpen = await _platformChannel.invokeMethod<bool>(
        'openUrl',
        <String, dynamic>{'url': url},
      );
      return didOpen == true;
    } catch (error) {
      debugPrint('Could not open update URL: $error');
      return false;
    }
  }

  static String normalizeReleaseNotes(String? notes) {
    final value = (notes ?? '').trim();
    if (value.isEmpty) {
      return 'New version is available to download from GitHub Releases.';
    }

    return value.length > 260 ? '${value.substring(0, 260).trim()}...' : value;
  }

  static String _normalizeVersionTag(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return '';
    }

    return normalized.toLowerCase().startsWith('v')
        ? normalized.substring(1)
        : normalized;
  }

  static int _compareVersions(String left, String right) {
    final leftParts = left
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final rightParts = right
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final maxLength =
        leftParts.length > rightParts.length ? leftParts.length : rightParts.length;

    for (var index = 0; index < maxLength; index++) {
      final leftValue = index < leftParts.length ? leftParts[index] : 0;
      final rightValue = index < rightParts.length ? rightParts[index] : 0;

      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }

    return 0;
  }
}
