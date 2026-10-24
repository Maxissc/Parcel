import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/data/progress_providers.dart';
import 'package:parcel_desktop/shared/media_labels.dart';

import 'support/test_env.dart';

PlaybackProgress _progress(
  String videoId, {
  int minutes = 10,
  String type = 'series',
}) => PlaybackProgress(
  type: type,
  metaId: 'tt1',
  videoId: videoId,
  position: Duration(minutes: minutes),
  duration: const Duration(minutes: 50),
  name: 'Serie',
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = makeTempDir();
    container = await openContainer(dir, mockWorld(defaultRoutes()));
  });
  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  test(
    'guardar progreso lo deja en «Seguir viendo» y en el del video',
    () async {
      expect(container.read(continueWatchingProvider), isEmpty);

      await container.read(progressSaverProvider).save(_progress('tt1:1:3'));

      final items = container.read(continueWatchingProvider);
      expect(items, hasLength(1));
      expect(items.single.videoId, 'tt1:1:3');
      final key = (type: 'series', metaId: 'tt1', videoId: 'tt1:1:3');
      expect(
        container.read(videoProgressProvider(key))?.position,
        const Duration(minutes: 10),
      );
    },
  );

  test('un progreso terminado no figura en «Seguir viendo»', () async {
    await container
        .read(progressSaverProvider)
        .save(_progress('tt1:1:3', minutes: 49));

    expect(container.read(continueWatchingProvider), isEmpty);
  });

  test('las etiquetas de episodio salen del id del video', () {
    expect(episodeLabelFromVideoId('tt0903747:1:3'), 'T1 E3');
    expect(episodeLabelFromVideoId('tt0133093'), isNull);
    expect(episodeLabelFromVideoId('x:a:b'), isNull);
    // Solo los ids de IMDb llevan temporada y episodio: en otros, el número
    // del medio es el id de la serie, no una temporada.
    expect(episodeLabelFromVideoId('kitsu:7442:5'), isNull);
    expect(episodeLabelFromVideoId('tmdb:1399:2'), isNull);
    expect(episodeLabelFromVideoId('tt0903747:0:2'), 'T0 E2');
    expect(episodeLabel(2, 10), 'T2 E10');
    expect(episodeLabel(2, null), isNull);
  });

  test('los tipos se muestran en español', () {
    expect(typeLabel('movie'), 'Películas');
    expect(typeLabel('series'), 'Series');
    expect(typeLabel('podcast'), 'Podcast');
  });
}
