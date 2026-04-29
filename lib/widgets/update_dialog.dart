import 'package:flutter/material.dart';

import '../services/update_service.dart';

enum _UpdateDialogState { idle, downloading, installing }

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

  Future<void> _onUpdateNow() async {
    if (_state != _UpdateDialogState.idle) {
      return;
    }

    setState(() {
      _state = _UpdateDialogState.downloading;
      _progress = 0;
    });

    try {
      final filePath = await UpdateService().downloadApk(
        widget.updateInfo.downloadUrl,
        (value) {
          if (!mounted) {
            return;
          }
          setState(() {
            _progress = value.clamp(0, 1);
          });
        },
      );

      _downloadedPath = filePath;
      if (!mounted) {
        return;
      }

      setState(() => _state = _UpdateDialogState.installing);
      await UpdateService().installApk(filePath);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _state = _UpdateDialogState.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
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
                      await UpdateService().installApk(path);
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
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _state == _UpdateDialogState.idle,
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
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xAA000000),
                    blurRadius: 22,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                ),
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
        if (_state == _UpdateDialogState.idle) ...[
          const SizedBox(height: 20),
          _buildButtons(context),
        ],
      ],
    );
  }

  Widget _buildProgress() {
    if (_state == _UpdateDialogState.installing) {
      return const Text(
        'Installing...',
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
    return Row(
      children: [
        Expanded(
          child: Focus(
            autofocus: true,
            onFocusChange: (focused) {
              setState(() => _updateFocused = focused);
            },
            child: GestureDetector(
              onTap: _onUpdateNow,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _updateFocused ? _accent : _accent.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _updateFocused
                      ? [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.45),
                            blurRadius: 16,
                            spreadRadius: 1.5,
                          ),
                        ]
                      : [],
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
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Focus(
            onFocusChange: (focused) {
              setState(() => _laterFocused = focused);
            },
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _laterFocused ? _accent : Colors.white.withValues(alpha: 0.35),
                    width: _laterFocused ? 2 : 1,
                  ),
                  boxShadow: _laterFocused
                      ? [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.25),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  'Later',
                  style: TextStyle(
                    color: _laterFocused ? _accent : Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
