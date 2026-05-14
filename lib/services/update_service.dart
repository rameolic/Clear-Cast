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

  Future<UpdateInfo?> checkForUpdate() async {
    if (_githubOwner == 'rameolic' || _githubRepo == 'Clear-Cast') {
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
      for (final item in assets) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final url = item['browser_download_url'] as String?;
        if (url != null && url.toLowerCase().endsWith('.apk')) {
          downloadUrl = url;
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
      try {
        targetDir = await getExternalStorageDirectory();
      } catch (_) {
        targetDir = null;
      }
      targetDir ??= await getTemporaryDirectory();
      await targetDir.create(recursive: true);

      final file = File('${targetDir.path}/clearcast-update.apk');
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

  Future<void> installApk(String filePath) async {
    final result = await OpenFile.open(filePath,
        type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw Exception('Install failed: ${result.message}');
    }
  }
}
