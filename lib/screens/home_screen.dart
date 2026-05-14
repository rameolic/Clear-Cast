import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  List<UrlItem> _items = [];
  String _searchQuery = '';
  bool _protectionOff = false;
  bool _loading = true;
  String? _error;
  Timer? _updateCheckTimer;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadProtectionSetting();
    _loadUrls();
    if (defaultTargetPlatform == TargetPlatform.android) {
      _updateCheckTimer = Timer(
        const Duration(seconds: 3),
        () => _checkForUpdates(),
      );
    }
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadUrls() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await SheetsService.fetchUrls();
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    if (!mounted || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final update = await UpdateService().checkForUpdate();
    if (update != null && mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(updateInfo: update),
      );
    }
  }

  Future<void> _loadProtectionSetting() async {
    final prefs = await SharedPreferences.getInstance();
    // Enforce Shield ON at every app launch.
    const off = false;
    await prefs.setBool(_protectionOffPrefsKey, off);
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewScreen(
          item: item,
          compatibilityMode: _protectionOff,
        ),
      ),
    );
  }

  List<UrlItem> get _filteredItems {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _items;
    }
    return _items.where((item) {
      return item.title.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query) ||
          item.url.toLowerCase().contains(query);
    }).toList();
  }

  void _focusSearch() {
    if (!_searchFocusNode.hasFocus) {
      _searchFocusNode.requestFocus();
    }
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  void _clearOrUnfocusSearch() {
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      setState(() => _searchQuery = '');
      return;
    }
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = DeviceProfileService.instance.isAndroidTv;
    return PopScope(
      canPop: !isTv,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !isTv) {
          return;
        }
        SystemNavigator.pop();
      },
      child: SafeArea(
        top: true,
        child: Scaffold(
          backgroundColor: ClearCastColors.scaffold,
          body: TvNavigationScope(
            child: Shortcuts(
              shortcuts: <ShortcutActivator, Intent>{
                const SingleActivator(LogicalKeyboardKey.slash):
                    const _FocusSearchIntent(),
                const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                    const _FocusSearchIntent(),
                const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                    const _FocusSearchIntent(),
                const SingleActivator(LogicalKeyboardKey.escape):
                    const _ClearOrUnfocusSearchIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
                    onInvoke: (intent) {
                      _focusSearch();
                      return null;
                    },
                  ),
                  _ClearOrUnfocusSearchIntent:
                      CallbackAction<_ClearOrUnfocusSearchIntent>(
                    onInvoke: (intent) {
                      _clearOrUnfocusSearch();
                      return null;
                    },
                  ),
                },
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
                        _buildSearchBar(r, isTv),
                        _buildProtectionRow(r),
                        Expanded(child: _buildBody(r, constraints)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
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
                  Switch.adaptive(
                    value: protectionOn,
                    activeThumbColor: ClearCastColors.lime,
                    activeTrackColor:
                        ClearCastColors.lime.withValues(alpha: 0.35),
                    onChanged: (on) => _setProtectionOff(!on),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(ResponsiveLayout r, bool isTv) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        r.gridHorizontalPadding(),
        0,
        r.gridHorizontalPadding(),
        (r.h * 0.012).clamp(8.0, 14.0),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: ClearCastColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _searchFocusNode.hasFocus
                ? ClearCastColors.lime
                : Colors.white.withValues(alpha: 0.14),
            width: _searchFocusNode.hasFocus ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: _searchFocusNode.hasFocus
                  ? ClearCastColors.lime
                  : Colors.white.withValues(alpha: 0.6),
              size: (r.shortestSide * 0.028).clamp(18.0, 24.0),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: r.bodyBodySize(),
                ),
                cursorColor: ClearCastColors.lime,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: isTv
                      ? 'Search sites... (Select to type)'
                      : 'Search sites...  (/ or Ctrl/Cmd+F to focus, Esc to clear)',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: r.bodyBodySize(),
                  ),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              IconButton(
                onPressed: _clearOrUnfocusSearch,
                icon: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                tooltip: 'Clear search',
              ),
          ],
        ),
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
          TvFocusable(
            onPressed: () => _setProtectionOff(!_protectionOff),
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                final protectionOn = !_protectionOff;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: r.refreshButtonPadding(),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: focused || _protectionOff
                          ? Colors.amberAccent
                          : Colors.white.withValues(alpha: 0.2),
                      width: focused ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _protectionOff
                        ? Colors.amberAccent.withValues(alpha: 0.12)
                        : Colors.transparent,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        protectionOn
                            ? Icons.shield_rounded
                            : Icons.shield_outlined,
                        color: focused || _protectionOff
                            ? Colors.amberAccent
                            : Colors.white.withValues(alpha: 0.5),
                        size: r.refreshIconSize(),
                      ),
                      SizedBox(width: (r.w * 0.005).clamp(6.0, 12.0)),
                      Text(
                        protectionOn ? 'Shield on' : 'Shield off',
                        style: TextStyle(
                          color: focused || _protectionOff
                              ? Colors.amberAccent
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: r.refreshLabelSize(),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(width: (r.w * 0.008).clamp(8.0, 14.0)),
          TvFocusable(
            onPressed: _loadUrls,
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
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
                      Icon(
                        Icons.refresh_rounded,
                        color: focused
                            ? ClearCastColors.lime
                            : Colors.white.withValues(alpha: 0.5),
                        size: r.refreshIconSize(),
                      ),
                      SizedBox(width: (r.w * 0.005).clamp(6.0, 12.0)),
                      Text(
                        'Refresh',
                        style: TextStyle(
                          color: focused
                              ? ClearCastColors.lime
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: r.refreshLabelSize(),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
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

    final visibleItems = _filteredItems;
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
    if (visibleItems.isEmpty) {
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
                  Icons.search_off_rounded,
                  color: Colors.white.withValues(alpha: 0.22),
                  size: r.bodyIconLarge(),
                ),
                SizedBox(height: r.bodyGapSmall()),
                Text(
                  'No matches for "${_searchQuery.trim()}"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
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
        itemCount: visibleItems.length,
        itemBuilder: (context, index) {
          return UrlCard(
            key: ValueKey(visibleItems[index].url),
            item: visibleItems[index],
            autoFocus: index == 0,
            onTap: () => _openWebView(visibleItems[index]),
          );
        },
      ),
    );
  }
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _ClearOrUnfocusSearchIntent extends Intent {
  const _ClearOrUnfocusSearchIntent();
}
