import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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

enum UpdateCheckStatus {
  available,
  upToDate,
  rateLimited,
  error,
  unsupported,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final UpdateInfo? update;
  final String? message;

  const UpdateCheckResult._(this.status, {this.update, this.message});

  factory UpdateCheckResult.available(UpdateInfo update) =>
      UpdateCheckResult._(UpdateCheckStatus.available, update: update);

  factory UpdateCheckResult.upToDate() =>
      const UpdateCheckResult._(UpdateCheckStatus.upToDate);

  factory UpdateCheckResult.rateLimited() =>
      const UpdateCheckResult._(UpdateCheckStatus.rateLimited);

  factory UpdateCheckResult.error(String message) =>
      UpdateCheckResult._(UpdateCheckStatus.error, message: message);

  factory UpdateCheckResult.unsupported() =>
      const UpdateCheckResult._(UpdateCheckStatus.unsupported);

  bool get hasUpdate =>
      status == UpdateCheckStatus.available && update != null;
}

class UpdateCancelledException implements Exception {
  const UpdateCancelledException();

  @override
  String toString() => 'Update cancelled';
}

class InstallPermissionException implements Exception {
  final String message;
  const InstallPermissionException(this.message);

  @override
  String toString() => message;
}

class UpdateCancelToken {
  bool _cancelled = false;
  void Function()? _abort;

  bool get isCancelled => _cancelled;

  void bindAbort(void Function() abort) {
    _abort = abort;
    if (_cancelled) {
      abort();
    }
  }

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _abort?.call();
  }
}

class UpdateService {
  static const String _githubOwner = 'rameolic';
  static const String _githubRepo = 'Clear-Cast';
  static const String _lastCheckKey = 'last_update_check';
  static const String _rateLimitedUntilKey = 'update_rate_limited_until';
  static const Duration _checkCooldown = Duration(minutes: 30);
  static const Duration _rateLimitCooldown = Duration(hours: 1);
  static const Duration _downloadConnectTimeout = Duration(seconds: 30);
  static const Duration _downloadIdleTimeout = Duration(seconds: 30);
  static const Duration _downloadOverallTimeout = Duration(minutes: 10);

  UpdateService._internal();
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;

  static const MethodChannel _installChannel =
      MethodChannel('com.rameolic.clearcast/device');

  static Uri get latestReleasesPageUrl => Uri.parse(
        'https://github.com/$_githubOwner/$_githubRepo/releases/latest',
      );

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

  static Map<String, String> get _githubHeaders => const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'ClearCast-UpdateCheck',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// GitHub latest releases page (not a guessed next tag).
  static Uri releasePageUrlForVersion(String version) {
    final tag = version.startsWith('v') ? version : 'v$version';
    return Uri.parse(
      'https://github.com/$_githubOwner/$_githubRepo/releases/tag/$tag',
    );
  }

  static Future<Uri> nextReleasePageUrl() async {
    return latestReleasesPageUrl;
  }

  static Future<bool> openReleasesPage() async {
    return launchUrl(
      latestReleasesPageUrl,
      mode: LaunchMode.externalApplication,
    );
  }

