import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/url_item.dart';
import 'logger_service.dart';

class SheetsLoadResult {
  final List<UrlItem> items;
  final bool fromCache;

  const SheetsLoadResult({required this.items, this.fromCache = false});
}

class SheetsService {
  /// ─────────────────────────────────────────────────────────────────────────
  /// HOW TO SET UP YOUR GOOGLE SHEET:
  ///
  ///  1. Create a Google Sheet with these columns (row 1 = headers):
  ///       A: title | B: url | C: thumbnailUrl | D: category | E: description | F: allowed
  ///
  ///     `allowed` is optional JSON array of extra redirect bases, e.g.
  ///     ["https://what-is-reviews.blogspot.com/"]
  ///
  ///  2. Publish it to the web:
  ///       File → Share → Publish to web → Sheet1 → CSV → Publish
  ///
  ///  3. Use your published sheet key from URL:
  ///       https://docs.google.com/spreadsheets/d/e/PUBLISHED_SHEET_KEY/pubhtml
  ///
  ///  4. Configure values with --dart-define (optional):
  ///       --dart-define=SHEETS_PUBLISHED_SHEET_KEY=your_published_sheet_key
  ///       --dart-define=SHEETS_GID=0
  ///
  ///  Example sheet row:
  ///    YouTube | https://youtube.com | https://i.imgur.com/xyz.png | Video |
  /// ─────────────────────────────────────────────────────────────────────────
  static const String _sheetId = String.fromEnvironment(
    'SHEETS_PUBLISHED_SHEET_KEY',
    defaultValue:
        '2PACX-1vS7XItmvTnzSvsG1Xbt4f_Uwfxwcxs6pGQ-rDKvCmmWk1athbKlPEidCfQzM0RiDo1CC3tg8P1NcveH',
  );
  static const String _sheetGid = String.fromEnvironment(
    'SHEETS_GID',
    defaultValue: '0',
  );

  static const String _cacheBodyKey = 'sheets_cache_body_v2';
  static const String _cacheAtKey = 'sheets_cache_at';

  static String get _csvUrl =>
      'https://docs.google.com/spreadsheets/d/e/$_sheetId/pub?gid=$_sheetGid&single=true&output=csv';

  /// Fetches URL list from Google Sheets; uses cached CSV when offline.
  static Future<SheetsLoadResult> fetchUrls() async {
    try {
      AppLogger.info('Fetching URLs from Google Sheets');
      if (_sheetId.isEmpty) {
        throw Exception(
          'Missing SHEETS_PUBLISHED_SHEET_KEY. Run app with --dart-define=SHEETS_PUBLISHED_SHEET_KEY=your_published_sheet_key',
        );
      }

      final response = await http.get(
        Uri.parse(_csvUrl),
        headers: {'Accept': 'text/csv'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        AppLogger.warn('Sheet fetch failed with status ${response.statusCode}');
        throw Exception('Failed to fetch sheet: ${response.statusCode}');
      }

      await _saveCache(response.body);
      final items = _parseCsvBody(response.body);
      AppLogger.info('Loaded ${items.length} URL entries from Sheets');
      return SheetsLoadResult(items: items);
    } catch (e) {
      final cached = await _loadCachedItems();
      if (cached != null && cached.isNotEmpty) {
        AppLogger.warn('Using cached Sheets data after fetch error: $e');
        return SheetsLoadResult(items: cached, fromCache: true);
      }
      AppLogger.error('SheetsService fetch failed', e);
      throw Exception('SheetsService error: $e');
    }
  }

  static Future<void> _saveCache(String body) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheBodyKey, body);
    await prefs.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<UrlItem>?> _loadCachedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final body = prefs.getString(_cacheBodyKey);
    if (body == null || body.isEmpty) {
      return null;
    }
    return _parseCsvBody(body);
  }

  static List<UrlItem> _parseCsvBody(String body) {
    final rows = _parseCsv(body);
    final items = <UrlItem>[];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 2 || row[1].trim().isEmpty) {
        continue;
      }
      final item = UrlItem.fromCsvRow(row);
      if (!item.hasHttpUrl) {
        AppLogger.warn('Skipping non-http(s) sheet row "${item.title}": ${item.url}');
        continue;
      }
      if (item.allowedUrls.isNotEmpty) {
        AppLogger.info(
          'Sheet row "${item.title}" allowed URLs: ${item.allowedUrls.join(', ')}',
        );
      }
      items.add(item);
    }
    return items;
  }

  /// CSV parser that keeps quoted fields (including embedded newlines) intact.
  static List<List<String>> _parseCsv(String body) {
    final rows = <List<String>>[];
    var fields = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (int i = 0; i < body.length; i++) {
      final char = body[i];
      if (char == '"') {
        if (inQuotes && i + 1 < body.length && body[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < body.length && body[i + 1] == '\n') {
          i++;
        }
        fields.add(buffer.toString());
        buffer.clear();
        if (fields.any((field) => field.trim().isNotEmpty)) {
          rows.add(fields);
        }
        fields = <String>[];
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty || fields.isNotEmpty) {
      fields.add(buffer.toString());
      if (fields.any((field) => field.trim().isNotEmpty)) {
        rows.add(fields);
      }
    }
    return rows;
  }
}
