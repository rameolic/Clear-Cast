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
  ///  3. Copy the Sheet ID from the URL:
  ///       https://docs.google.com/spreadsheets/d/SHEET_ID_HERE/edit
  ///
  ///  4. Replace SHEET_ID_HERE below with your actual Sheet ID
  ///
  ///  Example sheet row:
  ///    YouTube | https://youtube.com | https://i.imgur.com/xyz.png | Video |
  /// ─────────────────────────────────────────────────────────────────────────
  static const String _sheetId = 'SHEET_ID_HERE'; // 👈 Replace this
  static const String _sheetName = 'Sheet1'; // 👈 Change if different tab name

  static String get _csvUrl =>
      // 'https://docs.google.com/spreadsheets/d/$_sheetId/gviz/tq?tqx=out:csv&sheet=$_sheetName';
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vS7XItmvTnzSvsG1Xbt4f_Uwfxwcxs6pGQ-rDKvCmmWk1athbKlPEidCfQzM0RiDo1CC3tg8P1NcveH/pub?gid=0&single=true&output=csv';

  /// Fetches and parses the URL list from Google Sheets
  static Future<List<UrlItem>> fetchUrls() async {
    try {
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
