import 'package:flutter/material.dart';

import '../layout/responsive_layout.dart';
import '../theme/clearcast_colors.dart';
import '../models/url_item.dart';
import '../services/sheets_service.dart';
import '../services/update_service.dart';
import '../widgets/url_card.dart';
import '../widgets/update_dialog.dart';
import 'webview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<UrlItem> _items = [];
  bool _loading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadUrls();
    _checkForUpdates();
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
    await Future.delayed(const Duration(seconds: 3));
    final update = await UpdateService().checkForUpdate();
    if (update != null && mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(updateInfo: update),
      );
    }
  }

  void _openWebView(UrlItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClearCastColors.scaffold,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final r = ResponsiveLayout(constraints.biggest);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(r),
              Expanded(child: _buildBody(r, constraints)),
            ],
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
          Focus(
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return GestureDetector(
                  onTap: _loadUrls,
                  child: AnimatedContainer(
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
                  Focus(
                    autofocus: true,
                    child: Builder(builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return GestureDetector(
                        onTap: _loadUrls,
                        child: Container(
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
