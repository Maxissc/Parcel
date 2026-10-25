import 'package:parcel_core/parcel_core.dart';

import '../../playback/playback_errors.dart';

/// Texto de una pista para los menús: título e idioma si los hay, o «Pista N».
///
/// [index] cuenta desde cero y solo se usa si la pista no trae datos.
String trackLabel(PlaybackTrack track, int index) {
  final title = track.title?.trim();
  final language = track.language?.trim();
  final hasTitle = title != null && title.isNotEmpty;
  // `und` es «idioma sin determinar»: no aporta nada en el menú.
  final hasLanguage =
      language != null && language.isNotEmpty && language != 'und';
  if (hasTitle && hasLanguage) return redactUrlsInText('$title ($language)');
  if (hasTitle) return redactUrlsInText(title);
  if (hasLanguage) return language;
  return 'Pista ${index + 1}';
}
