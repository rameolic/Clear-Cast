import 'package:http/http.dart' as http;
import '../models/url_item.dart';

class SheetsService {
  /// ─────────────────────────────────────────────────────────────────────────
  /// HOW TO SET UP YOUR GOOGLE SHEET:
  ///
  ///  1. Create a Google Sheet with these columns (row 1 = headers):
  ///       A: title | B: url | C: thumbnailUrl | D: category | E: description
  ///
  ///  2. Publish it to the web:
  ///       File → Share → Publish to web → Sheet1 → CSV → Publish
  ///
  ///  3. Use your published sheet key from URL:
  ///       https://docs.google.com/spreadsheets/d/e/PUBLISHED_SHEET_KEY/pubhtml
  ///
  ///  4. Configure values with --dart-define (optional):
  ///       --dart-define=SHEETS_PUBLISHED_SHEET_KEY=your_published_sheet_key
  ///       --dart-define=SHEETS_SHEET_NAME=Sheet1
  ///
  ///  Example sheet row:
  ///    YouTube | https://youtube.com | https://i.imgur.com/xyz.png | Video |
  /// ─────────────────────────────────────────────────────────────────────────
  static const String _sheetId = String.fromEnvironment(
    'SHEETS_PUBLISHED_SHEET_KEY',
    defaultValue: '2PACX-1vS7XItmvTnzSvsG1Xbt4f_Uwfxwcxs6pGQ-rDKvCmmWk1athbKlPEidCfQzM0RiDo1CC3tg8P1NcveH',
  );
  static const String _sheetName =
      String.fromEnvironment('SHEETS_SHEET_NAME', defaultValue: 'Sheet1');
  static const String _sheetGid = '0';

  static String get _csvUrl =>
      'https://docs.google.com/spreadsheets/d/e/$_sheetId/pub?gid=$_sheetGid&single=true&output=csv';

  /// Fetches and parses the URL list from Google Sheets
  static Future<List<UrlItem>> fetchUrls() async {
    try {
      if (_sheetId.isEmpty) {
        throw Exception(
          'Missing SHEETS_PUBLISHED_SHEET_KEY. Run app with --dart-define=SHEETS_PUBLISHED_SHEET_KEY=your_published_sheet_key',
        );
      }
      if (_sheetName.isEmpty) {
        throw Exception(
          'Missing SHEETS_SHEET_NAME. Run app with --dart-define=SHEETS_SHEET_NAME=Sheet1',
        );
      }

      final response = await http.get(
        Uri.parse(_csvUrl),
        headers: {'Accept': 'text/csv'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch sheet: ${response.statusCode}');
      }

      final lines = response.body.split('\n');
      final items = <UrlItem>[];

      // Skip header row (index 0)
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final row = _parseCsvLine(line);
        if (row.length >= 2 && row[1].isNotEmpty) {
          items.add(UrlItem.fromCsvRow(row));
        }
      }

      return items;
    } catch (e) {
      throw Exception('SheetsService error: $e');
    }
  }

  /// Minimal CSV line parser that handles quoted fields
  static List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"'); // escaped quote
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    fields.add(buffer.toString());
    return fields;
  }
}
