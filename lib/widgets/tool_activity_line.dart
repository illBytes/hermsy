import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Turns a Hermes tool line ("🔍 web search: weather Lagos…") into calm
/// status copy ("Web search · weather Lagos"), the same wording the tool
/// chip, the header and the drawer use.
String cleanToolLabel(String? raw) => ToolLabel.parse(raw ?? '').text;

/// A Hermes tool line ("🔍 Web search: weather Lagos…") split into the parts
/// the UI shows: the emoji (if Hermes sent one), a fitting icon, and a calm
/// label without the trailing ellipsis ("Web search · weather Lagos").
class ToolLabel {
  const ToolLabel({required this.text, required this.icon, this.emoji});

  factory ToolLabel.parse(String raw) {
    var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    String? emoji;
    if (text.isNotEmpty) {
      final first = text.characters.first;
      if (_isSymbol(first)) {
        emoji = first;
        text = text.substring(first.length).trim();
      }
    }
    while (text.endsWith('…') || text.endsWith('...')) {
      text = text.endsWith('…')
          ? text.substring(0, text.length - 1)
          : text.substring(0, text.length - 3);
      text = text.trimRight();
    }
    final colon = text.indexOf(': ');
    if (colon > 0) {
      text =
          '${text.substring(0, colon)} · ${text.substring(colon + 2).trim()}';
    }
    // Anything else in front of the words ("- ", a second symbol).
    text = text.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '');
    if (text.isEmpty) {
      text = 'Working';
    } else {
      text = '${text[0].toUpperCase()}${text.substring(1)}';
    }
    return ToolLabel(text: text, emoji: emoji, icon: _iconFor(text));
  }

  /// "Web search · weather Lagos".
  final String text;

  /// The emoji Hermes put in front of the line, if any.
  final String? emoji;

  /// A Material icon for the tool, used when there is no emoji.
  final IconData icon;

  static bool _isSymbol(String grapheme) {
    final rune = grapheme.runes.first;
    if (rune < 0x2190) {
      return false;
    }
    return !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(grapheme);
  }

  static IconData _iconFor(String text) {
    final value = text.toLowerCase();
    bool has(List<String> words) => words.any(value.contains);
    if (has(['search', 'lookup', 'find'])) {
      return Icons.travel_explore_rounded;
    }
    if (has(['terminal', 'shell', 'exec', 'command', 'bash', 'run '])) {
      return Icons.terminal_rounded;
    }
    if (has(['write', 'edit', 'patch', 'save'])) {
      return Icons.edit_note_rounded;
    }
    if (has(['read', 'file', 'document', 'pdf'])) {
      return Icons.description_rounded;
    }
    if (has(['browser', 'browse', 'fetch', 'web', 'url', 'http', 'page'])) {
      return Icons.language_rounded;
    }
    if (has(['image', 'vision', 'photo', 'draw', 'picture'])) {
      return Icons.image_rounded;
    }
    if (has(['memory', 'remember', 'recall'])) {
      return Icons.psychology_rounded;
    }
    return Icons.build_rounded;
  }
}

/// The live tool chip: a 24dp glass capsule with the tool's emoji or icon,
/// its cleaned label, and a softly pulsing ion dot while it runs.
class ToolActivityLine extends StatelessWidget {
  const ToolActivityLine({super.key, required this.label});

  /// The raw Hermes tool line.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tool = ToolLabel.parse(label);
    return Semantics(
      liveRegion: true,
      label: 'Using ${tool.text}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
        decoration: BoxDecoration(
          color: AppColors.veil(0x0A),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tool.emoji != null)
              Text(
                tool.emoji!,
                style: const TextStyle(fontSize: 12, height: 1.2),
              )
            else
              Icon(tool.icon, size: 14, color: AppColors.secondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tool.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: AppColors.text),
              ),
            ),
            const SizedBox(width: 8),
            const _PulseDot(),
          ],
        ),
      ),
    );
  }
}

/// A finished tool step: "✓ Read file · notes.md" in the quiet hint color.
class ToolTrailLine extends StatelessWidget {
  const ToolTrailLine({super.key, required this.label});

  /// The raw Hermes tool line.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tool = ToolLabel.parse(label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.check_rounded, size: 14, color: AppColors.hint),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tool.emoji == null ? tool.text : '${tool.emoji} ${tool.text}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: AppColors.hint),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: 6,
        child: CustomPaint(painter: _PulseDotPainter(_pulse)),
      ),
    );
  }
}

class _PulseDotPainter extends CustomPainter {
  _PulseDotPainter(this.pulse) : super(repaint: pulse);

  final Animation<double> pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeInOut.transform(pulse.value);
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      size.width * (0.9 + t * 0.5),
      Paint()
        ..color = AppColors.ion.withValues(alpha: 0.10 + t * 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      center,
      size.width / 2,
      Paint()..color = AppColors.ion.withValues(alpha: 0.55 + t * 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant _PulseDotPainter oldDelegate) {
    return oldDelegate.pulse != pulse;
  }
}
