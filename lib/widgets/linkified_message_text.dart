import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Exibe URLs no texto como links e entrega a abertura ao sistema operacional.
///
/// Links universais do Instagram e do YouTube são encaminhados ao aplicativo
/// instalado. Quando ele não existe, o próprio sistema usa o navegador.
class LinkifiedMessageText extends StatefulWidget {
  const LinkifiedMessageText({
    super.key,
    required this.text,
    required this.style,
    required this.linkStyle,
    this.onOpenError,
  });

  final String text;
  final TextStyle style;
  final TextStyle linkStyle;
  final VoidCallback? onOpenError;

  @override
  State<LinkifiedMessageText> createState() => _LinkifiedMessageTextState();
}

class _LinkifiedMessageTextState extends State<LinkifiedMessageText> {
  static final RegExp _urlPattern = RegExp(
    r'(?:(?:https?://)|(?:www\.)|(?:instagram\.com/)|(?:youtube\.com/)|(?:youtu\.be/))[^\s<>]+',
    caseSensitive: false,
  );
  static final RegExp _trailingPunctuation = RegExp(r'[.,!?;:)}\]]+$');

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Uri? _normalizedUri(String value) {
    final hasScheme = value.toLowerCase().startsWith('http://') ||
        value.toLowerCase().startsWith('https://');
    final withScheme = hasScheme ? value : 'https://$value';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
      return null;
    }
    return uri;
  }

  Future<void> _open(String value) async {
    final uri = _normalizedUri(value);
    if (uri == null) {
      widget.onOpenError?.call();
      return;
    }

    try {
      // externalApplication mantém o comportamento de Universal Links/App
      // Links: Instagram/YouTube abrem no app; sem app, abrem no navegador.
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) widget.onOpenError?.call();
    } catch (_) {
      widget.onOpenError?.call();
    }
  }

  List<InlineSpan> _buildSpans() {
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _urlPattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }

      final rawMatch = match.group(0)!;
      final trailing = _trailingPunctuation.stringMatch(rawMatch) ?? '';
      final link = trailing.isEmpty
          ? rawMatch
          : rawMatch.substring(0, rawMatch.length - trailing.length);
      final recognizer = TapGestureRecognizer()..onTap = () => _open(link);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(text: link, style: widget.linkStyle, recognizer: recognizer),
      );
      if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
      cursor = match.end;
    }

    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(style: widget.style, children: _buildSpans()));
  }
}
