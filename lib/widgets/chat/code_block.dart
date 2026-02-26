import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight_core.dart' as hi;
import 'package:highlight/languages/bash.dart' as lang_bash;
import 'package:highlight/languages/cpp.dart' as lang_cpp;
import 'package:highlight/languages/cs.dart' as lang_cs;
import 'package:highlight/languages/css.dart' as lang_css;
import 'package:highlight/languages/dart.dart' as lang_dart;
import 'package:highlight/languages/go.dart' as lang_go;
import 'package:highlight/languages/java.dart' as lang_java;
import 'package:highlight/languages/javascript.dart' as lang_js;
import 'package:highlight/languages/json.dart' as lang_json;
import 'package:highlight/languages/kotlin.dart' as lang_kotlin;
import 'package:highlight/languages/markdown.dart' as lang_md;
import 'package:highlight/languages/php.dart' as lang_php;
import 'package:highlight/languages/python.dart' as lang_python;
import 'package:highlight/languages/ruby.dart' as lang_ruby;
import 'package:highlight/languages/rust.dart' as lang_rust;
import 'package:highlight/languages/sql.dart' as lang_sql;
import 'package:highlight/languages/swift.dart' as lang_swift;
import 'package:highlight/languages/typescript.dart' as lang_ts;
import 'package:highlight/languages/xml.dart' as lang_xml;
import 'package:highlight/languages/yaml.dart' as lang_yaml;

