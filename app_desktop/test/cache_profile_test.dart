import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/playback/cache_profile.dart';

const _gib = 1024 * 1024 * 1024;
const _mib = 1024 * 1024;

void main() {
  group('cacheProfileForRam', () {
    test('menos de 6 GB: caché chica', () {
      final p = cacheProfileForRam(4 * _gib);
      expect(p.level, CacheLevel.low);
      expect(p.maxBytes, 150 * _mib);
      expect(p.maxBackBytes, 50 * _mib);
      expect(p.readaheadSeconds, 20);
    });

    test('de 6 a 12 GB (los dos incluidos): caché media', () {
      for (final ram in [6 * _gib, 8 * _gib, 12 * _gib]) {
        final p = cacheProfileForRam(ram);
        expect(p.level, CacheLevel.medium, reason: '$ram');
        expect(p.maxBytes, 300 * _mib);
        expect(p.maxBackBytes, 120 * _mib);
      }
    });

    test('más de 12 GB: caché grande', () {
      final p = cacheProfileForRam(32 * _gib);
      expect(p.level, CacheLevel.high);
      expect(p.maxBytes, 600 * _mib);
      expect(p.maxBackBytes, 250 * _mib);
    });

    test('justo debajo de 6 GB sigue siendo chica', () {
      expect(cacheProfileForRam(6 * _gib - 1).level, CacheLevel.low);
    });

    test('siempre pide caché activa, 20 s adelante y caché con búsqueda', () {
      for (final ram in [2 * _gib, 8 * _gib, 64 * _gib]) {
        final options = cacheProfileForRam(ram).mpvOptions;
        expect(options['cache'], 'yes');
        expect(options['demuxer-readahead-secs'], '20');
        expect(options['demuxer-seekable-cache'], 'yes');
      }
    });

    test('las opciones de mpv llevan los tamaños en bytes', () {
      final options = cacheProfileForRam(8 * _gib).mpvOptions;
      expect(options['demuxer-max-bytes'], '${300 * _mib}');
      expect(options['demuxer-max-back-bytes'], '${120 * _mib}');
    });
  });

  group('detectCacheProfile', () {
    test('usa la RAM que lee', () {
      expect(
        detectCacheProfile(readRam: () => 16 * _gib).level,
        CacheLevel.high,
      );
    });

    test('si no se puede leer la RAM usa el nivel medio', () {
      expect(detectCacheProfile(readRam: () => null).level, CacheLevel.medium);
    });

    test('si leer la RAM lanza un error usa el nivel medio', () {
      expect(
        detectCacheProfile(readRam: () => throw StateError('falló')).level,
        CacheLevel.medium,
      );
    });

    test('una RAM que no tiene sentido usa el nivel medio', () {
      expect(detectCacheProfile(readRam: () => 0).level, CacheLevel.medium);
      expect(detectCacheProfile(readRam: () => -5).level, CacheLevel.medium);
    });
  });

  test('el texto del nivel nombra el tamaño', () {
    expect(cacheProfileForRam(8 * _gib).label, 'Media · 300 MB');
  });

  test('en Windows lee la RAM real del equipo', () {
    final ram = readTotalRamBytes();
    if (Platform.isWindows) {
      expect(ram, greaterThan(1 * _gib));
    } else {
      expect(ram, isNull);
    }
  });
}
