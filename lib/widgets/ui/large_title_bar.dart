import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// A pinned header whose large title (28) settles into the toolbar (18) as
/// the page scrolls. Once content slides beneath it, the bar frosts over
/// with a bottom hairline. It shows a [BackButton] when the route can pop.
///
/// Shared by Settings, server settings, and the inbox.
class LargeTitleSliverBar extends StatelessWidget {
  const LargeTitleSliverBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SliverPersistentHeader(
      pinned: true,
      delegate: _LargeTitleDelegate(
        title: title,
        topInset: media.padding.top,
        textScaler: media.textScaler.clamp(maxScaleFactor: 1.35),
        canPop: ModalRoute.of(context)?.impliesAppBarDismissal ?? false,
        overlayStyle:
            Theme.of(context).appBarTheme.systemOverlayStyle ??
            SystemUiOverlayStyle.light,
      ),
    );
  }
}

class _LargeTitleDelegate extends SliverPersistentHeaderDelegate {
  _LargeTitleDelegate({
    required this.title,
    required this.topInset,
    required this.textScaler,
    required this.canPop,
    required this.overlayStyle,
  }) : _largeRow = (textScaler.scale(_largeSize) * 1.21 + 20).ceilToDouble();

  final String title;
  final double topInset;
  final TextScaler textScaler;
  final bool canPop;
  final SystemUiOverlayStyle overlayStyle;
  final double _largeRow;

  static const _toolbar = 56.0;
  static const _largeSize = 28.0;
  static const _smallSize = 18.0;
  static const _gutter = AppSpace.reading;

  /// Scroll distance over which the bar frosts once content is beneath it.
  static const _frostRun = 16.0;

  @override
  double get minExtent => topInset + _toolbar;

  @override
  double get maxExtent => topInset + _toolbar + _largeRow;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final t = (shrinkOffset / range).clamp(0.0, 1.0);
    final frost = ((shrinkOffset - range) / _frostRun).clamp(0.0, 1.0);

    final left = ui.lerpDouble(_gutter, canPop ? 60 : _gutter, t)!;
    final centerY = ui.lerpDouble(
      topInset + _toolbar + _largeRow / 2 - 4,
      topInset + _toolbar / 2,
      t,
    )!;
    final scale = ui.lerpDouble(1, _smallSize / _largeSize, t)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (frost > 0) _Frost(amount: frost),
          Positioned(
            left: left,
            right: _gutter,
            top: centerY,
            child: FractionalTranslation(
              translation: const Offset(0, -0.5),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.centerLeft,
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: textScaler,
                    style: AppText.largeTitle,
                  ),
                ),
              ),
            ),
          ),
          if (canPop)
            Positioned(
              top: topInset,
              left: AppSpace.x1,
              height: _toolbar,
              child: const Center(child: BackButton()),
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LargeTitleDelegate oldDelegate) {
    return oldDelegate.title != title ||
        oldDelegate.topInset != topInset ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.canPop != canPop ||
        oldDelegate.overlayStyle != overlayStyle;
  }
}

/// Frosted canvas behind the collapsed bar, with its bottom hairline.
class _Frost extends StatelessWidget {
  const _Frost({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24 * amount, sigmaY: 24 * amount),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.74 * amount),
            border: Border(
              bottom: BorderSide(
                color: AppColors.hairline.withValues(
                  alpha: AppColors.hairline.a * amount,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
