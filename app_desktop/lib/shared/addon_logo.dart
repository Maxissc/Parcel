import 'package:flutter/material.dart';

/// Logo de un addon; si no hay o no carga, muestra un ícono genérico.
class AddonLogo extends StatelessWidget {
  const AddonLogo(this.url, {super.key, this.size = 48});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Icon(
      Icons.extension_outlined,
      size: size * 0.5,
      color: scheme.onSurfaceVariant,
    );
    final logoUrl = url;
    final uri = logoUrl == null ? null : Uri.tryParse(logoUrl);
    final loadable =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: loadable
          ? Image.network(
              logoUrl!,
              width: size,
              height: size,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => fallback,
            )
          : fallback,
    );
  }
}
