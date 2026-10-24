import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';
import '../../shared/urls.dart';

/// Iniciales de un nombre: las de las dos primeras palabras («Tim Robbins» es
/// «TR»). Vacío si no hay letras.
String initialsOf(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  String first(String w) => String.fromCharCode(w.runes.first).toUpperCase();
  return words.length == 1
      ? first(words[0])
      : first(words[0]) + first(words[1]);
}

/// Un color estable para [name]: el mismo nombre da siempre el mismo color.
Color avatarColorOf(String name) {
  var hash = 17;
  for (final rune in name.trim().toLowerCase().runes) {
    hash = (hash * 31 + rune) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.45, 0.35).toColor();
}

/// «Elenco»: fila horizontal de tarjetas con foto (o iniciales), nombre y
/// personaje; debajo, «Dirección» y «Guion».
class CastSection extends StatelessWidget {
  const CastSection({super.key, required this.credits});

  final Credits credits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cast = credits.cast.take(30).toList();
    if (cast.isEmpty && credits.directors.isEmpty && credits.writers.isEmpty) {
      return const SizedBox.shrink();
    }
    Widget line(String label, List<String> names) => Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            TextSpan(text: names.join(', ')),
          ],
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );

    return Column(
      key: const Key('detail-cast'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cast.isNotEmpty) ...[
          Semantics(
            header: true,
            child: Text(
              'Elenco',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          SizedBox(
            height: 156,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cast.length,
                separatorBuilder: (_, _) => const SizedBox(width: Spacing.md),
                itemBuilder: (context, i) => _CastCard(member: cast[i]),
              ),
            ),
          ),
        ],
        if (credits.directors.isNotEmpty) line('Dirección', credits.directors),
        if (credits.writers.isNotEmpty) line('Guion', credits.writers),
      ],
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({required this.member});

  final CastMember member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = member.photoUrl;
    final initials = Text(
      initialsOf(member.name),
      style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
    );
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 72,
            child: ClipOval(
              child: ColoredBox(
                key: Key('cast-avatar-${member.name}'),
                color: avatarColorOf(member.name),
                child: photo != null && isHttpUrl(photo)
                    ? Image.network(
                        photo,
                        key: Key('cast-photo-${member.name}'),
                        fit: BoxFit.cover,
                        cacheWidth: 144,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => Center(child: initials),
                      )
                    : Center(child: initials),
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            member.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge,
          ),
          if (member.character != null)
            Text(
              member.character!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
