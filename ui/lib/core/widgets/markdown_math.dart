import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

const _latexCommandPattern =
    r'(frac|sqrt|angle|triangle|Delta|theta|pi|times|cdot|circ|text|left|right|begin|end|sum|int|le|leq|ge|geq|neq|ne|infty|overline|overrightarrow|vec|bar|sin|cos|tan|log|ln|max|min|pm|mp|approx|alpha|beta|gamma|sigma|lambda|mu|rho|varphi|phi|frown|overset|rightarrow|Rightarrow|leftrightarrow|Leftrightarrow|xrightarrow|implies|to|neg|not|land|lor|wedge|vee|cap|cup|in|notin|subseteq|forall|exists|emptyset|perp|equiv|sim|iff|vdash|pmod|quad|cdot|cdots|dots|ldots|div|underbrace|oplus|lbrace|rbrace|hline)';

final _latexCommandRe = RegExp(r'\\' + _latexCommandPattern + r'\b');
final _mathOperatorRe = RegExp(r'[=<>^_{}|+*/]');
final _geometryLabelRe = RegExp(r"^[A-Z][A-Z0-9']{0,4}$");
final _doubleEscapedLatexCommandRe =
    RegExp(r'\\\\' + _latexCommandPattern + r'\b');
final _fencedCodeBlockRe = RegExp(r'(```[\s\S]*?```|~~~[\s\S]*?~~~)');
final _cjkTextRe = RegExp(r'[\u3400-\u9FFF]');
final _htmlTagRe = RegExp(r'<[^>]+>');
final _lineBreakHtmlRe = RegExp(r'<br\s*/?>', caseSensitive: false);
final _imgHtmlRe = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _softWrapProtectedMarkdownSegmentRe = RegExp(
  r'(<math-(?:inline|block)>[^<]+</math-(?:inline|block)>|!?\[[^\]\n]*\]\([^)]+\)|<[^>\n]+>)',
);
final _longUnbrokenAsciiRunRe =
    RegExp(r'[A-Za-z0-9][A-Za-z0-9._:/?&=%+#,\-]{27,}');
final _markdownLinkOrImageRe = RegExp(r'(!?)\[([^\]\n]*)\]\(([^)]+)\)');
final _bareLatexEnvironmentRe = RegExp(
  r'(^|\n)([ \t]*)(\\begin\{([A-Za-z*]+)\}[\s\S]*?\\end\{[A-Za-z*]+\})([ \t]*)(?=\n|$)',
);
const _blockMathEnvironmentNames = {
  'aligned',
  'align',
  'align*',
  'gathered',
  'gather',
  'gather*',
  'cases',
  'matrix',
  'pmatrix',
  'bmatrix',
  'vmatrix',
  'array',
  'split',
};

/// Markdown + LaTeX renderer shared by exam pages and chat bubbles.
class MarkdownMathView extends StatelessWidget {
  const MarkdownMathView({
    super.key,
    required this.data,
    this.selectable = true,
    this.styleSheet,
    this.textColor,
    this.mathColor,
    this.blockMathBackground,
    this.blockMathBorderColor,
    this.baseFontSize = 15,
  });

  final String data;
  final bool selectable;
  final MarkdownStyleSheet? styleSheet;
  final Color? textColor;
  final Color? mathColor;
  final Color? blockMathBackground;
  final Color? blockMathBorderColor;
  final double baseFontSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveTextColor =
        textColor ?? (isDark ? const Color(0xFFE5E5E7) : Colors.black87);
    final effectiveMathColor =
        mathColor ?? effectiveTextColor;
    final effectiveStyleSheet = styleSheet ??
        examMarkdownStyleSheet(context,
            baseFontSize: baseFontSize, textColor: effectiveTextColor);

    final preparedData = _softWrapMarkdownText(prepareMarkdownMath(data));

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;

