import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../layout/responsive_layout.dart';
import '../models/url_item.dart';
import '../theme/clearcast_colors.dart';
import 'tv_focusable.dart';

class UrlCard extends StatefulWidget {
  final UrlItem item;
  final VoidCallback onTap;
  final bool autoFocus;

  const UrlCard({
    super.key,
    required this.item,
    required this.onTap,
    this.autoFocus = false,
  });

  @override
  State<UrlCard> createState() => _UrlCardState();
}

class _UrlCardState extends State<UrlCard> with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    if (focused) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: widget.autoFocus,
      onPressed: widget.onTap,
      onFocusChange: _onFocusChange,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isFocused
                    ? ClearCastColors.lime
                    : Colors.white.withValues(alpha: 0.1),
                width: _isFocused ? 3 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: ClearCastColors.lime.withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isFocused
                    ? [
                        ClearCastColors.surfaceMuted,
                        ClearCastColors.surface,
                      ]
                    : [
                        ClearCastColors.surface,
                        ClearCastColors.scaffoldDeep,
                      ],
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final rw = constraints.maxWidth;
                        final maxH = constraints.maxHeight;
                        if (rw <= 0 || maxH <= 0) {
                          return const SizedBox.shrink();
                        }
                        final r = ResponsiveLayout(Size(rw, maxH));
                        final thumbH = r.tileThumbDisplayHeight();
                        final iconSize = r.tileThumbIconSize();
                        return Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: rw,
                            height: thumbH,
                            child: _buildThumbnail(iconSize: iconSize),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final cw = constraints.maxWidth;
                        final ch = constraints.maxHeight;
                        if (cw <= 0 || ch <= 0) {
                          return const SizedBox.shrink();
                        }
                        final r = ResponsiveLayout(Size(cw, ch));
                        final padH = r.tileInfoPadH();
                        final padV = r.tileInfoPadV();
                        final innerW =
                            (cw - 2 * padH).clamp(0.0, double.infinity);
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            padH,
                            padV,
                            padH,
                            padV,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: innerW,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.item.title,
                                    style: TextStyle(
                                      color: _isFocused
                                          ? ClearCastColors.lime
                                          : Colors.white,
                                      fontSize: r.tileTitleSize(),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                      height: 1.15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (widget.item.description.isNotEmpty) ...[
                                    SizedBox(height: r.tileInfoGapSmall()),
                                    Text(
                                      widget.item.description,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.5),
                                        fontSize: r.tileDescSize(),
                                        height: 1.25,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  SizedBox(height: r.tileInfoGapBeforeBadge()),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal:
                                          r.tileBadgeInnerPaddingH(innerW),
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ClearCastColors.lime
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      widget.item.category.toUpperCase(),
                                      style: TextStyle(
                                        color: ClearCastColors.lime,
                                        fontSize: r.tileBadgeSize(),
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.0,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnailFallbackLabel(double iconSize) {
    final raw = widget.item.title.trim();
    final display = raw.isEmpty ? '—' : raw;
    return Container(
      color: ClearCastColors.surfaceMuted,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              display,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isFocused
                    ? ClearCastColors.lime
                    : Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
                fontSize: (iconSize * 1.35).clamp(28.0, 56.0),
                letterSpacing: 0.35,
                height: 1.05,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail({required double iconSize}) {
    final thumb = widget.item.resolvedThumbnail;
    if (thumb.isEmpty) {
      return _thumbnailFallbackLabel(iconSize);
    }

    return CachedNetworkImage(
      imageUrl: thumb,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => Container(
        color: ClearCastColors.surfaceMuted,
        child: Center(
          child: SizedBox(
            width: iconSize,
            height: iconSize,
            child: const CircularProgressIndicator(
              color: ClearCastColors.lime,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => _thumbnailFallbackLabel(iconSize),
    );
  }
}
