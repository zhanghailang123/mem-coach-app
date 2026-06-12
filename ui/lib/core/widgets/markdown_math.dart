import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

const _latexCommandPattern =
    r'(frac|dfrac|tfrac|sqrt|angle|triangle|Delta|theta|vartheta|pi|times|cdot|circ|degree|text|mathrm|operatorname|left|right|langle|rangle|begin|end|sum|prod|int|lim|partial|nabla|le|leq|ge|geq|neq|ne|infty|overline|underline|overbrace|overrightarrow|vec|bar|hat|tilde|dot|ddot|sin|cos|tan|cot|sec|csc|arcsin|arccos|arctan|log|ln|max|min|pm|mp|approx|alpha|beta|gamma|delta|epsilon|varepsilon|zeta|eta|iota|kappa|lambda|mu|nu|xi|rho|varrho|sigma|tau|upsilon|varphi|phi|chi|psi|omega|frown|overset|rightarrow|Rightarrow|longrightarrow|Longrightarrow|leftarrow|Leftarrow|leftrightarrow|Leftrightarrow|mapsto|xrightarrow|implies|to|neg|not|land|lor|wedge|vee|cap|cup|in|notin|subseteq|subset|supseteq|supset|forall|exists|emptyset|varnothing|perp|parallel|equiv|sim|simeq|cong|iff|vdash|therefore|because|pmod|mod|quad|qquad|cdots|dots|ldots|div|underbrace|oplus|lbrace|rbrace|hline|displaystyle|textstyle|scriptstyle|scriptscriptstyle)';

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
const _mobileMarkdownTableBreakpoint = 560.0;
const _greekIdentifierPattern =
    r'(alpha|beta|gamma|delta|epsilon|varepsilon|zeta|eta|theta|vartheta|iota|kappa|lambda|mu|nu|xi|pi|rho|varrho|sigma|tau|upsilon|phi|varphi|chi|psi|omega)';
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
    final effectiveMathColor = mathColor ?? effectiveTextColor;
    final effectiveStyleSheet = styleSheet ??
        examMarkdownStyleSheet(context,
            baseFontSize: baseFontSize, textColor: effectiveTextColor);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final preparedData = _softWrapMarkdownText(
          prepareMarkdownMath(
            data,
            compactTables: availableWidth < _mobileMarkdownTableBreakpoint,
          ),
        );

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
                maxInlineWidth: (availableWidth - 8).clamp(120, 520).toDouble(),
              ),
              'math-block': _EncodedMathBuilder(
                display: true,
                color: effectiveMathColor,
                fallbackColor: effectiveTextColor,
                baseFontSize: baseFontSize,
                maxInlineWidth: (availableWidth - 8).clamp(120, 520).toDouble(),
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
    tableColumnWidth: const FlexColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
  final normalizedFormula = _normalizeLatexFormula(formula);
  final fontSize = textStyle.fontSize ?? 14;
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: _InlineMathBox(
      maxWidth: 220,
      child: Math.tex(
        normalizedFormula,
        mathStyle: MathStyle.text,
        textStyle: textStyle.copyWith(
          color: mathColor,
          fontSize: fontSize,
          height: 1.2,
        ),
        onErrorFallback: (_) => Text(
          _softWrapFormulaText(normalizedFormula),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle.copyWith(color: mathColor),
        ),
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

String prepareMarkdownMath(String input, {bool compactTables = false}) {
  var text = normalizeMarkdownMath(input);
  text = _encodeMarkdownMathOutsideCodeBlocks(text);
  if (compactTables) text = _compactMarkdownTables(text);
  return text;
}

String _encodeMarkdownMathOutsideCodeBlocks(String text) {
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

String _compactMarkdownTables(String text) {
  final buffer = StringBuffer();
  var lastIndex = 0;

  for (final match in _fencedCodeBlockRe.allMatches(text)) {
    buffer.write(_compactMarkdownTablesInPlainText(
      text.substring(lastIndex, match.start),
    ));
    buffer.write(match.group(0));
    lastIndex = match.end;
  }

  buffer.write(_compactMarkdownTablesInPlainText(text.substring(lastIndex)));
  return buffer.toString();
}

String _compactMarkdownTablesInPlainText(String text) {
  final lines = text.split('\n');
  final output = <String>[];
  var index = 0;

  while (index < lines.length) {
    if (index + 1 < lines.length &&
        _isMarkdownTableRow(lines[index]) &&
        _isMarkdownTableSeparator(lines[index + 1])) {
      final tableLines = <String>[lines[index], lines[index + 1]];
      index += 2;
      while (index < lines.length && _isMarkdownTableRow(lines[index])) {
        tableLines.add(lines[index]);
        index += 1;
      }

      final compacted = _markdownTableToMobileBlocks(tableLines);
      if (compacted != null) {
        if (output.isNotEmpty && output.last.trim().isNotEmpty) {
          output.add('');
        }
        output.addAll(compacted.split('\n'));
        if (index < lines.length && lines[index].trim().isNotEmpty) {
          output.add('');
        }
        continue;
      }

      output.addAll(tableLines);
      continue;
    }

    output.add(lines[index]);
    index += 1;
  }

  return output.join('\n');
}

bool _isMarkdownTableRow(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty ||
      trimmed.startsWith('```') ||
      trimmed.startsWith('~~~')) {
    return false;
  }
  return _splitMarkdownTableRow(trimmed).length >= 2;
}

bool _isMarkdownTableSeparator(String line) {
  final cells = _splitMarkdownTableRow(line);
  if (cells.length < 2) return false;
  return cells.every((cell) {
    final marker = cell.replaceAll(' ', '').trim();
    return RegExp(r'^:?-{2,}:?$').hasMatch(marker);
  });
}

String? _markdownTableToMobileBlocks(List<String> tableLines) {
  if (tableLines.length < 3) return null;
  final headers = _splitMarkdownTableRow(tableLines.first);
  if (headers.length < 2) return null;

  final rows = tableLines
      .skip(2)
      .map(_splitMarkdownTableRow)
      .where((row) => row.any((cell) => cell.trim().isNotEmpty))
      .toList();
  if (rows.isEmpty) return null;

  final buffer = StringBuffer();
  for (final row in rows) {
    final normalizedRow = List<String>.generate(
      headers.length,
      (cellIndex) => cellIndex < row.length ? row[cellIndex].trim() : '',
    );
    final firstCell = normalizedRow.first.trim();
    final hasTitle = firstCell.isNotEmpty;

    if (hasTitle) {
      buffer.writeln('**$firstCell**');
    }

    final startIndex = hasTitle ? 1 : 0;
    for (var cellIndex = startIndex; cellIndex < headers.length; cellIndex++) {
      final cell = normalizedRow[cellIndex].trim();
      if (cell.isEmpty) continue;
      final header = headers[cellIndex].trim();
      if (header.isEmpty) {
        buffer.writeln('- $cell');
      } else {
        buffer.writeln('- **$header**：$cell');
      }
    }
    buffer.writeln();
  }

  return buffer.toString().trimRight();
}

List<String> _splitMarkdownTableRow(String line) {
  var text = line.trim();
  if (!text.contains('|')) return const [];
  if (text.startsWith('|')) text = text.substring(1);
  if (text.endsWith('|')) text = text.substring(0, text.length - 1);

  final cells = <String>[];
  final buffer = StringBuffer();
  var escaped = false;
  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (char == '\\' && !escaped) {
      escaped = true;
      buffer.write(char);
      continue;
    }
    if (char == '|' && !escaped) {
      cells.add(buffer.toString().trim().replaceAll(r'\|', '|'));
      buffer.clear();
      continue;
    }
    buffer.write(char);
    escaped = false;
  }
  cells.add(buffer.toString().trim().replaceAll(r'\|', '|'));
  return cells;
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
  var normalized = _normalizeLineBreaks(input);

  normalized = _normalizeEmbeddedHtml(normalized);
  normalized = _normalizeMathSentinelDelimiters(normalized);
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

String _normalizeLineBreaks(String input) {
  var normalized = _repairControlEscapedLatexCommands(input)
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');

  normalized = normalized.replaceAll(r'\r\n', '\n');
  normalized = normalized.replaceAllMapped(
    RegExp(r'\\n(?![A-Za-z])'),
    (_) => '\n',
  );
  normalized = normalized.replaceAllMapped(
    RegExp(r'\\r(?![A-Za-z])'),
    (_) => '\n',
  );
  return normalized;
}

String _repairControlEscapedLatexCommands(String text) {
  // Some imported code-199 content has "\right" decoded as carriage-return + "ight".
  return text
      .replaceAll('\r' 'ight', r'\right')
      .replaceAll('\r' 'ho', r'\rho')
      .replaceAll('\r' 'angle', r'\rangle')
      .replaceAll('\r' 'brace', r'\rbrace');
}

String _normalizeMathSentinelDelimiters(String text) {
  return text.replaceAllMapped(
    RegExp(r'\$begin:math\$([\s\S]*?)\$end:math\$', caseSensitive: false),
    (match) {
      final body = (match.group(1) ?? '').trim();
      if (body.isEmpty) return '';
      if (body.contains('\n')) return '\n\$\$$body\$\$\n';
      return '\$$body\$';
    },
  );
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
    required this.maxInlineWidth,
    this.backgroundColor,
    this.borderColor,
  });

  final bool display;
  final Color color;
  final Color fallbackColor;
  final double baseFontSize;
  final double maxInlineWidth;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final formula = _normalizeLatexFormula(_decodeFormula(element.textContent));
    if (formula.trim().isEmpty) return null;
    final fallbackText = display
        ? '\$\$${_softWrapFormulaText(formula)}\$\$'
        : '\$${_softWrapFormulaText(formula)}\$';

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
          fallbackText,
          softWrap: true,
          style: (preferredStyle ?? TextStyle(fontSize: baseFontSize)).copyWith(
            color: fallbackColor,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.normal, // 同样强制使用常规字重
          ),
        );
      },
    );

    if (!display) {
      return _InlineMathBox(maxWidth: maxInlineWidth, child: math);
    }

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