        return SizedBox(
          width: availableWidth,
          child: MarkdownBody(
            data: preparedData,
            selectable: selectable,
            extensionSet: md.ExtensionSet.gitHubFlavored,
            inlineSyntaxes: [
              _EncodedMathSyntax('math-inline'),
              _EncodedMathSyntax('math-block'),
            ],
            builders: {
              'math-inline': _EncodedMathBuilder(
                display: false,
                color: effectiveMathColor,
                fallbackColor: effectiveTextColor,
                baseFontSize: baseFontSize,
              ),
              'math-block': _EncodedMathBuilder(
                display: true,
                color: effectiveMathColor,
                fallbackColor: effectiveTextColor,
                baseFontSize: baseFontSize,
                backgroundColor: blockMathBackground ??
                    effectiveMathColor.withValues(alpha: 0.06),
                borderColor: blockMathBorderColor ??
                    effectiveMathColor.withValues(alpha: 0.14),
              ),
            },
            styleSheet: effectiveStyleSheet,
          ),
        );
      },
    );
  }
}

/// Compact inline Markdown/LaTeX preview for list rows.
class MarkdownMathPreview extends StatelessWidget {
  const MarkdownMathPreview({
    super.key,
    required this.data,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.style,
    this.mathColor,
  });

  final String data;
  final int maxLines;
  final TextOverflow overflow;
  final TextStyle? style;
  final Color? mathColor;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = defaultStyle.merge(style);
    final effectiveMathColor =
        mathColor ?? Theme.of(context).colorScheme.primary;

    return RichText(
      maxLines: maxLines,
      overflow: overflow,
      text: TextSpan(
        style: effectiveStyle,
        children: _buildPreviewSpans(
          data,
          textStyle: effectiveStyle,
          mathColor: effectiveMathColor,
        ),
      ),
    );
  }
}

MarkdownStyleSheet examMarkdownStyleSheet(
  BuildContext context, {
  double baseFontSize = 15,
  Color? textColor,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final foreground =
      textColor ?? (isDark ? const Color(0xFFE5E5E7) : Colors.black87);
  final muted = isDark ? const Color(0xFF98989D) : Colors.black54;
  final borderColor = isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.black.withValues(alpha: 0.08);

  return MarkdownStyleSheet(
    p: TextStyle(
      color: foreground,
      fontSize: baseFontSize,
      height: 1.68,
      fontWeight: FontWeight.w500,
    ),
    h1: TextStyle(
      color: foreground,
      fontSize: baseFontSize + 6,
      fontWeight: FontWeight.w900,
      height: 1.35,
    ),
    h2: TextStyle(
      color: foreground,
      fontSize: baseFontSize + 4,
      fontWeight: FontWeight.w900,
      height: 1.35,
    ),
    h3: TextStyle(
      color: foreground,
      fontSize: baseFontSize + 2,
      fontWeight: FontWeight.bold,
      height: 1.45,
    ),
    h4: TextStyle(
      color: foreground,
      fontSize: baseFontSize + 1,
      fontWeight: FontWeight.w800,
      height: 1.45,
    ),
    listBullet: TextStyle(
      color: foreground,
      fontSize: baseFontSize,
      height: 1.55,
    ),
    code: TextStyle(
      color: colorScheme.primary,
      fontSize: baseFontSize - 1,
      fontFamily: 'monospace',
      backgroundColor: colorScheme.primary.withValues(alpha: 0.07),
    ),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xFF1F2430),
      borderRadius: BorderRadius.circular(12),
    ),
    codeblockPadding: const EdgeInsets.all(14),
    blockquote: TextStyle(
      color: muted,
      fontSize: baseFontSize,
      height: 1.6,
      fontStyle: FontStyle.italic,
    ),
    blockquoteDecoration: BoxDecoration(
      color: colorScheme.primary.withValues(alpha: 0.05),
      border: Border(
        left: BorderSide(
          color: colorScheme.primary.withValues(alpha: 0.35),
          width: 4,
        ),
      ),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
    a: TextStyle(
      color: colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: colorScheme.primary.withValues(alpha: 0.45),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(
          color: borderColor,
          width: 1,
        ),
      ),
    ),
    tableHead: TextStyle(
      color: foreground,
      fontSize: baseFontSize - 1,
      fontWeight: FontWeight.w900,
    ),
    tableBody: TextStyle(
      color: foreground,
      fontSize: baseFontSize - 1,
      height: 1.45,
    ),
    tableBorder: TableBorder.all(color: borderColor),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );
}

