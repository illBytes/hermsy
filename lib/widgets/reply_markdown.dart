import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../services/reply_markdown_prep.dart';
import '../theme/app_theme.dart';
import 'reply_code_block.dart';
import 'ui/frank_ui.dart';

/// Frank's reply text, typeset like a document.
///
/// The reply is split into blocks at blank lines outside code fences and
/// each block is its own [MarkdownBody], so while Frank streams only the
/// last block is parsed again; finished paragraphs stay as they are. While
/// [streaming], an aurora caret rides the end of the text.
class ReplyMarkdown extends StatefulWidget {
  const ReplyMarkdown({
    super.key,
    required this.data,
    this.error = false,
    this.streaming = false,
    this.style,
  });

  final String data;
  final bool error;
  final bool streaming;

  /// Paragraph style. Defaults to [AppText.body]; headings, lists and code
  /// scale from it (the reader passes a larger size).
  final TextStyle? style;

  @override
  State<ReplyMarkdown> createState() => _ReplyMarkdownState();
}

class _ReplyMarkdownState extends State<ReplyMarkdown>
    with TickerProviderStateMixin {
  /// Fades the caret in when words start and out when the reply lands.
  late final AnimationController _caret = AnimationController(
    vsync: this,
    duration: AppMotion.short,
  )..addStatusListener(_onCaretStatus);

  /// One blink cycle. Restarted on every new chunk, so the caret holds solid
  /// while words flow and only blinks when Frank pauses.
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  late final Animation<double> _blinkOpacity = _blink.drive(
    TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1), weight: 42),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0.12,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 24,
      ),
      TweenSequenceItem(tween: ConstantTween(0.12), weight: 10),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.12,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 24,
      ),
    ]),
  );

  String? _source;
  List<String> _blocks = const [];

  bool get _showCaret => widget.streaming || _caret.value > 0;

  @override
  void initState() {
    super.initState();
    if (widget.streaming) {
      _caret.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBlink();
  }

  @override
  void didUpdateWidget(covariant ReplyMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming != oldWidget.streaming) {
      if (widget.streaming) {
        _caret.forward();
      } else {
        _caret.reverse();
      }
    }
    if (widget.streaming && widget.data != oldWidget.data) {
      _blink.value = 0;
    }
    _syncBlink();
  }

  void _syncBlink() {
    final run = widget.streaming && !AppMotion.reduced(context);
    if (run && !_blink.isAnimating) {
      _blink.repeat();
    } else if (!run && _blink.isAnimating) {
      _blink
        ..stop()
        ..value = 0;
    }
  }

  void _onCaretStatus(AnimationStatus status) {
    // Drop the caret from the text once it has faded out.
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _caret.dispose();
    _blink.dispose();
    super.dispose();
  }

  List<String> _blocksFor(String data) {
    if (!identical(data, _source) && data != _source) {
      _source = data;
      _blocks = splitReplyBlocks(prepareReplyMarkdown(data));
    }
    return _blocks;
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? AppText.body;
    final sheet = _ReplyStyles.sheet(base, widget.error);
    final blocks = List<String>.of(_blocksFor(widget.data));
    final caret = _showCaret;
    if (caret) {
      if (blocks.isEmpty) {
        blocks.add(caretMark);
      } else {
        blocks[blocks.length - 1] = withCaret(blocks.last);
      }
    }

    final builders = <String, MarkdownElementBuilder>{
      'pre': _PreBuilder(),
      'code': _InlineCodeBuilder(base, widget.error),
      if (caret)
        _CaretSyntax.tag: _CaretBuilder(
          FadeTransition(
            opacity: _caret,
            child: FadeTransition(
              opacity: _blinkOpacity,
              child: const _AuroraCaret(),
            ),
          ),
        ),
    };

    Widget body(String data) {
      return MarkdownBody(
        data: data,
        selectable: false,
        softLineBreak: true,
        styleSheet: sheet,
        builders: builders,
        inlineSyntaxes: caret ? [_CaretSyntax()] : null,
        bulletBuilder: (parameters) => _Bullet(parameters, base),
        checkboxBuilder: (checked) => _Checkbox(checked, base),
        onTapLink: (text, href, title) => _openLink(context, href),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _blockGap),
            child: body(blocks[i]),
          ),
      ],
    );
  }
}

