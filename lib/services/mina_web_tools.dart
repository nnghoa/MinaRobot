import 'dart:convert';

import 'package:http/http.dart' as http;

class WebSearchResult {
  final String title;
  final String url;
  final String snippet;

  WebSearchResult(this.title, this.url, this.snippet);
}

/// Công cụ web cho AI: tìm kiếm và đọc nội dung trang dưới dạng chữ thuần (bỏ quảng cáo, menu,
/// script) để AI tóm tắt và đọc lại cho người dùng.
class MinaWebTools {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 8.1.0; Visbot) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0 Mobile Safari/537.36';

  /// Tìm kiếm qua trang HTML của DuckDuckGo (không cần API key).
  static Future<List<WebSearchResult>> search(String query, {int limit = 5}) async {
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': query, 'kl': 'vn-vi'});
    final resp = await http
        .get(uri, headers: {'User-Agent': _ua, 'Accept-Language': 'vi-VN,vi;q=0.9'})
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return const [];
    final html = utf8.decode(resp.bodyBytes, allowMalformed: true);

    final results = <WebSearchResult>[];
    final linkRe = RegExp(
      r'<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    final snippetRe = RegExp(r'class="result__snippet"[^>]*>(.*?)</a>', dotAll: true);
    final snippets = snippetRe.allMatches(html).map((m) => _clean(m.group(1) ?? '')).toList();

    var i = 0;
    for (final m in linkRe.allMatches(html)) {
      final url = _unwrapDdgUrl(m.group(1) ?? '');
      if (url.isEmpty || url.contains('duckduckgo.com/y.js')) {
        i++;
        continue; // bỏ link quảng cáo của DuckDuckGo
      }
      results.add(WebSearchResult(
        _clean(m.group(2) ?? ''),
        url,
        i < snippets.length ? snippets[i] : '',
      ));
      i++;
      if (results.length >= limit) break;
    }
    return results;
  }

  /// Tải trang và trả về phần chữ chính (tối đa [maxChars] ký tự).
  static Future<String> readPage(String url, {int maxChars = 3500}) async {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    final resp = await http
        .get(Uri.parse(u), headers: {'User-Agent': _ua, 'Accept-Language': 'vi-VN,vi;q=0.9'})
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      return 'Không tải được trang (HTTP ${resp.statusCode}).';
    }
    var html = utf8.decode(resp.bodyBytes, allowMalformed: true);

    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false)
        .firstMatch(html);
    final title = _clean(titleMatch?.group(1) ?? '');

    // Ưu tiên thẻ <article> hoặc <main> nếu có
    final article = RegExp(r'<(article|main)[^>]*>(.*?)</\1>', dotAll: true, caseSensitive: false)
        .firstMatch(html);
    if (article != null && (article.group(2)?.length ?? 0) > 500) {
      html = article.group(2)!;
    }

    html = html.replaceAll(
        RegExp(r'<(script|style|noscript|nav|header|footer|aside|form|iframe|svg)[^>]*>.*?</\1>',
            dotAll: true, caseSensitive: false),
        ' ');
    html = html.replaceAll(RegExp(r'<br\s*/?>|</p>|</h\d>|</li>', caseSensitive: false), '\n');
    var text = _clean(html, keepNewlines: true);
    text = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.length > 30) // bỏ dòng menu/nút bấm ngắn
        .join('\n');
    if (text.length > maxChars) text = '${text.substring(0, maxChars)}…';
    return title.isEmpty ? text : '$title\n\n$text';
  }

  static String _unwrapDdgUrl(String href) {
    var h = _decodeEntities(href);
    if (h.startsWith('//')) h = 'https:$h';
    final uri = Uri.tryParse(h);
    if (uri == null) return '';
    final uddg = uri.queryParameters['uddg'];
    if (uddg != null && uddg.isNotEmpty) return uddg;
    return h;
  }

  static String _clean(String html, {bool keepNewlines = false}) {
    var s = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = _decodeEntities(s);
    if (keepNewlines) {
      s = s.replaceAll(RegExp(r'[ \t\r\f]+'), ' ').replaceAll(RegExp(r'\n\s*\n+'), '\n');
    } else {
      s = s.replaceAll(RegExp(r'\s+'), ' ');
    }
    return s.trim();
  }

  static String _decodeEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? '' : String.fromCharCode(code);
    });
  }
}