List<InlineSpan> _buildPreviewSpans(
  String input, {
  required TextStyle textStyle,
  required Color mathColor,
}) {
  final normalized = normalizeMarkdownMath(input);
  final spans = <InlineSpan>[];
  final mathPattern = RegExp(
    r'\$\$([\s\S]+?)\$\$|(^|[^\\])\$(?!\$)([^\n$]+?)\$',
  );
  var cursor = 0;

  for (final match in mathPattern.allMatches(normalized)) {
    final isBlockMath = match.group(1) != null;
    final prefix = isBlockMath ? '' : (match.group(2) ?? '');
    final formulaStart =
        isBlockMath ? match.start : match.start + prefix.length;

    _appendPreviewText(
      spans,
      normalized.substring(cursor, formulaStart),
      textStyle,
    );

    final formula = (isBlockMath ? match.group(1) : match.group(3))?.trim();
    if (formula != null && formula.isNotEmpty) {
      spans.add(_previewMathSpan(formula, textStyle, mathColor));
    }

    cursor = match.end;
  }

  _appendPreviewText(spans, normalized.substring(cursor), textStyle);

  if (spans.isEmpty) {
    spans.add(TextSpan(text: _cleanPreviewText(normalized), style: textStyle));
  }
  return spans;
}

void _appendPreviewText(
  List<InlineSpan> spans,
  String rawText,
  TextStyle textStyle,
) {
  final text = _cleanPreviewText(rawText);
  if (text.isEmpty) return;
  spans.add(TextSpan(text: text, style: textStyle));
}

InlineSpan _previewMathSpan(
  String formula,
  TextStyle textStyle,
  Color mathColor,
) {
  final fontSize = textStyle.fontSize ?? 14;
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Math.tex(
      formula,
      mathStyle: MathStyle.text,
      textStyle: textStyle.copyWith(
        color: mathColor,
        fontSize: fontSize,
        height: 1.2,
      ),
      onErrorFallback: (_) => Text(
        formula,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyle.copyWith(color: mathColor),
      ),
    ),
  );
}

String _cleanPreviewText(String text) {
  var output = text
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '')
      .replaceAll(_lineBreakHtmlRe, ' ')
      .replaceAll(_htmlTagRe, '')
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\d+[\.)]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'[`*_~>#]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (output.trim().isEmpty) return '';
  return output;
}

String prepareMarkdownMath(String input) {
  final text = normalizeMarkdownMath(input);
  final buffer = StringBuffer();
  var lastIndex = 0;

  for (final match in _fencedCodeBlockRe.allMatches(text)) {
    buffer.write(_encodeMathSegments(text.substring(lastIndex, match.start)));
    buffer.write(match.group(0));
    lastIndex = match.end;
  }

  buffer.write(_encodeMathSegments(text.substring(lastIndex)));
  return buffer.toString();
}

String _softWrapMarkdownText(String text) {
  final buffer = StringBuffer();
  var cursor = 0;

  for (final match in _softWrapProtectedMarkdownSegmentRe.allMatches(text)) {
    buffer
        .write(_softWrapPlainMarkdownText(text.substring(cursor, match.start)));
    buffer.write(_softWrapProtectedMarkdownSegment(match.group(0) ?? ''));
    cursor = match.end;
  }

  buffer.write(_softWrapPlainMarkdownText(text.substring(cursor)));
  return buffer.toString();
}

String _softWrapProtectedMarkdownSegment(String segment) {
  if (segment.startsWith('<math-inline>') ||
      segment.startsWith('<math-block>')) {
    return segment;
  }
  return segment.replaceAllMapped(_markdownLinkOrImageRe, (match) {
    final prefix = match.group(1) ?? '';
    final label = match.group(2) ?? '';
    final target = match.group(3) ?? '';
    return '$prefix[${_softWrapPlainMarkdownText(label)}]($target)';
  });
}

String _softWrapPlainMarkdownText(String text) {
  return text.replaceAllMapped(_longUnbrokenAsciiRunRe, (match) {
    final value = match.group(0) ?? '';
    if (value.isEmpty) return value;

    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      buffer.write(value[i]);
      final shouldBreak = (i + 1) % 16 == 0 && i != value.length - 1;
      if (shouldBreak) buffer.write('\u200B');
    }
    return buffer.toString();
  });
}

