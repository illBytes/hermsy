import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/image_delivery.dart';
import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// The pictures in a message. One image keeps its own shape (up to
/// [maxHeight] tall); two or more form a two-column grid with 4dp gaps. Tap
/// one to open it full screen with pinch-zoom.
class MessageImageStrip extends StatelessWidget {
  const MessageImageStrip({
    super.key,
    required this.paths,
    this.remotes = const [],
    this.radius = 16,
    this.maxHeight = 320,
  });

  final List<String> paths;
  final List<String> remotes;

  /// Outer corner radius of the image or grid.
  final double radius;

  /// Tallest a single image may be.
  final double maxHeight;

  /// Widest the strip grows, so photos stay photos on wide screens.
  static const maxWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final seenStems = <String>{};
    final items = <_ImageItem>[];

    void add(_ImageItem item) {
      final key = item.local ?? item.remote ?? item.label;
      if (key == null || key.isEmpty) {
        return;
      }
      final stem = imageStem(key);
      if (stem.isNotEmpty && !seenStems.add(stem)) {
        return;
      }
      if (stem.isEmpty && !seenStems.add(key)) {
        return;
      }
      items.add(item);
    }

    for (final path in paths) {
      add(_ImageItem(local: path));
    }
    for (final remote in remotes) {
      if (!shouldShowRemoteImage(remote, localPaths: paths)) {
        continue;
      }
      final name = remote.split('/').last;
      if (remote.startsWith('http') || remote.startsWith('data:')) {
        add(_ImageItem(remote: remote));
      } else {
        add(_ImageItem(label: name.isEmpty ? 'Image' : name));
      }
    }
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    if (items.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: _MessageImage(item: items.single, decodeWidth: maxWidth),
        ),
      );
    }

    const gap = 4.0;
    const tileWidth = (maxWidth - gap) / 2;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      if (i > 0) {
        rows.add(const SizedBox(height: gap));
      }
      final pair = items.skip(i).take(2).toList();
      rows.add(
        pair.length == 2
            ? Row(
                children: [
                  for (var j = 0; j < 2; j++) ...[
                    if (j > 0) const SizedBox(width: gap),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: _Tile(
                          child: _MessageImage(
                            item: pair[j],
                            fill: true,
                            decodeWidth: tileWidth * 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            : AspectRatio(
                aspectRatio: 2,
                child: _Tile(
                  child: _MessageImage(
                    item: pair.single,
                    fill: true,
                    decodeWidth: maxWidth,
                  ),
                ),
              ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xs - 2),
      child: child,
    );
  }
}

class _ImageItem {
  const _ImageItem({this.local, this.remote, this.label});

  final String? local;
  final String? remote;
  final String? label;

  bool get isSvg {
    final path = local ?? remote ?? '';
    return path.toLowerCase().split('?').first.endsWith('.svg');
  }

  bool get hasFile => local != null && File(local!).existsSync();

  bool get hasRemote => remote != null && remote!.startsWith('http');

  bool get canOpen => hasFile || hasRemote;
}

class _MessageImage extends StatelessWidget {
  const _MessageImage({
    required this.item,
    required this.decodeWidth,
    this.fill = false,
  });

  final _ImageItem item;

  /// Logical width to decode at; big camera photos are never decoded at
  /// full resolution for the thread.
  final double decodeWidth;

  /// Cover the whole tile (grid) instead of keeping the image's own size.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final open = item.canOpen ? () => _openViewer(context, item) : null;
    return Semantics(
      image: true,
      button: open != null,
      label: 'Image',
      child: GestureDetector(
        onTap: open,
        child: fill ? SizedBox.expand(child: _image(context)) : _image(context),
      ),
    );
  }

  Widget _image(BuildContext context) {
    final cacheWidth = (decodeWidth * MediaQuery.devicePixelRatioOf(context)).round();
    final fit = fill ? BoxFit.cover : BoxFit.contain;
    if (item.hasFile) {
      final file = File(item.local!);
      return item.isSvg
          ? SvgPicture.file(file, fit: BoxFit.contain)
          : Image.file(
              file,
              fit: fit,
              cacheWidth: cacheWidth,
              frameBuilder: _fadeIn,
              errorBuilder: _broken,
            );
    }
    if (item.hasRemote) {
      final remote = item.remote!;
      return item.isSvg
          ? SvgPicture.network(remote, fit: BoxFit.contain)
          : Image.network(
              remote,
              fit: fit,
              cacheWidth: cacheWidth,
              frameBuilder: _fadeIn,
              errorBuilder: _broken,
            );
    }
    if (item.label != null) {
      return _Placeholder(label: item.label!, fill: fill);
    }
    return _broken(context, null, null);
  }

  Widget _fadeIn(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) {
      return child;
    }
    if (frame == null && !fill) {
      return SizedBox(
        width: 220,
        height: 160,
        child: ColoredBox(color: AppColors.surface),
      );
    }
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: AppMotion.short,
      curve: AppMotion.standard,
      child: child,
    );
  }

  Widget _broken(BuildContext context, Object? error, StackTrace? stack) {
    return ColoredBox(
      color: AppColors.surface,
      child: SizedBox(
        width: fill ? double.infinity : 160,
        height: fill ? double.infinity : 110,
        child: Icon(
          Icons.broken_image_rounded,
          color: AppColors.hint,
          size: 22,
        ),
      ),
    );
  }
}

/// A delivered image we only know by name (no file on this phone yet).
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label, required this.fill});

  final String label;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fill ? double.infinity : 200,
      height: fill ? double.infinity : 120,
      color: AppColors.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_rounded, color: AppColors.hint, size: 22),
          const SizedBox(height: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
          ),
        ],
      ),
    );
  }
}

void _openViewer(BuildContext context, _ImageItem item) {
  final reduced = AppMotion.reduced(context);
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Close image',
      transitionDuration: AppMotion.medium,
      reverseTransitionDuration: AppMotion.short,
      pageBuilder: (context, animation, secondary) => _ImageViewer(item: item),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.enter,
          reverseCurve: AppMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: reduced
              ? child
              : ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                  child: child,
                ),
        );
      },
    ),
  );
}

/// Full-screen viewer: near-black glass, pinch to zoom, tap or X to close.
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.item});

  final _ImageItem item;

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (item.hasFile) {
      final file = File(item.local!);
      image = item.isSvg
          ? SvgPicture.file(file, fit: BoxFit.contain)
          : Image.file(file, fit: BoxFit.contain);
    } else {
      final remote = item.remote!;
      image = item.isSvg
          ? SvgPicture.network(remote, fit: BoxFit.contain)
          : Image.network(remote, fit: BoxFit.contain);
    }
    return Material(
      color: AppColors.background.withValues(alpha: 0.96),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: SafeArea(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(child: image),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                // An opaque scrim disc: a bright or zoomed image can reach
                // the corner, and a faint white disc would vanish over it.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.background.withValues(alpha: 0.6),
                    border: Border.all(color: AppColors.strokeStrong),
                  ),
                  child: FrankIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    color: AppColors.text,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
