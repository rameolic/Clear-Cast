import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final String tagName;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.tagName,
  });
}

class UpdateService {
  static const String _githubOwner = 'rameolic';
  static const String _githubRepo = 'Clear-Cast';
  static const String _lastCheckKey = 'last_update_check';
  static const Duration _checkCooldown = Duration(minutes: 30);
  static const Duration _rateLimitCooldown = Duration(hours: 1);

  UpdateService._internal();
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;

  static bool get supportsAutoUpdate {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isMacOS;
  }

  static List<String> get _preferredAssetExtensions {
    if (Platform.isMacOS) {
      return const ['.dmg', '.zip', '.pkg'];
    }
    if (Platform.isAndroid) {
      return const ['.apk'];
    }
    return const [];
  }

  static String get _defaultDownloadBasename {
    if (Platform.isMacOS) {
      return 'clearcast-update.dmg';
    }
    return 'clearcast-update.apk';
  }

  /// GitHub releases page for the version after [currentVersion].
  ///
  /// Encodes `major.minor.patch` as a three-digit number (e.g. 1.0.2 → 102),
  /// adds one, then decodes (102 → 1.0.3, 109 → 1.1.0).
  static String nextReleaseVersion(String currentVersion) {
    final versionOnly = currentVersion.split('+').first.trim();
    final parts = versionOnly.split('.');
    if (parts.length == 3) {
      final nums = parts.map(int.tryParse).toList();
      if (nums.every((n) => n != null && n >= 0 && n <= 9)) {
        final encoded = nums[0]! * 100 + nums[1]! * 10 + nums[2]!;
        final next = encoded + 1;
        return '${next ~/ 100}.${(next ~/ 10) % 10}.${next % 10}';
      }
    }
    return Version.parse(versionOnly).nextPatch.toString();
  }

  static Uri releasePageUrlForVersion(String version) {
    final tag = version.startsWith('v') ? version : 'v$version';
    return Uri.parse(
      'https://github.com/$_githubOwner/$_githubRepo/releases/tag/$tag',
    );
  }

  static Future<Uri> nextReleasePageUrl() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final next = nextReleaseVersion(packageInfo.version);
    return releasePageUrlForVersion(next);
  }

  Future<UpdateInfo?> checkForUpdate() async {
    if (!supportsAutoUpdate) {
      return null;
    }
    if (_githubOwner == 'YOUR_GITHUB_USERNAME' ||
        _githubRepo == 'YOUR_REPO_NAME') {
      debugPrint('UpdateService: GitHub owner/repo not configured.');
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastCheckMs = prefs.getInt(_lastCheckKey);
    if (lastCheckMs != null &&
        nowMs - lastCheckMs < _checkCooldown.inMilliseconds) {
      return null;
    }

    final uri = Uri.parse(
      'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 403) {
        await prefs.setInt(
          _lastCheckKey,
          DateTime.now().add(_rateLimitCooldown).millisecondsSinceEpoch,
        );
        debugPrint('UpdateService: GitHub API rate limited (403).');
        return null;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'UpdateService: release check failed with ${response.statusCode}.',
        );
        await prefs.setInt(_lastCheckKey, nowMs);
        return null;
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        await prefs.setInt(_lastCheckKey, nowMs);
        return null;
      }

      final tagName = (decoded['tag_name'] as String? ?? '').trim();
      if (tagName.isEmpty) {
        await prefs.setInt(_lastCheckKey, nowMs);
        return null;
      }

      final versionOnly = tagName.replaceFirst(RegExp(r'^v'), '');
      final remoteVersionStr = versionOnly.split('+').first.trim();
      if (remoteVersionStr.isEmpty) {
        await prefs.setInt(_lastCheckKey, nowMs);
        return null;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final localVersionStr = packageInfo.version.trim();
      if (localVersionStr.isEmpty) {
        await prefs.setInt(_lastCheckKey, nowMs);
        return null;
      }

      final remoteVersion = Version.parse(remoteVersionStr);
      final localVersion = Version.parse(localVersionStr);
      await prefs.setInt(_lastCheckKey, nowMs);
      if (remoteVersion <= localVersion) {
        return null;
      }

      final assets = decoded['assets'];
      if (assets is! List || assets.isEmpty) {
        debugPrint('UpdateService: latest release has no assets.');
        return null;
      }

      String? downloadUrl;
      final extensions = _preferredAssetExtensions;
      for (final ext in extensions) {
        for (final item in assets) {
          if (item is! Map<String, dynamic>) {
            continue;
          }
          final url = item['browser_download_url'] as String?;
          if (url != null && url.toLowerCase().endsWith(ext)) {
            downloadUrl = url;
            break;
          }
        }
        if (downloadUrl != null) {
          break;
        }
      }
      downloadUrl ??= (assets.first
          as Map<String, dynamic>)['browser_download_url'] as String?;
      if (downloadUrl == null || downloadUrl.isEmpty) {
        return null;
      }

      final releaseNotes = (decoded['body'] as String? ?? '').trim();
      return UpdateInfo(
        version: remoteVersionStr,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        tagName: tagName,
      );
    } on TimeoutException catch (e) {
      debugPrint('UpdateService: timed out while checking updates: $e');
      await prefs.setInt(_lastCheckKey, nowMs);
      return null;
    } catch (e) {
      debugPrint('UpdateService: failed to check updates: $e');
      await prefs.setInt(_lastCheckKey, nowMs);
      return null;
    }
  }

  Future<String> downloadUpdate(
    String url,
    void Function(double progress) onProgress,
  ) async {
    return downloadApk(url, onProgress);
  }

  Future<String> downloadApk(
    String url,
    void Function(double progress) onProgress,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Download failed with status ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      Directory? targetDir;
      if (Platform.isAndroid) {
        try {
          targetDir = await getExternalStorageDirectory();
        } catch (_) {
          targetDir = null;
        }
      }
      targetDir ??= await getDownloadsDirectory();
      targetDir ??= await getTemporaryDirectory();
      await targetDir.create(recursive: true);

      final fileName = _downloadFileNameForUrl(url);
      final file = File('${targetDir.path}/$fileName');
      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();
      final total = response.contentLength ?? 0;
      int received = 0;
      onProgress(0);

      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          onProgress(received / total);
        }
      }

      await sink.flush();
      await sink.close();
      if (total == 0) {
        onProgress(1);
      }
      return file.path;
    } finally {
      client.close();
    }
  }

  static String _downloadFileNameForUrl(String url) {
    final uri = Uri.tryParse(url);
    final segment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    if (segment.isNotEmpty && segment.contains('.')) {
      return segment;
    }
    return _defaultDownloadBasename;
  }

  Future<void> installUpdate(String filePath) async {
    return installApk(filePath);
  }

  Future<void> installApk(String filePath) async {
    if (Platform.isMacOS) {
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        throw Exception('Could not open installer: ${result.message}');
      }
      return;
    }
    final result = await OpenFile.open(filePath,
        type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw Exception('Install failed: ${result.message}');
    }
  }
}
