import 'dart:io';

import 'package:flutter/material.dart';

import '../services/update_service.dart';
import 'tv_focusable.dart';

enum _UpdateDialogState { idle, downloading, installing, opened }

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  State<UpdateDialog> createState() => _UpdateDialogStateState();
}

class _UpdateDialogStateState extends State<UpdateDialog> {
  static const Color _overlay = Color(0xF2080E1A);
  static const Color _card = Color(0xFF0D1B2E);
  static const Color _border = Color(0xFF1A2744);
  static const Color _accent = Color(0xFF00E5FF);

  _UpdateDialogState _state = _UpdateDialogState.idle;
  double _progress = 0;
  bool _updateFocused = false;
  bool _laterFocused = false;
  String? _downloadedPath;
  UpdateCancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _onUpdateNow() async {
    if (_state != _UpdateDialogState.idle) {
      return;
    }

    if (Platform.isAndroid) {
      final allowed = await UpdateService.canInstallPackages();
      if (!allowed) {
        try {
          await UpdateService.openInstallPermissionSettings();
        } catch (_) {}
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Allow installing unknown apps for ClearCast, then tap Update Now again.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
    }

    final cancelToken = UpdateCancelToken();
    _cancelToken = cancelToken;

    setState(() {
      _state = _UpdateDialogState.downloading;
      _progress = 0;
    });

    try {
      final filePath = await UpdateService().downloadUpdate(
        widget.updateInfo.downloadUrl,
        (value) {
          if (!mounted) {
            return;
          }
          setState(() {
            _progress = value.clamp(0, 1);
          });
        },
        cancelToken: cancelToken,
      );

      if (cancelToken.isCancelled || !mounted) {
        return;
      }

      _downloadedPath = filePath;
      setState(() => _state = _UpdateDialogState.installing);
      await UpdateService().installUpdate(filePath);
      if (!mounted) {
        return;
      }
      setState(() => _state = _UpdateDialogState.opened);
    } on UpdateCancelledException {
      if (!mounted) {
        return;
      }
      setState(() => _state = _UpdateDialogState.idle);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _state = _UpdateDialogState.idle);
      final message = e is InstallPermissionException
          ? e.message
          : 'Update failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: _downloadedPath == null
              ? null
              : SnackBarAction(
                  label: 'Retry install',
                  onPressed: () async {
                    final path = _downloadedPath;
                    if (path == null) {
                      return;
                    }
                    try {
                      await UpdateService().installUpdate(path);
                    } catch (installErr) {
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Install failed: $installErr')),
                      );
                    }
                  },
                ),
        ),
      );
    }
  }

  void _onCancelDownload() {
    _cancelToken?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (_state == _UpdateDialogState.downloading) {
          _cancelToken?.cancel();
        }
      },
      child: Material(
        color: _overlay,
        child: SizedBox.expand(
          child: Center(
            child: Container(
              width: 760,
              margin: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildContent(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Update Available',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.updateInfo.tagName,
            style: const TextStyle(
              color: _accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: SingleChildScrollView(
            child: Text(
              widget.updateInfo.releaseNotes.isEmpty
                  ? 'A new version is ready to install.'
                  : widget.updateInfo.releaseNotes,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ),
        if (_state != _UpdateDialogState.idle) ...[
          const SizedBox(height: 18),
          _buildProgress(),
        ],
        if (_state != _UpdateDialogState.installing) ...[
          const SizedBox(height: 20),
          _buildButtons(context),
        ],
      ],
    );
  }

  Widget _buildProgress() {
    if (_state == _UpdateDialogState.installing) {
      return const Text(
        'Opening installer...',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    if (_state == _UpdateDialogState.opened) {
      return const Text(
        'Installer opened. Use Back to dismiss this dialog.',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: _progress <= 0 ? null : _progress,
          minHeight: 8,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          valueColor: const AlwaysStoppedAnimation<Color>(_accent),
        ),
        const SizedBox(height: 8),
        Text(
          _progress <= 0
              ? 'Preparing download...'
              : '${(_progress * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildButtons(BuildContext context) {
    if (_state == _UpdateDialogState.downloading) {
      return TvFocusable(
        autofocus: true,
        onPressed: _onCancelDownload,
        onFocusChange: (focused) {
          setState(() => _laterFocused = focused);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _laterFocused
                  ? _accent
                  : Colors.white.withValues(alpha: 0.35),
              width: _laterFocused ? 2 : 1,
            ),
          ),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: _laterFocused
                  ? _accent
                  : Colors.white.withValues(alpha: 0.85),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    final dismissLabel =
        _state == _UpdateDialogState.opened ? 'Close' : 'Later';
    return Row(
      children: [
        if (_state == _UpdateDialogState.idle)
          Expanded(
            child: TvFocusable(
              autofocus: true,
              onPressed: _onUpdateNow,
              onFocusChange: (focused) {
                setState(() => _updateFocused = focused);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      _updateFocused ? _accent : _accent.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Update Now',
                  style: TextStyle(
                    color: Color(0xFF052028),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        if (_state == _UpdateDialogState.idle) const SizedBox(width: 12),
        Expanded(
          child: TvFocusable(
            autofocus: _state == _UpdateDialogState.opened,
            onPressed: () => Navigator.of(context).pop(),
            onFocusChange: (focused) {
              setState(() => _laterFocused = focused);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _laterFocused
                      ? _accent
                      : Colors.white.withValues(alpha: 0.35),
                  width: _laterFocused ? 2 : 1,
                ),
              ),
              child: Text(
                dismissLabel,
                style: TextStyle(
                  color: _laterFocused
                      ? _accent
                      : Colors.white.withValues(alpha: 0.85),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
