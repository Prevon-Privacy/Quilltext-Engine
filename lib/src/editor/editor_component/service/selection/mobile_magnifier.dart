import 'package:flutter/material.dart';

class MobileMagnifier extends StatelessWidget {
  const MobileMagnifier({
    super.key,
    required this.size,
    required this.offset,
    this.bounds,
  });

  final Size size;
  final Offset offset;

  /// PREVON PATCH 24: the area the lens must stay inside (the editor's own
  /// size). Without it the lens slid half off screen at the edges and over the
  /// top, where it vanished exactly when the finger was highest. The lens is
  /// pinned inside, and its focal point keeps pointing at the finger.
  final Size? bounds;

  @override
  Widget build(BuildContext context) {
    // the magnifier will blink if the center is the same as the offset.
    final magicOffset = Offset(0, size.height - 22);
    var center = offset - magicOffset;
    final area = bounds;
    if (area != null &&
        area.width >= size.width &&
        area.height >= size.height) {
      const margin = 4.0;
      center = Offset(
        center.dx.clamp(
          size.width / 2 + margin,
          (area.width - size.width / 2 - margin)
              .clamp(size.width / 2 + margin, double.infinity),
        ),
        center.dy.clamp(size.height / 2 + margin, double.infinity),
      );
    }
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      ),
      child: IgnorePointer(
        child: _CustomMagnifier(
          size: size,
          // Still aimed at the finger however far the lens was pinned.
          additionalFocalPointOffset: offset - center,
        ),
      ),
    );
  }
}

class _CustomMagnifier extends StatelessWidget {
  const _CustomMagnifier({
    this.additionalFocalPointOffset = Offset.zero,
    required this.size,
  });

  final Size size;
  final Offset additionalFocalPointOffset;

  @override
  Widget build(BuildContext context) {
    return RawMagnifier(
      decoration: const MagnifierDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(40)),
        ),
        shadows: <BoxShadow>[
          BoxShadow(
            blurRadius: 1.5,
            offset: Offset(0, 2),
            spreadRadius: 0.75,
            color: Color.fromARGB(25, 0, 0, 0),
          ),
        ],
      ),
      magnificationScale: 1.25,
      focalPointOffset: additionalFocalPointOffset,
      size: size,
      child: const ColoredBox(
        color: Color.fromARGB(8, 158, 158, 158),
      ),
    );
  }
}
