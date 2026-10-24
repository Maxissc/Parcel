import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';

/// De dónde sale lo que se está viendo y qué es, para el panel de datos.
/// Nunca lleva URLs.
class PlayerInfo {
  const PlayerInfo({
    this.addonName,
    this.streamName,
    this.atmos = false,
    this.imdbRating,
    this.year,
    this.runtime,
    this.genres = const [],
  });

  final String? addonName;
  final String? streamName;

  /// El título del stream dice Atmos.
  final bool atmos;
  final String? imdbRating;
  final String? year;
  final String? runtime;
  final List<String> genres;
}

/// «2.0», «5.1», «7.1»... según la cantidad de canales.
String channelsLabel(int channels) => switch (channels) {
  1 => '1.0',
  2 => '2.0',
  6 => '5.1',
  8 => '7.1',
  _ => '$channels canales',
};

/// «4K» o «1080p» según el alto real del video.
String? videoResolutionLabel(PlaybackStats s) {
  final h = s.videoHeight;
  final w = s.videoWidth;
  if (h == null || h <= 0) return null;
  if (h >= 2000 || (w ?? 0) >= 3600) return '4K';
  return '${h}p';
}

/// Chips cortos para los controles: «4K · HDR · 5.1 · 24 fps».
List<String> statsChips(PlaybackStats s, {bool atmos = false}) {
  final fps = s.fps;
  final channels = s.audioChannels;
  return [
    ?videoResolutionLabel(s),
    ?s.dynamicRange.shortLabel,
    if (channels != null && channels > 0)
      atmos ? '${channelsLabel(channels)} Atmos' : channelsLabel(channels),
    if (fps != null && fps > 0) '${fps.round()} fps',
  ];
}

String _decimal(double v, [int digits = 1]) =>
    v.toStringAsFixed(digits).replaceAll('.', ',');

String _bitrate(int bitsPerSecond) {
  final mbps = bitsPerSecond / 1000000;
  return mbps >= 1
      ? '${_decimal(mbps)} Mb/s'
      : '${(bitsPerSecond / 1000).round()} kb/s';
}

/// Panel lateral con todos los datos técnicos (tecla I).
class InfoPanel extends StatelessWidget {
  const InfoPanel({
    super.key,
    required this.stats,
    required this.info,
    required this.onClose,
  });

  final PlaybackStats stats;
  final PlayerInfo? info;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = stats;
    final info = this.info;
    final width = s.videoWidth;
    final height = s.videoHeight;
    final channels = s.audioChannels;
    final rows = <(String, List<(String, String?)>)>[
      (
        'Video',
        [
          (
            'Resolución',
            width != null && height != null ? '$width×$height' : null,
          ),
          ('FPS', s.fps == null ? null : _decimal(s.fps!, 2)),
          ('Códec', s.videoCodec),
          (
            'Rango dinámico',
            switch (s.dynamicRange) {
              DynamicRange.sdr => 'SDR',
              DynamicRange.hdr10 => 'HDR10',
              DynamicRange.hlg => 'HLG',
              DynamicRange.dolbyVision => 'Dolby Vision',
            },
          ),
          (
            'Decodificación',
            s.hardwareDecoder == null
                ? 'Software'
                : 'Hardware (${s.hardwareDecoder})',
          ),
          (
            'Bitrate',
            s.videoBitrate == null ? null : _bitrate(s.videoBitrate!),
          ),
        ],
      ),
      (
        'Audio',
        [
          ('Códec', s.audioCodec),
          (
            'Canales',
            channels == null
                ? null
                : '${channelsLabel(channels)}${info?.atmos == true ? ' · Atmos' : ''}',
          ),
        ],
      ),
      (
        'Caché',
        [
          ('Adelante', '${s.bufferAhead.inSeconds} s'),
          ('Atrás', '${s.bufferBehind.inSeconds} s'),
          ('Nivel', s.cacheLevel),
        ],
      ),
      if (info != null)
        ('Fuente', [('Addon', info.addonName), ('Stream', info.streamName)]),
      if (info != null)
        (
          'Contenido',
          [
            ('IMDb', info.imdbRating == null ? null : '★ ${info.imdbRating}'),
            ('Año', info.year),
            ('Duración', info.runtime),
            ('Géneros', info.genres.isEmpty ? null : info.genres.join(', ')),
          ],
        ),
    ];

    return Material(
      key: const Key('player-info-panel'),
      color: Colors.black.withValues(alpha: 0.88),
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
      child: SizedBox(
        width: 340,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Información (I)',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  0,
                  Spacing.md,
                  Spacing.md,
                ),
                children: [
                  for (final (title, items) in rows) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.md),
                      child: Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    for (final (label, value) in items)
                      if (value != null && value.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 110,
                                child: Text(
                                  label,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  value,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