/// Space between blocks (paragraphs, lists, code). Inside a block, list
/// items and lines sit closer ([MarkdownStyleSheet.blockSpacing]).
const _blockGap = 12.0;

/// The private-use character that marks where the streaming caret goes.
const caretMark = '\uE000';

/// Appends [caretMark] to [block]: inline at the end of the last line when
/// that line is prose, or on its own line after code, tables, headings and
/// rules, where text glued to the end would change what the line means.
String withCaret(String block) {
  var text = block;
  while (text.endsWith('\n') || text.endsWith('\r')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.trim().isEmpty) {
    return caretMark;
  }
  final lastLine = text.substring(text.lastIndexOf('\n') + 1);
  return _inlineCaretFits(lastLine) ? '$text$caretMark' : '$text\n\n$caretMark';
}

final _ruleLine = RegExp(r'^ {0,3}([-*_=])[ \t]*(\1[ \t]*)+$');
final _headingLine = RegExp(r'^ {0,3}#{1,6}(\s|$)');
final _fenceLine = RegExp(r'^\s*(`{3,}|~{3,})');

bool _inlineCaretFits(String line) {
  if (line.trim().isEmpty) {
    return false;
  }
  if (line.startsWith('    ') || line.startsWith('\t')) {
    return false;
  }
  final trimmed = line.trimLeft();
  return !_ruleLine.hasMatch(line) &&
      !_headingLine.hasMatch(line) &&
      !_fenceLine.hasMatch(line) &&
      !trimmed.startsWith('|');
}

/// Splits prepared reply markdown into blocks that render the same on their
/// own as they do together: at blank lines, never inside a code fence, and
/// keeping indented continuations and runs of list items with the block
/// they belong to (so lists keep their numbering and nesting).
///
/// Link reference definitions and footnotes refer across blocks, so text
/// that has them stays one block.
List<String> splitReplyBlocks(String text) {
  if (_crossReference.hasMatch(text)) {
    return text.trim().isEmpty ? const [] : [text];
  }
  final chunks = <List<String>>[];
  var current = <String>[];
  String? fenceChar;
  var fenceLength = 0;
  var fenceIndent = 0;

  for (final line in text.split('\n')) {
    final fence = _fenceLine.firstMatch(line);
    if (fenceChar == null) {
      if (fence != null) {
        final marker = fence.group(1)!;
        fenceChar = marker[0];
        fenceLength = marker.length;
        fenceIndent = line.length - line.trimLeft().length;
      } else if (line.trim().isEmpty) {
        if (current.isNotEmpty) {
          chunks.add(current);
          current = <String>[];
        }
        continue;
      }
    } else if (fence != null) {
      final marker = fence.group(1)!;
      final indent = line.length - line.trimLeft().length;
      final rest = line.trimLeft().substring(marker.length).trim();
      if (marker[0] == fenceChar &&
          marker.length >= fenceLength &&
          rest.isEmpty &&
          indent <= fenceIndent + 3) {
        fenceChar = null;
      }
    }
    current.add(line);
  }
  if (current.isNotEmpty) {
    chunks.add(current);
  }

  final blocks = <List<String>>[];
  for (final chunk in chunks) {
    if (blocks.isNotEmpty && _belongsToPrevious(blocks.last, chunk)) {
      blocks.last
        ..add('')
        ..addAll(chunk);
    } else {
      blocks.add(chunk);
    }
  }
  return [for (final block in blocks) block.join('\n')];
}

final _crossReference = RegExp(r'^ {0,3}\[[^\]\n]+\]:\s*\S', multiLine: true);
final _listItem = RegExp(r'^ {0,3}([-+*]|\d{1,9}[.)])(\s|$)');

bool _belongsToPrevious(List<String> previous, List<String> chunk) {
  final first = chunk.first;
  if (first.startsWith(' ') || first.startsWith('\t')) {
    return true;
  }
  final marker = _listItem.firstMatch(first);
  if (marker == null) {
    return false;
  }
  for (var i = previous.length - 1; i >= 0; i--) {
    final line = previous[i];
    if (line.trim().isEmpty || line.startsWith(' ') || line.startsWith('\t')) {
      continue;
    }
    // A loose list continues; a list of the other kind starts afresh.
    final last = _listItem.firstMatch(line);
    return last != null && _ordered(last) == _ordered(marker);
  }
  return false;
}

