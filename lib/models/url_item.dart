import 'dart:convert';

class UrlItem {
  final String title;
  final String url;
  final String thumbnailUrl;
  final String category;
  final String description;
  /// Extra redirect bases from Sheets column `allowed`, e.g.
  /// `["https://what-is-reviews.blogspot.com/"]`
  final List<String> allowedUrls;

  UrlItem({
    required this.title,
    required this.url,
    required this.thumbnailUrl,
    this.category = 'General',
    this.description = '',
    this.allowedUrls = const [],
  });

  /// Parse from a Google Sheets CSV row.
  /// Columns: title, url, thumbnailUrl, category, description, allowed
  factory UrlItem.fromCsvRow(List<String> row) {
    return UrlItem(
      title: row.isNotEmpty ? row[0].trim() : 'Untitled',
      url: row.length > 1 ? row[1].trim() : '',
      thumbnailUrl: row.length > 2 ? row[2].trim() : '',
      category: row.length > 3 ? row[3].trim() : 'General',
      description: row.length > 4 ? row[4].trim() : '',
      allowedUrls: row.length > 5 ? _parseAllowedUrls(row[5]) : const [],
    );
  }

  static List<String> _parseAllowedUrls(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    // Google Sheets sometimes exports JSON with single quotes.
    if (trimmed.startsWith('[') && trimmed.contains("'")) {
      trimmed = trimmed.replaceAll("'", '"');
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return decoded
            .map((entry) => entry.toString().trim())
            .where((entry) => entry.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Fall through to plain URL parsing.
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return [trimmed];
    }

    return trimmed
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.startsWith('http'))
        .toList();
  }

  /// Fallback thumbnail using Google's favicon service
  String get resolvedThumbnail {
    if (thumbnailUrl.isNotEmpty) return thumbnailUrl;
    try {
      final uri = Uri.parse(url);
      return 'https://www.google.com/s2/favicons?domain=${uri.host}&sz=128';
    } catch (_) {
      return '';
    }
  }
}