/// Renders a fenced code block with syntax highlighting and a copy button.
///
/// Used by [HtmlMessageText] to render `<pre><code>` blocks from Matrix
/// formatted messages.
class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.language,
    required this.isMe,
  });

  final String code;
  final String? language;
  final bool isMe;

  // ── Highlight.js engine (singleton) ──────────────────────────────

  static final hi.Highlight _highlight = _initHighlight();

  static hi.Highlight _initHighlight() {
    final h = hi.Highlight();
    h.registerLanguage('bash', lang_bash.bash);
    h.registerLanguage('c', lang_cpp.cpp);
    h.registerLanguage('cpp', lang_cpp.cpp);
    h.registerLanguage('csharp', lang_cs.cs);
    h.registerLanguage('css', lang_css.css);
    h.registerLanguage('dart', lang_dart.dart);
    h.registerLanguage('go', lang_go.go);
    h.registerLanguage('java', lang_java.java);
    h.registerLanguage('javascript', lang_js.javascript);
    h.registerLanguage('json', lang_json.json);
    h.registerLanguage('kotlin', lang_kotlin.kotlin);
    h.registerLanguage('markdown', lang_md.markdown);
    h.registerLanguage('php', lang_php.php);
    h.registerLanguage('python', lang_python.python);
    h.registerLanguage('ruby', lang_ruby.ruby);
    h.registerLanguage('rust', lang_rust.rust);
    h.registerLanguage('sql', lang_sql.sql);
    h.registerLanguage('swift', lang_swift.swift);
    h.registerLanguage('typescript', lang_ts.typescript);
    h.registerLanguage('html', lang_xml.xml);
    h.registerLanguage('xml', lang_xml.xml);
    h.registerLanguage('yaml', lang_yaml.yaml);
    // Common aliases.
    h.registerLanguage('js', lang_js.javascript);
    h.registerLanguage('ts', lang_ts.typescript);
    h.registerLanguage('py', lang_python.python);
    h.registerLanguage('rb', lang_ruby.ruby);
    h.registerLanguage('sh', lang_bash.bash);
    h.registerLanguage('shell', lang_bash.bash);
    h.registerLanguage('cs', lang_cs.cs);
    h.registerLanguage('md', lang_md.markdown);
    h.registerLanguage('yml', lang_yaml.yaml);
    return h;
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final bgColor = isMe
        ? cs.onPrimary.withValues(alpha: 0.12)
        : cs.surfaceContainerHighest;

    final textColor = isMe ? cs.onPrimary : cs.onSurface;

    final codeSpans = _buildHighlightedSpans(cs, brightness, textColor);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header bar ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4, top: 4),
            child: Row(
              children: [
                if (language != null)
                  Text(
                    language!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: textColor.withValues(alpha: 0.6),
                        ),
                  ),
                const Spacer(),
                SizedBox(
                  height: 32,
                  width: 32,
                  child: IconButton(
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: 'Copy code',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── Code area ──────────────────────────────────────────
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5,
                      color: textColor,
                    ),
                    children: codeSpans,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Syntax highlighting ──────────────────────────────────────────

  List<TextSpan> _buildHighlightedSpans(
    ColorScheme cs,
    Brightness brightness,
    Color defaultColor,
  ) {
    hi.Result result;
    try {
      if (language != null) {
        result = _highlight.parse(code, language: language);
      } else {
        result = _highlight.parse(code, autoDetection: true);
      }
    } catch (_) {
      return [TextSpan(text: code)];
    }

    if (result.nodes == null) {
      return [TextSpan(text: code)];
    }

    final theme = _getThemeMap(cs, brightness, defaultColor);
    final spans = <TextSpan>[];
    for (final node in result.nodes!) {
      _walkNode(node, theme, defaultColor, spans);
    }
    return spans;
  }

  void _walkNode(
    hi.Node node,
    Map<String, TextStyle> theme,
    Color defaultColor,
    List<TextSpan> spans, [
    String? inheritedClassName,
  ]) {
    final effectiveClass = node.className ?? inheritedClassName;
    if (node.value != null) {
      final style = effectiveClass != null ? theme[effectiveClass] : null;
      spans.add(TextSpan(text: node.value, style: style));
    } else if (node.children != null) {
      for (final child in node.children!) {
        _walkNode(child, theme, defaultColor, spans, effectiveClass);
      }
    }
  }

  static ColorScheme? _cachedColorScheme;
  static Brightness? _cachedBrightness;
  static Color? _cachedDefaultColor;
  static Map<String, TextStyle>? _cachedThemeMap;

  static Map<String, TextStyle> _getThemeMap(
    ColorScheme cs,
    Brightness brightness,
    Color defaultColor,
  ) {
    if (_cachedThemeMap != null &&
        cs == _cachedColorScheme &&
        brightness == _cachedBrightness &&
        defaultColor == _cachedDefaultColor) {
      return _cachedThemeMap!;
    }
    _cachedColorScheme = cs;
    _cachedBrightness = brightness;
    _cachedDefaultColor = defaultColor;
    _cachedThemeMap = _buildThemeMap(cs, brightness, defaultColor);
    return _cachedThemeMap!;
  }

  static Map<String, TextStyle> _buildThemeMap(
    ColorScheme cs,
    Brightness brightness,
    Color defaultColor,
  ) {
    final isLight = brightness == Brightness.light;

    final keyword = TextStyle(
      color: cs.primary,
      fontWeight: FontWeight.w600,
    );
    final string = TextStyle(
      color: isLight ? const Color(0xFF2E7D32) : const Color(0xFF81C784),
    );
    final comment = TextStyle(
      color: defaultColor.withValues(alpha: 0.5),
      fontStyle: FontStyle.italic,
    );
    final number = TextStyle(color: cs.secondary);
    final title = TextStyle(color: cs.tertiary);
    final builtin = TextStyle(color: cs.secondary);

    return {
      'keyword': keyword,
      'built_in': builtin,
      'type': title,
      'literal': number,
      'number': number,
      'regexp': string,
      'string': string,
      'subst': string,
      'symbol': number,
      'class': title,
      'function': title,
      'title': title,
      'params': TextStyle(color: defaultColor),
      'comment': comment,
      'doctag': comment,
      'meta': TextStyle(color: defaultColor.withValues(alpha: 0.7)),
      'meta-keyword': keyword,
      'meta-string': string,
      'section': title,
      'tag': keyword,
      'name': keyword,
      'attr': title,
      'attribute': title,
      'variable': number,
      'bullet': number,
      'code': TextStyle(color: defaultColor),
      'emphasis': const TextStyle(fontStyle: FontStyle.italic),
      'strong': const TextStyle(fontWeight: FontWeight.bold),
      'formula': string,
      'link': TextStyle(
        color: cs.primary,
        decoration: TextDecoration.underline,
      ),
      'quote': comment,
      'selector-tag': keyword,
      'selector-id': title,
      'selector-class': title,
      'selector-attr': keyword,
      'selector-pseudo': keyword,
      'template-tag': keyword,
      'template-variable': number,
      'addition': string,
      'deletion': TextStyle(
        color: isLight ? const Color(0xFFC62828) : const Color(0xFFEF9A9A),
      ),
    };
  }
}