bool _ordered(Match marker) => !'-+*'.contains(marker.group(1)!);

/// One shared style sheet per base style, so an unchanged block never
/// re-parses just because its parent rebuilt.
class _ReplyStyles {
  static final _cache = <(TextStyle, bool), MarkdownStyleSheet>{};

  static MarkdownStyleSheet sheet(TextStyle base, bool error) {
    return _cache.putIfAbsent((base, error), () => _build(base, error));
  }

  static MarkdownStyleSheet _build(TextStyle style, bool error) {
    final size = style.fontSize ?? 16;
    final base = error ? style.copyWith(color: AppColors.danger) : style;
    final strong = base.color ?? AppColors.text;
    return MarkdownStyleSheet(
      p: base,
      pPadding: EdgeInsets.zero,
      h1: base.copyWith(
        fontSize: size * 1.375,
        height: 1.3,
        fontWeight: const FontWeight(650),
        letterSpacing: -0.4,
        color: strong,
      ),
      h2: base.copyWith(
        fontSize: size * 1.1875,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
        color: strong,
      ),
      h3: base.copyWith(
        fontSize: size * 1.0625,
        height: 1.4,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: strong,
      ),
      h4: base.copyWith(fontWeight: FontWeight.w600, color: strong),
      h5: base.copyWith(fontWeight: FontWeight.w600, color: strong),
      h6: base.copyWith(
        fontWeight: FontWeight.w600,
        color: error ? AppColors.danger : AppColors.secondary,
      ),
      h1Padding: const EdgeInsets.only(top: 6, bottom: 2),
      h2Padding: const EdgeInsets.only(top: 4, bottom: 2),
      h3Padding: const EdgeInsets.only(top: 2),
      em: base.copyWith(fontStyle: FontStyle.italic),
      strong: base.copyWith(fontWeight: FontWeight.w600, color: strong),
      del: base.copyWith(
        decoration: TextDecoration.lineThrough,
        decorationColor: AppColors.hint,
        color: error ? AppColors.danger : AppColors.secondary,
      ),
      a: base.copyWith(
        color: AppColors.link,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.link.withValues(alpha: 0.4),
      ),
      code: AppText.code.copyWith(fontSize: size * 0.875),
      blockquote: base.copyWith(
        color: error ? AppColors.danger : AppColors.secondary,
      ),
      blockquoteDecoration: const _QuoteBar(),
      blockquotePadding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
      blockSpacing: 6,
      listIndent: 20,
      listBullet: base,
      listBulletPadding: const EdgeInsets.only(right: 6),
      checkbox: base,
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      tableHead: base.copyWith(
        fontSize: size * 0.9,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: strong,
      ),
      tableBody: base.copyWith(fontSize: size * 0.9, height: 1.45),
      tableBorder: TableBorder(
        top: BorderSide(color: AppColors.hairline),
        bottom: BorderSide(color: AppColors.hairline),
        horizontalInside: BorderSide(color: AppColors.hairline),
      ),
      tableHeadCellsDecoration: BoxDecoration(color: AppColors.veil(0x08)),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableScrollbarThumbVisibility: false,
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      tableVerticalAlignment: TableCellVerticalAlignment.top,
    );
  }
}

/// List markers: iris dots (rings when nested) and mono hint numbers. Built
/// as text so they sit on the first line's baseline at any text scale.
class _Bullet extends StatelessWidget {
  const _Bullet(this.parameters, this.base);

  final MarkdownBulletParameters parameters;
  final TextStyle base;

  @override
  Widget build(BuildContext context) {
    if (parameters.style == BulletStyle.orderedList) {
      return Text(
        '${parameters.index + 1}.',
        textAlign: TextAlign.right,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: base.copyWith(
          fontFamily: AppText.mono,
          fontFamilyFallback: AppText.monoFallback,
          fontSize: (base.fontSize ?? 16) * 0.875,
          color: AppColors.hint,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    final nested = parameters.nestLevel > 0;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: nested ? null : AppColors.iris,
                border: nested
                    ? Border.all(
                        color: AppColors.iris.withValues(alpha: 0.8),
                        width: 1.2,
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      textAlign: TextAlign.right,
      style: base,
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox(this.checked, this.base);

  final bool checked;
  final TextStyle base;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: checked ? AppColors.iris.withValues(alpha: 0.22) : null,
                borderRadius: BorderRadius.circular(AppRadii.xs - 1),
                border: Border.all(
                  color: checked
                      ? AppColors.iris.withValues(alpha: 0.7)
                      : AppColors.strokeStrong,
                ),
              ),
              child: checked
                  ? Icon(Icons.check_rounded, size: 12, color: AppColors.text)
                  : null,
            ),
          ),
        ],
      ),
      style: base,
    );
  }
}

