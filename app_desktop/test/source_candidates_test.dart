import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/data/browse_providers.dart';
import 'package:parcel_desktop/features/player/source_candidates.dart';

import 'support/test_env.dart';

AddonStream _s(String name, {String? bingeGroup, String? url}) =>
    AddonStream.fromJson({
      'url': url ?? 'http://x/${name.hashCode}.mkv',
      'name': name,
      if (bingeGroup != null) 'behaviorHints': {'bingeGroup': bingeGroup},
    });

StreamGroup _group(String url, String name, List<AddonStream> streams) {
  final a = addon(url, manifestJson('id.$name', name));
  return StreamGroup(a, AddonSuccess(a, streams));
}

void main() {
  test(
    'ordena entre addons: cacheados primero y filtra lo no reproducible',
    () {
      final groups = [
        _group('https://a.example.com/manifest.json', 'A', [
          _s('A 1080p'),
          AddonStream.fromJson({'infoHash': 'abc', 'name': 'torrent'}),
        ]),
        _group('https://b.example.com/manifest.json', 'B', [
          _s('B 1080p [RD+]'),
        ]),
      ];
      final ranked = rankCandidates(groups);
      expect(ranked.map((c) => c.addonName), ['B', 'A']);
      expect(ranked.first.stream.name, 'B 1080p [RD+]');
    },
  );

  test('respeta la calidad preferida', () {
    final groups = [
      _group('https://a.example.com/manifest.json', 'A', [
        _s('x 1080p'),
        _s('x 2160p'),
      ]),
    ];
    expect(
      rankCandidates(
        groups,
        quality: QualityPreference.p2160,
      ).first.stream.name,
      'x 2160p',
    );
  });

  test('para el episodio siguiente prefiere el mismo addon y bingeGroup', () {
    final groups = [
      _group('https://a.example.com/manifest.json', 'A', [
        _s('A 2160p [RD+]'),
        _s('A 1080p', bingeGroup: 'bg-1080'),
      ]),
      _group('https://b.example.com/manifest.json', 'B', [
        _s('B 1080p [RD+]', bingeGroup: 'bg-1080'),
      ]),
    ];
    final ranked = rankCandidates(
      groups,
      preferAddonUrl: 'https://a.example.com/manifest.json',
      preferBingeGroup: 'bg-1080',
    );
    expect(ranked.first.addonName, 'A');
    expect(ranked.first.stream.name, 'A 1080p');
  });

  test('sin bingeGroup, para el episodio siguiente van primero los del '
      'mismo addon (listos antes que el resto)', () {
    final groups = [
      _group('https://b.example.com/manifest.json', 'B', [_s('B 2160p [RD+]')]),
      _group('https://a.example.com/manifest.json', 'A', [
        _s('A 1080p [RD+]'),
        _s('A 720p'),
      ]),
    ];
    final ranked = rankCandidates(
      groups,
      preferAddonUrl: 'https://a.example.com/manifest.json',
    );
    expect(ranked.first.addonName, 'A');
    expect(ranked.first.stream.name, 'A 1080p [RD+]');
    expect(ranked.map((c) => c.addonName).toSet(), {'A', 'B'});
    // El de otro addon no se descarta: queda como alternativa.
    expect(ranked, hasLength(3));
  });

  test('los grupos que fallan o todavía no respondieron no aportan', () {
    final groups = [
      StreamGroup(
        addon('https://a.example.com/manifest.json', manifestJson('a', 'A')),
      ),
      _group('https://b.example.com/manifest.json', 'B', [_s('B 1080p')]),
    ];
    expect(rankCandidates(groups), hasLength(1));
  });

  test('la etiqueta no lleva la URL', () {
    final c = rankCandidates([
      _group('https://a.example.com/manifest.json', 'A', [
        _s('Torrentio\n1080p', url: 'http://h.example.com/v.mkv?token=SECRETO'),
      ]),
    ]).single;
    expect(c.label, contains('Torrentio'));
    expect(c.label, isNot(contains('SECRETO')));
    expect(c.label, isNot(contains('http')));
  });

  test('isReady es falso solo para los que hay que bajar en el debrid', () {
    final c = rankCandidates([
      _group('https://a.example.com/manifest.json', 'A', [
        _s('x 1080p [RD download]'),
        _s('x 1080p [RD+]'),
        _s('x 1080p'),
      ]),
    ]);
    expect(c.where((e) => e.isReady), hasLength(2));
    expect(
      c.where((e) => !e.isReady).single.stream.name,
      'x 1080p [RD download]',
    );
  });
}
