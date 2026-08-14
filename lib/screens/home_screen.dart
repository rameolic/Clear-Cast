import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../layout/responsive_layout.dart';
import '../theme/clearcast_colors.dart';
import '../models/url_item.dart';
import '../services/device_profile_service.dart';
import '../services/sheets_service.dart';
import '../services/update_service.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/url_card.dart';
import '../widgets/update_dialog.dart';
import 'webview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Persisted as `true` when protection is **off** (legacy key name: compatibility mode).
  static const String _protectionOffPrefsKey = 'compatibility_mode';
  static const Duration _exitWindow = Duration(seconds: 2);

  List<UrlItem> _items = [];
  bool _protectionOff = false;
  bool _loading = true;
  String? _error;
  bool _fromCache = false;
  Timer? _updateCheckTimer;
  DateTime? _lastBackAt;
  bool _checkingUpdates = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadProtectionSetting();
    _loadUrls();
    if (UpdateService.supportsAutoUpdate) {
      _updateCheckTimer = Timer(
        const Duration(seconds: 3),
        () => _checkForUpdates(manual: false),
      );
    }
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    _updateCheckTimer?.cancel();
    super.deactivate();
  }

  Future<void> _loadUrls() async {
    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
    });
    try {
      final result = await SheetsService.fetchUrls();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = result.items;
        _fromCache = result.fromCache;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
        _fromCache = false;
      });
    }
  }

  bool get _isHomeCurrent => ModalRoute.of(context)?.isCurrent == true;

  Future<void> _checkForUpdates({required bool manual}) async {
    if (!mounted || _checkingUpdates) {
      return;
    }
    if (!manual && !_isHomeCurrent) {
      return;
    }

    if (!UpdateService.supportsAutoUpdate) {
      if (!manual) {
        return;
      }
      final opened = await UpdateService.openReleasesPage();
      if (!mounted) {
        return;
      }
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the releases page.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() => _checkingUpdates = true);
    late final UpdateCheckResult result;
    try {
      result = await UpdateService().checkForUpdate(force: manual);
    } finally {
      if (mounted) {
        setState(() => _checkingUpdates = false);
      }
    }

    if (!mounted) {
      return;
    }
    if (!manual && !_isHomeCurrent) {
      return;
    }

    final update = result.update;
    if (result.hasUpdate && update != null) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(updateInfo: update),
      );
      return;
    }

    if (!manual) {
      return;
    }

    final message = switch (result.status) {
      UpdateCheckStatus.upToDate => 'You are up to date.',
      UpdateCheckStatus.rateLimited =>
        'GitHub is rate-limiting update checks. Try again in a bit.',
      UpdateCheckStatus.error =>
        result.message ?? 'Could not check for updates.',
      UpdateCheckStatus.unsupported =>
        'In-app updates are not supported on this device.',
      UpdateCheckStatus.available => 'Could not load update details.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _loadProtectionSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final off = prefs.getBool(_protectionOffPrefsKey) ?? false;
    if (!mounted) {
      return;
    }
    setState(() => _protectionOff = off);
  }

  Future<void> _setProtectionOff(bool off) async {
    setState(() => _protectionOff = off);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_protectionOffPrefsKey, off);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          off
              ? 'Protection off for new pages: no ad blocking or injected scripts. Re-open a site if one is already open.'
              : 'Protection on: blocking and safety helpers enabled for new pages.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openWebView(UrlItem item) {
    _updateCheckTimer?.cancel();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewScreen(
          item: item,
          compatibilityMode: _protectionOff,
        ),
      ),
    );
  }

  void _handleHomeBack() {
    final now = DateTime.now();
    if (_lastBackAt != null && now.difference(_lastBackAt!) < _exitWindow) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Press Back again to exit'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = DeviceProfileService.instance.isAndroidTv;
    final scaffold = Scaffold(
      backgroundColor: ClearCastColors.scaffold,
      body: TvNavigationScope(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final r = ResponsiveLayout(
              constraints.biggest,
              isTv: isTv,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(r),
                _buildProtectionRow(r),
                if (_fromCache)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      r.gridHorizontalPadding(),
                      0,
                      r.gridHorizontalPadding(),
                      (r.h * 0.01).clamp(6.0, 12.0),
                    ),
                    child: Text(
                      'Showing cached list (could not refresh from Google Sheets).',
                      style: TextStyle(
                        color: Colors.amberAccent.withValues(alpha: 0.85),
                        fontSize: r.bodyBodySize(),
                      ),
                    ),
                  ),
                Expanded(child: _buildBody(r, constraints)),
              ],
            );
          },
        ),
      ),
    );

    return PopScope(
      canPop: !isTv,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !isTv) {
          return;
        }
        _handleHomeBack();
      },
      child: isTv ? scaffold : SafeArea(top: true, child: scaffold),
    );
  }

  Widget _buildProtectionRow(ResponsiveLayout r) {
    final protectionOn = !_protectionOff;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        r.gridHorizontalPadding(),
        0,
        r.gridHorizontalPadding(),
        (r.h * 0.012).clamp(8.0, 14.0),
      ),
      child: TvFocusable(
        onPressed: () => _setProtectionOff(!_protectionOff),
        child: Material(
          color: ClearCastColors.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _setProtectionOff(!_protectionOff),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: (r.w * 0.022).clamp(12.0, 18.0),
                vertical: (r.h * 0.014).clamp(10.0, 14.0),
              ),
              child: Row(
                children: [
                  Icon(
                    protectionOn ? Icons.shield_rounded : Icons.shield_outlined,
                    color: protectionOn
                        ? ClearCastColors.lime
                        : Colors.amberAccent,
                    size: (r.shortestSide * 0.038).clamp(22.0, 30.0),
                  ),
                  SizedBox(width: (r.w * 0.018).clamp(12.0, 18.0)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          protectionOn ? 'Protection on' : 'Protection off',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: r.bodyTitleSize(),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: (r.h * 0.004).clamp(2.0, 6.0)),
                        Text(
                          protectionOn
                              ? 'Blocks ads/trackers and strips intrusive overlays. Turn off if video stalls or a site breaks.'
                              : 'Plain browsing: no request filtering or injected scripts (best for stubborn players).',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: r.bodyBodySize() * 0.92,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IgnorePointer(
                    child: Switch.adaptive(
                      value: protectionOn,
                      activeThumbColor: ClearCastColors.lime,
                      activeTrackColor:
                          ClearCastColors.lime.withValues(alpha: 0.35),
                      onChanged: (_) {},
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

  Widget _headerAction({
    required ResponsiveLayout r,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool busy = false,
    bool enabled = true,
  }) {
    final canPress = enabled && !busy;
    return TvFocusable(
      enabled: canPress,
      onPressed: canPress ? onPressed : null,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          final accent = focused
              ? ClearCastColors.lime
              : Colors.white.withValues(alpha: canPress ? 0.5 : 0.28);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: r.refreshButtonPadding(),
            decoration: BoxDecoration(
              border: Border.all(
                color: focused
                    ? ClearCastColors.lime
                    : Colors.white.withValues(alpha: 0.2),
                width: focused ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              color: focused
                  ? ClearCastColors.lime.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox(
                    width: r.refreshIconSize(),
                    height: r.refreshIconSize(),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                else
                  Icon(
                    icon,
                    color: accent,
                    size: r.refreshIconSize(),
                  ),
                SizedBox(width: (r.w * 0.005).clamp(6.0, 12.0)),
                Text(
                  busy ? 'Checking...' : label,
                  style: TextStyle(
                    color: accent,
                    fontSize: r.refreshLabelSize(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(ResponsiveLayout r) {
    final logo = r.headerLogoBox();
    final logoW = (logo * 2.85).clamp(logo * 1.9, r.w * 0.38);
    return Container(
      padding: r.headerPadding(),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ClearCastColors.surface,
            ClearCastColors.scaffold.withValues(alpha: 0),
          ],
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: r.w - r.headerPadding().horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: logo * 1.2,
                width: logoW,
                child: Image.asset(
                  'assets/branding/clearcast_logo.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  semanticLabel: 'ClearCast logo',
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.cast_connected_rounded,
                    color: ClearCastColors.lime,
                    size: logo,
                  ),
                ),
              ),
              SizedBox(width: (r.w * 0.012).clamp(10.0, 20.0)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) =>
                          ClearCastColors.brandGradient.createShader(bounds),
                      child: Text(
                        'ClearCast',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: r.headerTitleSize(),
                          fontWeight: FontWeight.w900,
                          letterSpacing: r.headerTitleLetterSpacing(),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'Your curated web experience',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: r.headerSubtitleSize(),
                        letterSpacing: 0.5,
                      ),
                      maxLines: r.isCompactWidth ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _headerAction(
                r: r,
                icon: Icons.refresh_rounded,
                label: 'Refresh',
                onPressed: _loadUrls,
              ),
              SizedBox(width: (r.w * 0.008).clamp(8.0, 14.0)),
              _headerAction(
                r: r,
                icon: Icons.system_update_rounded,
                label: 'Update',
                busy: _checkingUpdates,
                enabled: !_checkingUpdates,
                onPressed: () => _checkForUpdates(manual: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ResponsiveLayout r, BoxConstraints outerConstraints) {
    if (_loading) {
      return Padding(
        padding: r.centeredHorizontalPadding(),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: (r.shortestSide * 0.09).clamp(28.0, 44.0),
                height: (r.shortestSide * 0.09).clamp(28.0, 44.0),
                child: const CircularProgressIndicator(
                  color: ClearCastColors.lime,
                  strokeWidth: 2,
                ),
              ),
              SizedBox(height: r.bodyGapLarge()),
              Text(
                'Loading from Google Sheets...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: r.bodyBodySize(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: r.centeredHorizontalPadding(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: r.centeredContentMaxWidth()),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    color: Colors.white.withValues(alpha: 0.2),
                    size: r.bodyIconLarge(),
                  ),
                  SizedBox(height: r.bodyGapSmall()),
                  Text(
                    'Could not load URLs',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: r.bodyTitleSize(),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: r.bodyGapSmall()),
                  Text(
                    'Make sure your Google Sheet ID is correct\n'
                    'and the sheet is published publicly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: r.bodyBodySize(),
                      height: 1.6,
                    ),
                  ),
                  SizedBox(height: r.bodyGapLarge()),
                  TvFocusable(
                    autofocus: true,
                    onPressed: _loadUrls,
                    child: Builder(builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return Container(
                        padding: r.retryButtonPadding(),
                        decoration: BoxDecoration(
                          color: focused
                              ? ClearCastColors.lime
                              : ClearCastColors.lime.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: ClearCastColors.lime,
                            width: focused ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          'Try Again',
                          style: TextStyle(
                            color: focused
                                ? ClearCastColors.onLime
                                : ClearCastColors.lime,
                            fontWeight: FontWeight.w700,
                            fontSize: r.retryLabelSize(),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Padding(
        padding: r.centeredHorizontalPadding(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: r.centeredContentMaxWidth()),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_rounded,
                  color: Colors.white.withValues(alpha: 0.2),
                  size: r.bodyIconLarge(),
                ),
                SizedBox(height: r.bodyGapSmall()),
                Text(
                  'No URLs found in your sheet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: r.bodyBodySize(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final spacing = r.gridSpacing();
    final hPad = r.gridHorizontalPadding();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: GridView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(bottom: r.gridBottomPadding()),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: r.gridMaxCrossAxisExtent(),
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: ResponsiveLayout.gridAspectRatio,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          return UrlCard(
            key: ValueKey(_items[index].url),
            item: _items[index],
            autoFocus: index == 0,
            onTap: () => _openWebView(_items[index]),
          );
        },
      ),
    );
  }
}
