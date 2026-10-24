import 'package:flutter/material.dart';

/// Caja gris que late despacio: ocupa el lugar de algo que todavía carga.
///
/// Si [width] es `null` ocupa todo el ancho disponible.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Opacity(
          opacity: 0.35 + 0.35 * Curves.easeInOut.transform(_controller.value),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
        ),
      ),
    );
  }
}