String normalizeMarkdownMath(String input) {
  var normalized = input
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\n');

  normalized = _normalizeEmbeddedHtml(normalized);
  normalized = _normalizeDoubleEscapedMathDelimiters(normalized);
  normalized = normalized.replaceAllMapped(
    _doubleEscapedLatexCommandRe,
    (match) => '\\${match.group(1)}',
  );
  normalized = normalized.replaceAllMapped(
    RegExp(r'\\\(([\s\S]*?)\\\)'),
    (match) => '\$${match.group(1) ?? ''}\$',
  );
  normalized = normalized.replaceAllMapped(
    RegExp(r'\\\[([\s\S]*?)\\\]'),
    (match) => '\$\$${match.group(1) ?? ''}\$\$',
  );
  normalized = _normalizeMathCodeSpans(normalized);
  normalized = _normalizeBareMathEnvironments(normalized);
  normalized = _normalizeBareMathLines(normalized);
  return normalized;
}

String _normalizeDoubleEscapedMathDelimiters(String text) {
  var normalized = text.replaceAllMapped(
    RegExp(r'\\\\\(([\s\S]*?)\\\\\)'),
    (match) => '\$${match.group(1) ?? ''}\$',
  );
  normalized = normalized.replaceAllMapped(
    RegExp(r'\\\\\[([\s\S]*?)\\\\\]'),
    (match) => '\$\$${match.group(1) ?? ''}\$\$',
  );
  return normalized;
}

String _normalizeEmbeddedHtml(String text) {
  return text
      .replaceAllMapped(_imgHtmlRe, (match) {
        final tag = match.group(0) ?? '';
        final src = _readHtmlAttribute(tag, 'src');
        if (src == null || src.isEmpty) return '';
        final alt = _readHtmlAttribute(tag, 'alt') ?? 'image';
        return '\n\n![$alt]($src)\n\n';
      })
      .replaceAll(_lineBreakHtmlRe, '\n')
      .replaceAll(RegExp(r'</?div\b[^>]*>', caseSensitive: false), '\n');
}

String? _readHtmlAttribute(String tag, String name) {
  final pattern = RegExp(
    "$name\\s*=\\s*(['\"])(.*?)\\1",
    caseSensitive: false,
  );
  return pattern.firstMatch(tag)?.group(2);
}

String _normalizeMathCodeSpans(String text) {
  return text.replaceAllMapped(RegExp(r'`([^`\n]+)`'), (match) {
    final body = (match.group(1) ?? '').trim();
    if (!_isLikelyMathCodeSpan(body)) {
      return match.group(0) ?? '';
    }
    return '\$$body\$';
  });
}

bool _isLikelyMathCodeSpan(String value) {
  final text = value.trim();
  if (text.isEmpty || text.contains('\n') || text.contains(r'$')) {
    return false;
  }
  if (_latexCommandRe.hasMatch(text)) return true;
  if (_mathOperatorRe.hasMatch(text) &&
      RegExp(r'[A-Za-z0-9\\]').hasMatch(text)) {
    return true;
  }
  if (_geometryLabelRe.hasMatch(text)) return true;
  return false;
}

String _normalizeBareMathLines(String text) {
  return text.split('\n').map(_normalizeBareMathLine).join('\n');
}

String _normalizeBareMathEnvironments(String text) {
  return text.replaceAllMapped(_bareLatexEnvironmentRe, (match) {
    final original = match.group(0) ?? '';
    final environment = match.group(4) ?? '';
    if (!_blockMathEnvironmentNames.contains(environment)) return original;

    final formula = (match.group(3) ?? '').trim();
    if (formula.isEmpty || formula.contains(r'$')) return original;
    if (!formula.endsWith('\\end{$environment}')) return original;

    final leadingBreak = match.group(1)?.isNotEmpty == true ? '\n' : '';
    return '$leadingBreak\n\$\$$formula\$\$\n';
  });
}

String _normalizeBareMathLine(String line) {
  if (line.trim().isEmpty || line.contains(r'$')) return line;

  final leading = RegExp(r'^\s*').firstMatch(line)?.group(0) ?? '';
  final trailing = RegExp(r'\s*$').firstMatch(line)?.group(0) ?? '';
  final end = line.length - trailing.length;
  if (end < leading.length) return line;

  final core = line.substring(leading.length, end);
  if (core.isEmpty || core.startsWith('|') || core.startsWith('<')) {
    return line;
  }

  final optionMatch = RegExp(r'^([A-E][\.\、]\s+)(.+)$').firstMatch(core);
  if (optionMatch != null) {
    final label = optionMatch.group(1) ?? '';
    final body = optionMatch.group(2)?.trim() ?? '';
    if (_isLikelyBareMathExpression(body)) {
      return '$leading$label\$$body\$$trailing';
    }
  }

  if (_isLikelyBareMathExpression(core)) {
    return '$leading\$${core.trim()}\$$trailing';
  }

  return line;
}

