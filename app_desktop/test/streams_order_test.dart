import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/data/browse_providers.dart';
import 'package:parcel_desktop/features/streams/streams_order.dart';

import 'support/test_env.dart';

AddonStream _stream(String name, {String? binge, bool playable = true}) =>
    AddonStream.fromJson({
      'name': name,
      if (playable) 'url': 'http://media.example.com/$name.mkv',
      if (!playable) 'infoHash': 'abc',
      if (binge != null) 'behaviorHints': {'bingeGroup': binge},
    });

StreamGroup _group(String url, String name) =>
    StreamGroup(addon(url, manifestJson('id.$name', name)));

void main() {
  test('el addon preferido va primero y el resto conserva su orden', () {
    final a = _group('https://a.example/manifest.json', 'A');
    final b = _group('https://b.example/manifest.json', 'B');
    final c = _group('https://c.example/manifest.json', 'C');

    expect(orderGroups([a, b, c], 'https://c.example/manifest.json'), [
      c,
      a,
      b,
    ]);
    expect(orderGroups([a, b, c], null), [a, b, c]);
    expect(orderGroups([a, b, c], 'https://otro.example/manifest.json'), [
      a,
      b,
      c,
    ]);
  });

  test('los streams del mismo bingeGroup van primero', () {
    final x = _stream('x', binge: 'g1');
    final y = _stream('y', binge: 'g2');
    final z = _stream('z', binge: 'g2');

    expect(orderStreams([x, y, z], 'g2'), [y, z, x]);
    expect(orderStreams([x, y, z], 'g3'), [x, y, z]);
    expect(orderStreams([x, y, z], null), [x, y, z]);
  });

  group('recommendedStream', () {
    test('prefiere el del mismo bingeGroup aunque no sea el primero', () {
      final x = _stream('x', binge: 'g1');
      final y = _stream('y', binge: 'g2');
      expect(identical(recommendedStream([x, y], 'g2'), y), isTrue);
    });

    test('sin coincidencia ni bingeGroup toma el primero reproducible', () {
      final torrent = _stream('t', playable: false);
      final x = _stream('x', binge: 'g1');
      expect(identical(recommendedStream([torrent, x], 'g9'), x), isTrue);
      expect(identical(recommendedStream([torrent, x], null), x), isTrue);
    });

    test('si ninguno se puede reproducir no sugiere nada', () {
      expect(recommendedStream([_stream('t', playable: false)], null), isNull);
      expect(recommendedStream(const [], 'g1'), isNull);
    });
  });
}