  static Future<bool> canInstallPackages() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }
    try {
      final ok = await _installChannel.invokeMethod<bool>('canInstallPackages');
      return ok ?? true;
    } catch (e) {
      debugPrint('UpdateService: canInstallPackages failed: $e');
      return true;
    }
  }

  static Future<void> openInstallPermissionSettings() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    await _installChannel.invokeMethod<void>('openInstallPermissionSettings');
  }

  Future<UpdateCheckResult> checkForUpdate({bool force = false}) async {
    if (!supportsAutoUpdate) {
      return UpdateCheckResult.unsupported();
    }
    if (_githubOwner == 'YOUR_GITHUB_USERNAME' ||
        _githubRepo == 'YOUR_REPO_NAME') {
      debugPrint('UpdateService: GitHub owner/repo not configured.');
      return UpdateCheckResult.error('Update source is not configured.');
    }

    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rateLimitedUntil = prefs.getInt(_rateLimitedUntilKey) ?? 0;
    if (rateLimitedUntil > nowMs) {
      return UpdateCheckResult.rateLimited();
    }
    final lastCheckMs = prefs.getInt(_lastCheckKey);
    if (!force &&
        lastCheckMs != null &&
        nowMs - lastCheckMs < _checkCooldown.inMilliseconds) {
      return UpdateCheckResult.upToDate();
    }

    final uri = Uri.parse(
      'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest',
    );

    Future<void> markChecked() => prefs.setInt(_lastCheckKey, nowMs);

    try {
      final response = await http
          .get(uri, headers: _githubHeaders)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 403) {
        await prefs.setInt(
          _rateLimitedUntilKey,
          DateTime.now().add(_rateLimitCooldown).millisecondsSinceEpoch,
        );
        debugPrint('UpdateService: GitHub API rate limited (403).');
        return UpdateCheckResult.rateLimited();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'UpdateService: release check failed with ${response.statusCode}.',
        );
        await markChecked();
        return UpdateCheckResult.error(
          'Could not reach GitHub (HTTP ${response.statusCode}).',
        );
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        await markChecked();
        return UpdateCheckResult.error('Unexpected response from GitHub.');
      }

      final tagName = (decoded['tag_name'] as String? ?? '').trim();
      if (tagName.isEmpty) {
        await markChecked();
        return UpdateCheckResult.error('Latest release has no version tag.');
      }

      final versionOnly = tagName.replaceFirst(RegExp(r'^v'), '');
      final remoteVersionStr = versionOnly.split('+').first.trim();
      if (remoteVersionStr.isEmpty) {
        await markChecked();
        return UpdateCheckResult.error('Latest release tag is empty.');
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final localVersionStr = packageInfo.version.trim();
      if (localVersionStr.isEmpty) {
        await markChecked();
        return UpdateCheckResult.error('Could not read the installed version.');
      }

      final Version remoteVersion;
      final Version localVersion;
      try {
        remoteVersion = Version.parse(remoteVersionStr);
        localVersion = Version.parse(localVersionStr);
      } on FormatException catch (e) {
        await markChecked();
        return UpdateCheckResult.error('Could not compare versions: $e');
      }

      await markChecked();
      if (remoteVersion <= localVersion) {
        return UpdateCheckResult.upToDate();
      }

      final assets = decoded['assets'];
      if (assets is! List || assets.isEmpty) {
        debugPrint('UpdateService: latest release has no assets.');
        return UpdateCheckResult.error(
          'Version $remoteVersionStr is available, but no installer was attached.',
        );
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
      if (downloadUrl == null || downloadUrl.isEmpty) {
        debugPrint('UpdateService: latest release has no matching installer.');
        return UpdateCheckResult.error(
          'Version $remoteVersionStr is available, but no installer was found for this device.',
        );
      }

      final releaseNotes = (decoded['body'] as String? ?? '').trim();
      return UpdateCheckResult.available(
        UpdateInfo(
          version: remoteVersionStr,
          downloadUrl: downloadUrl,
          releaseNotes: releaseNotes,
          tagName: tagName,
        ),
      );
    } on TimeoutException catch (e) {
      debugPrint('UpdateService: timed out while checking updates: $e');
      await markChecked();
      return UpdateCheckResult.error(
        'Timed out while checking for updates. Try again.',
      );
    } catch (e) {
      debugPrint('UpdateService: failed to check updates: $e');
      await markChecked();
      return UpdateCheckResult.error('Could not check for updates: $e');
    }
  }

  Future<String> downloadUpdate(
    String url,
    void Function(double progress) onProgress, {
    UpdateCancelToken? cancelToken,
  }) async {
    return downloadApk(url, onProgress, cancelToken: cancelToken);
  }

  Future<String> downloadApk(
    String url,
    void Function(double progress) onProgress, {
    UpdateCancelToken? cancelToken,
  }) async {
    final client = http.Client();
    cancelToken?.bindAbort(client.close);

    void throwIfCancelled() {
      if (cancelToken?.isCancelled == true) {
        throw const UpdateCancelledException();
      }
    }

    try {
      throwIfCancelled();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client
          .send(request)
          .timeout(_downloadConnectTimeout);
      throwIfCancelled();
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

      IOSink? sink;
      try {
        final writer = file.openWrite();
        sink = writer;
        final total = response.contentLength ?? 0;
        int received = 0;
        onProgress(0);

        await response.stream.timeout(_downloadIdleTimeout).forEach((chunk) {
          throwIfCancelled();
          received += chunk.length;
          writer.add(chunk);
          if (total > 0) {
            onProgress(received / total);
          }
        }).timeout(_downloadOverallTimeout);

        await writer.flush();
        await writer.close();
        sink = null;
        throwIfCancelled();
        if (total == 0) {
          onProgress(1);
        }
        return file.path;
      } catch (e) {
        try {
          await sink?.close();
        } catch (_) {}
        if (await file.exists()) {
          await file.delete();
        }
        if (cancelToken?.isCancelled == true || e is UpdateCancelledException) {
          throw const UpdateCancelledException();
        }
        if (e is TimeoutException) {
          throw TimeoutException('Download timed out.');
        }
        rethrow;
      }
    } on UpdateCancelledException {
      rethrow;
    } on TimeoutException {
      throw TimeoutException('Download timed out.');
    } catch (e) {
      if (cancelToken?.isCancelled == true) {
        throw const UpdateCancelledException();
      }
      rethrow;
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
    if (Platform.isAndroid) {
      final allowed = await canInstallPackages();
      if (!allowed) {
        try {
          await openInstallPermissionSettings();
        } catch (e) {
          debugPrint('UpdateService: could not open install settings: $e');
        }
        throw const InstallPermissionException(
          'Allow installing unknown apps for ClearCast, then tap Update Now again.',
        );
      }
      try {
        final ok = await _installChannel.invokeMethod<bool>(
          'installApk',
          {'path': filePath},
        );
        if (ok == true) {
          return;
        }
      } on PlatformException catch (e) {
        if (e.code == 'INSTALL_PERMISSION') {
          try {
            await openInstallPermissionSettings();
          } catch (_) {}
          throw InstallPermissionException(
            e.message ??
                'Allow installing unknown apps for ClearCast, then tap Update Now again.',
          );
        }
        debugPrint('UpdateService: native install intent failed: $e');
      } catch (e) {
        debugPrint('UpdateService: native install intent failed: $e');
      }
    }
    final result = await OpenFile.open(filePath,
        type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw Exception('Install failed: ${result.message}');
    }
  }
}