class _InlineMathBox extends StatelessWidget {
  const _InlineMathBox({
    required this.maxWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var effectiveMaxWidth = maxWidth;
        if (constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0 &&
            constraints.maxWidth < effectiveMaxWidth) {
          effectiveMaxWidth = constraints.maxWidth;
        }
        return ClipRect(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

String _normalizeLatexFormula(String raw) {
  var formula = _repairControlEscapedLatexCommands(raw).trim();
  formula = formula
      .replaceAll(RegExp(r'\\dfrac\b'), r'\frac')
      .replaceAll(RegExp(r'\\tfrac\b'), r'\frac')
      .replaceAll(
        RegExp(
            r'\\(?:displaystyle|textstyle|scriptstyle|scriptscriptstyle)\b\s*'),
        '',
      )
      .replaceAllMapped(
        RegExp(r'\\\\\s*[\[［]\s*-?(?:\d+(?:\.\d+)?)?\s*pt\s*[\]］]'),
        (_) => r'\\',
      )
      .replaceAll(
        RegExp(r'\s*[\[［]\s*-?(?:\d+(?:\.\d+)?)?\s*pt\s*[\]］]\s*'),
        ' ',
      )
      .replaceAll('，', ',')
      .replaceAll('；', ';')
      .replaceAll('：', ':')
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('［', '[')
      .replaceAll('］', ']')
      .replaceAll('＋', '+')
      .replaceAll('－', '-')
      .replaceAll('＝', '=')
      .replaceAll('×', r'\times ')
      .replaceAll('÷', r'\div ')
      .replaceAll('≤', r'\le ')
      .replaceAll('≥', r'\ge ')
      .replaceAll('≠', r'\ne ')
      .replaceAll('∞', r'\infty ')
      .replaceAll('π', r'\pi ');

  formula = formula.replaceAllMapped(
    RegExp(r'(^|[^\\A-Za-z])' + _greekIdentifierPattern + r'\b'),
    (match) => '${match.group(1)}\\${match.group(2)}',
  );
  formula = formula.replaceAllMapped(
    RegExp(r'\\sqrt\{(' +
        _greekIdentifierPattern.substring(
            1, _greekIdentifierPattern.length - 1) +
        r')\}'),
    (match) => '\\sqrt{\\${match.group(1)}}',
  );
  formula = formula.replaceAllMapped(
    RegExp(r'([0-9A-Za-z)\]}])\s*°'),
    (match) => '${match.group(1)}^\\circ',
  );
  formula = formula.replaceAllMapped(
    RegExp(r'√\s*\{([^{}]+)\}'),
    (match) => '\\sqrt{${match.group(1)}}',
  );
  formula = formula.replaceAllMapped(
    RegExp(r'√\s*([A-Za-z0-9]+)'),
    (match) => '\\sqrt{${match.group(1)}}',
  );
  return formula;
}

String _softWrapFormulaText(String formula) {
  return formula
      .replaceAllMapped(
          RegExp(r'([,;=+\-*/<>])'), (match) => '${match.group(1)}\u200B')
      .replaceAllMapped(
          RegExp(
              r'(\\qquad|\\quad|\\cdot|\\times|\\approx|\\Rightarrow|\\rightarrow)'),
          (match) => '${match.group(1)}\u200B')
      .replaceAllMapped(
          RegExp(r'(\S{18})'), (match) => '${match.group(1)}\u200B');
}
