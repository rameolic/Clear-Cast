import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_profile_service.dart';

/// Focusable control for TV remotes: D-pad focus ring + Enter/Select activation.
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final void Function(bool)? onFocusChange;
  final bool scrollIntoView;
  final bool enabled;

  const TvFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
    this.scrollIntoView = true,
    this.enabled = true,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _node;
  bool _ownsNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _node = widget.focusNode!;
    } else {
      _node = FocusNode();
      _ownsNode = true;
    }
    _node.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _node.removeListener(_handleFocusChanged);
    if (_ownsNode) {
      _node.dispose();
    }
    super.dispose();
  }

  void _handleFocusChanged() {
    widget.onFocusChange?.call(_node.hasFocus);
    if (_node.hasFocus && widget.scrollIntoView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_node.hasFocus) {
          return;
        }
        Scrollable.ensureVisible(
          context,
          alignment: 0.3,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled || widget.onPressed == null) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (TvActivationKeys.isActivationKey(event.logicalKey)) {
      widget.onPressed!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      skipTraversal: !widget.enabled,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}

/// Keys that activate focused TV controls (remote center / keyboard).
class TvActivationKeys {
  static bool isActivationKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
  }
}

/// Wraps a subtree with TV-friendly traversal when on Android TV.
class TvNavigationScope extends StatelessWidget {
  final Widget child;

  const TvNavigationScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!DeviceProfileService.instance.prefersDpadNavigation) {
      return child;
    }
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: child,
    );
  }
}