bool _isLikelyBareMathExpression(String value) {
  final text = value.trim();
  if (text.isEmpty ||
      text.contains('\n') ||
      text.contains(r'$') ||
      text.contains('```') ||
      text.contains('://') ||
      _cjkTextRe.hasMatch(text)) {
    return false;
  }

  final hasLatexCommand = _latexCommandRe.hasMatch(text);
  final hasMathOperator =
      _mathOperatorRe.hasMatch(text) && RegExp(r'[A-Za-z0-9\\]').hasMatch(text);
  if (!hasLatexCommand && !hasMathOperator) return false;

  final residue = text
      .replaceAll(_latexCommandRe, '')
      .replaceAll(RegExp(r'[A-Za-z0-9\s\\{}\[\]().,;:+\-*/=<>^_|&%]+'), '')
      .replaceAll('π', '')
      .replaceAll('∞', '')
      .replaceAll('√', '')
      .replaceAll('±', '')
      .replaceAll('×', '')
      .replaceAll('÷', '')
      .replaceAll('°', '');
  return residue.isEmpty;
}

String _encodeMathSegments(String text) {
  var encoded = text.replaceAllMapped(RegExp(r'\$\$([\s\S]+?)\$\$'), (match) {
    final formula = (match.group(1) ?? '').trim();
    if (formula.isEmpty) return match.group(0) ?? '';
    return '\n\n${_mathTag(formula, display: true)}\n\n';
  });

  encoded = encoded.replaceAllMapped(
    RegExp(r'(^|[^\\])\$(?!\$)([^\n$]+?)\$'),
    (match) {
      final prefix = match.group(1) ?? '';
      final formula = (match.group(2) ?? '').trim();
      if (formula.isEmpty || formula.endsWith(r'\')) {
        return match.group(0) ?? '';
      }
      return '$prefix${_mathTag(formula, display: false)}';
    },
  );

  return encoded;
}

String _mathTag(String formula, {required bool display}) {
  final payload = base64Url.encode(utf8.encode(formula));
  final tag = display ? 'math-block' : 'math-inline';
  return '<$tag>$payload</$tag>';
}

class _EncodedMathSyntax extends md.InlineSyntax {
  _EncodedMathSyntax(this.tag) : super('<$tag>([^<]+)</$tag>');

  final String tag;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(tag, match.group(1) ?? ''));
    return true;
  }
}

class _EncodedMathBuilder extends MarkdownElementBuilder {
  _EncodedMathBuilder({
    required this.display,
    required this.color,
    required this.fallbackColor,
    required this.baseFontSize,
    this.backgroundColor,
    this.borderColor,
  });

  final bool display;
  final Color color;
  final Color fallbackColor;
  final double baseFontSize;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final formula = _decodeFormula(element.textContent);
    if (formula.trim().isEmpty) return null;

    final math = Math.tex(
      formula,
      textStyle: (preferredStyle ?? TextStyle(fontSize: baseFontSize)).copyWith(
        color: color,
        fontSize: display ? baseFontSize + 1 : baseFontSize,
        height: 1.25,
        fontWeight: FontWeight.normal, // 强制学术符号使用常规字重，防止跟随标题等加粗
      ),
      mathStyle: display ? MathStyle.display : MathStyle.text,
      onErrorFallback: (error) {
        return Text(
          display ? '\$\$$formula\$\$' : '\$$formula\$',
          style: (preferredStyle ?? TextStyle(fontSize: baseFontSize)).copyWith(
            color: fallbackColor,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.normal, // 同样强制使用常规字重
          ),
        );
      },
    );

    if (!display) return math;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? Colors.transparent),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: math,
      ),
    );
  }

  String _decodeFormula(String payload) {
    try {
      return utf8.decode(base64Url.decode(payload.trim()));
    } catch (_) {
      return payload;
    }
  }
}
