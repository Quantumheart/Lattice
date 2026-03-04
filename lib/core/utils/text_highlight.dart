class HighlightSpan {
  const HighlightSpan(this.text, this.isMatch);
  final String text;
  final bool isMatch;
}

List<HighlightSpan> highlightSpans(String text, String query) {
  if (query.isEmpty) return [HighlightSpan(text, false)];

  final lower = text.toLowerCase();
  final queryLower = query.toLowerCase();
  final spans = <HighlightSpan>[];
  var start = 0;

  while (start < text.length) {
    final index = lower.indexOf(queryLower, start);
    if (index == -1) {
      spans.add(HighlightSpan(text.substring(start), false));
      break;
    }
    if (index > start) {
      spans.add(HighlightSpan(text.substring(start, index), false));
    }
    spans.add(HighlightSpan(text.substring(index, index + query.length), true));
    start = index + query.length;
  }

  return spans;
}
