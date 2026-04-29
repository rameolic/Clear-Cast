class UrlItem {
  final String title;
  final String url;
  final String thumbnailUrl;
  final String category;
  final String description;

  UrlItem({
    required this.title,
    required this.url,
    required this.thumbnailUrl,
    this.category = 'General',
    this.description = '',
  });

  /// Parse from a Google Sheets CSV row
  /// Expected columns: title, url, thumbnailUrl, category, description
  factory UrlItem.fromCsvRow(List<String> row) {
    return UrlItem(
      title: row.isNotEmpty ? row[0].trim() : 'Untitled',
      url: row.length > 1 ? row[1].trim() : '',
      thumbnailUrl: row.length > 2 ? row[2].trim() : '',
      category: row.length > 3 ? row[3].trim() : 'General',
      description: row.length > 4 ? row[4].trim() : '',
    );
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
