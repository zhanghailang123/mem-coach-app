import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

const _latexCommandPattern =
    r'(frac|sqrt|angle|triangle|Delta|theta|pi|times|cdot|circ|text|left|right|begin|end|sum|int|le|ge|neq|infty|overline|vec|sin|cos|tan|log|ln|max|min|pm|mp|approx|alpha|beta|gamma|lambda|mu|rho|varphi|phi|frown|overset)';

final _latexCommandRe = RegExp(r'\\' + _latexCommandPattern + r'\b');
final _mathOperatorRe = RegExp(r'[=<>^_{}|+*/]');
final _geometryLabelRe = RegExp(r"^[A-Z][A-Z0-9']{0,4}$");
final _doubleEscapedLatexCommandRe =
    RegExp(r'\\\\' + _latexCommandPattern + r'\b');
final _fencedCodeBlockRe = RegExp(r'(```[\s\S]*?```|~~~[\s\S]*?~~~)');

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
    final effectiveTextColor = textColor ?? Colors.black87;
    final effectiveMathColor =
        mathColor ?? Theme.of(context).colorScheme.primary;
    final effectiveStyleSheet = styleSheet ??
        examMarkdownStyleSheet(context, baseFontSize: baseFontSize);

    return MarkdownBody(
      data: prepareMarkdownMath(data),
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
          backgroundColor:
              blockMathBackground ?? effectiveMathColor.withOpacity(0.06),
          borderColor:
              blockMathBorderColor ?? effectiveMathColor.withOpacity(0.14),
        ),
      },
      styleSheet: effectiveStyleSheet,
    );
  }
}

MarkdownStyleSheet examMarkdownStyleSheet(
  BuildContext context, {
  double baseFontSize = 15,
  Color? textColor,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final foreground = textColor ?? Colors.black87;
  final muted = Colors.black54;

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
      color: colorScheme.primary,
      fontSize: baseFontSize + 2,
      fontWeight: FontWeight.w900,
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
      backgroundColor: colorScheme.primary.withOpacity(0.07),
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
      color: colorScheme.primary.withOpacity(0.05),
      border: Border(
        left: BorderSide(
          color: colorScheme.primary.withOpacity(0.35),
          width: 4,
        ),
      ),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
    a: TextStyle(
      color: colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: colorScheme.primary.withOpacity(0.45),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(
          color: Colors.black.withOpacity(0.08),
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
    tableBorder: TableBorder.all(color: Colors.black.withOpacity(0.08)),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );
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

String normalizeMarkdownMath(String input) {
  var normalized = input
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r');

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
  return normalized;
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
      ),
      mathStyle: display ? MathStyle.display : MathStyle.text,
      onErrorFallback: (error) {
        return Text(
          display ? '\$\$$formula\$\$' : '\$$formula\$',
          style: (preferredStyle ?? TextStyle(fontSize: baseFontSize)).copyWith(
            color: fallbackColor,
            fontStyle: FontStyle.italic,
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