/// The 2dp ion→iris rule beside a blockquote.
class _QuoteBar extends Decoration {
  const _QuoteBar();

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _QuoteBarPainter();
}

class _QuoteBarPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.height <= 0) {
      return;
    }
    final rect = Rect.fromLTWH(offset.dx, offset.dy, 2, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(1)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ion, AppColors.iris],
        ).createShader(rect),
    );
  }
}

/// Fenced code goes to [ReplyCodeBlock].
class _PreBuilder extends MarkdownElementBuilder {
  _PreBuilder();

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = '';
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final cls = child.attributes['class'] ?? '';
        if (cls.startsWith('language-')) {
          language = cls.substring('language-'.length);
        }
        break;
      }
    }
    var code = element.textContent.replaceAll(caretMark, '');
    if (code.endsWith('\n')) {
      code = code.substring(0, code.length - 1);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ReplyCodeBlock(code: code, language: language),
    );
  }
}

/// Inline `code` as a small rounded mono chip that stays on the line.
class _InlineCodeBuilder extends MarkdownElementBuilder {
  _InlineCodeBuilder(this.base, this.error);

  final TextStyle base;
  final bool error;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final size = (base.fontSize ?? 16) * 0.875;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.veil(0x0F),
                borderRadius: BorderRadius.circular(AppRadii.xs),
              ),
              child: Text(
                element.textContent.replaceAll(caretMark, ''),
                style: AppText.code.copyWith(
                  fontSize: size,
                  height: 1.3,
                  color: error ? AppColors.danger : AppText.code.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Turns [caretMark] into a `caret` element.
class _CaretSyntax extends md.InlineSyntax {
  _CaretSyntax() : super(caretMark, startCharacter: caretMark.codeUnitAt(0));

  static const tag = 'frank-caret';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty(tag));
    return true;
  }
}

/// Places the caret inside the line's text so it rides the last word.
class _CaretBuilder extends MarkdownElementBuilder {
  _CaretBuilder(this.caret);

  final Widget caret;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: caret),
        ],
      ),
    );
  }
}

/// A 2x16dp bar in the vertical aurora gradient with a soft glow.
class _AuroraCaret extends StatelessWidget {
  const _AuroraCaret();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 1),
      child: Container(
        width: 2,
        height: 16,
        decoration: BoxDecoration(
          gradient: AppGradients.auroraVertical,
          borderRadius: BorderRadius.circular(1),
          boxShadow: [
            BoxShadow(
              color: AppColors.azure.withValues(alpha: 0.55),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

/// Links open a small sheet; there is no browser hand-off in this build, so
/// the action is to copy the address.
void _openLink(BuildContext context, String? href) {
  final url = href?.trim() ?? '';
  if (url.isEmpty) {
    return;
  }
  final host = Uri.tryParse(url)?.host ?? '';
  final shown = url.length > 280 ? '${url.substring(0, 280)}…' : url;
  showFrankSheet<void>(
    context,
    builder: (sheetContext) {
      return FrankSheet(
        title: host.isEmpty ? 'Link' : host,
        subtitle: shown,
        children: [_CopyLinkRow(url: url)],
      );
    },
  );
}

/// 'Copy link' confirms in place ('Link copied' with an ion check), then
/// closes the sheet: no snackbar landing on the composer.
class _CopyLinkRow extends StatefulWidget {
  const _CopyLinkRow({required this.url});

  final String url;

  @override
  State<_CopyLinkRow> createState() => _CopyLinkRowState();
}

class _CopyLinkRowState extends State<_CopyLinkRow> {
  Timer? _close;
  var _copied = false;

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  void _copy() {
    if (_copied) {
      return;
    }
    Clipboard.setData(ClipboardData(text: widget.url));
    setState(() => _copied = true);
    _close = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SheetRow(
      icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
      iconColor: _copied ? AppColors.ion : null,
      label: _copied ? 'Link copied' : 'Copy link',
      onTap: _copy,
    );
  }
}
