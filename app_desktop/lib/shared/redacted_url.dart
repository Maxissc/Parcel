import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

/// Muestra de qué servidor es una URL de addon, sin la ruta ni la query: la
/// URL completa puede tener tokens del usuario, así que nunca se muestra.
class RedactedUrl extends StatelessWidget {
  const RedactedUrl(this.url, {super.key, this.style});

  final String url;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodySmall;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.dns_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            redactAddonUrl(url),
            style: base?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
