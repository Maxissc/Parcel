import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/playback/playback_errors.dart';
import 'package:parcel_desktop/playback/playback_stats_reader.dart';

void main() {
  group('MediaLoadGate: cuándo un error es fatal', () {
    test('sin nada cargado, un error es fatal', () {
      final gate = MediaLoadGate();
      expect(gate.isFatalError, isTrue);
    });

    test('el falso error de la prueba real: llegaron las pistas y después '
        '«No se pudo abrir el video» → no es fatal', () {
      final gate = MediaLoadGate()
        ..onTracks(hasAudio: true, hasVideo: true) // el motor cargó las pistas
        ..onDuration(Duration.zero); // y todavía no informó la duración
      expect(gate.loaded, isTrue);
      expect(gate.isFatalError, isFalse);
    });

    test('con duración conocida un error tampoco es fatal', () {
      final gate = MediaLoadGate()..onDuration(const Duration(minutes: 90));
      expect(gate.isFatalError, isFalse);
    });

    test('pistas «vacías» (ni audio ni video) no cuentan como cargado', () {
      final gate = MediaLoadGate()..onTracks(hasAudio: false, hasVideo: false);
      expect(gate.isFatalError, isTrue);
    });

    test('al abrir otro medio vuelve a ser fatal', () {
      final gate = MediaLoadGate()..onDuration(const Duration(minutes: 1));
      gate.reset();
      expect(gate.isFatalError, isTrue);
    });
  });

  group('decideEngineError: lo que hace el motor con un error de mpv', () {
    const raw = 'Failed to open http://host.example.com/v.mkv?token=SECRETO';

    test('sin pistas ni duración es fatal, con mensaje propio y sin URL', () {
      final decision = decideEngineError(MediaLoadGate(), raw);
      expect(decision.fatal, isTrue);
      expect(decision.userMessage, 'No se pudo abrir el video.');
      expect(decision.logLine, contains('host.example.com'));
      expect(decision.logLine, isNot(contains('SECRETO')));
    });

    test('la secuencia real: llegan las pistas y después el error → solo '
        'un aviso', () {
      final gate = MediaLoadGate();
      expect(decideEngineError(gate, raw).fatal, isTrue);
      gate.onTracks(hasAudio: true, hasVideo: true);
      final decision = decideEngineError(gate, raw);
      expect(decision.fatal, isFalse);
      expect(decision.logLine, startsWith('Aviso de reproducción'));
      expect(decision.logLine, isNot(contains('SECRETO')));
    });
  });

  group('dynamicRangeOf', () {
    test('pq es HDR10, hlg es HLG y lo demás es SDR', () {
      expect(dynamicRangeOf(gamma: 'pq'), DynamicRange.hdr10);
      expect(dynamicRangeOf(gamma: 'hlg'), DynamicRange.hlg);
      expect(dynamicRangeOf(gamma: 'bt.1886'), DynamicRange.sdr);
      expect(dynamicRangeOf(), DynamicRange.sdr);
    });

    test('la matriz dolbyvision gana sobre el gamma', () {
      expect(
        dynamicRangeOf(gamma: 'pq', colormatrix: 'dolbyvision'),
        DynamicRange.dolbyVision,
      );
    });
  });

  group('bufferFromCacheState', () {
    const position = Duration(seconds: 100);

    test('mide adelante y atrás dentro del rango que contiene la posición', () {
      const json =
          '{"seekable-ranges":[{"start":10.0,"end":50.0},'
          '{"start":80.0,"end":135.5}],"cache-end":135.5}';
      final b = bufferFromCacheState(json, position);
      expect(b?.ahead, const Duration(seconds: 35, milliseconds: 500));
      expect(b?.behind, const Duration(seconds: 20));
    });

    test('si ningún rango contiene la posición no hay buffer', () {
      const json = '{"seekable-ranges":[{"start":10.0,"end":50.0}]}';
      final b = bufferFromCacheState(json, position);
      expect(b?.ahead, Duration.zero);
      expect(b?.behind, Duration.zero);
    });

    test('un texto que no es JSON o no tiene rangos devuelve null', () {
      expect(bufferFromCacheState('', position), isNull);
      expect(bufferFromCacheState('no es json', position), isNull);
      expect(bufferFromCacheState('{"otra":1}', position), isNull);
    });
  });

  group('parsers de propiedades de mpv', () {
    test('códec: toma el nombre corto', () {
      expect(
        shortCodecName('hevc (HEVC (High Efficiency Video Coding))'),
        'hevc',
      );
      expect(shortCodecName('eac3'), 'eac3');
      expect(shortCodecName(''), isNull);
    });

    test('hardware: «no» y vacío son software', () {
      expect(hardwareDecoderName('d3d11va'), 'd3d11va');
      expect(hardwareDecoderName('no'), isNull);
      expect(hardwareDecoderName(''), isNull);
    });

    test('números: tolera vacío y basura', () {
      expect(parseMpvDouble('23.976'), closeTo(23.976, 1e-9));
      expect(parseMpvDouble(''), isNull);
      expect(parseMpvDouble('no'), isNull);
      expect(parseMpvInt('6'), 6);
      expect(parseMpvInt('6.0'), 6);
      expect(parseMpvInt(''), isNull);
    });
  });
}
