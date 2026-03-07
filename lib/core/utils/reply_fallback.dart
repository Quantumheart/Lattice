/// Strips the Matrix reply fallback prefix (lines starting with `> `)
/// from a message body, returning only the actual reply text.
String stripReplyFallback(String body) {
  final lines = body.split('\n');
  var i = 0;
  while (i < lines.length && (lines[i].startsWith('> ') || lines[i] == '>')) {
    i++;
  }
  // Skip the blank line after the fallback block.
  if (i < lines.length && lines[i].isEmpty) i++;
  return lines.sublist(i).join('\n');
}
