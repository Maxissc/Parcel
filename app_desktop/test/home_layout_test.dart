import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/data/app_settings.dart';
import 'package:parcel_desktop/data/home_layout.dart';

import 'support/test_env.dart';

CatalogRef _ref(String addon, String id, {String type = 'movie'}) {
  final manifest = AddonManifest.fromJson({
    'id': addon,
    'name': addon,
    'version': '1.0.0',
    'resources': ['catalog'],
    'types': [type],
    'catalogs': [
      {'type': type, 'id': id, 'name': id},
    ],
  });
  final installed = InstalledAddon(
    transportUrl: 'https://$addon.example.com/manifest.json',
    manifest: manifest,
  );
  return CatalogRef(installed, manifest.catalogs.single);
}

void main() {
  final a = _ref('uno', 'top');
  final b = _ref('uno', 'new');
  final c = _ref('dos', 'top', type: 'series');

  group('orden y filas ocultas', () {
    test('sin preferencias queda el orden de los addons', () {
      expect(applyHomeLayout([a, b, c], const HomeLayout()), [a, b, c]);
    });

    test('el orden elegido manda y lo nuevo va al final', () {
      final layout = HomeLayout(order: [homeRowKey(c), homeRowKey(a)]);
      expect(applyHomeLayout([a, b, c], layout), [c, a, b]);
    });

    test('las ocultas no salen, salvo que se pidan todas', () {
      final layout = HomeLayout(hidden: {homeRowKey(b)});
      expect(applyHomeLayout([a, b, c], layout), [a, c]);
      expect(applyHomeLayout([a, b, c], layout, includeHidden: true), [
        a,
        b,
        c,
      ]);
    });

    test('una fila de la lista que ya no existe se ignora', () {
      final layout = HomeLayout(
        order: ['https://x|movie|viejo', homeRowKey(b)],
      );
      expect(applyHomeLayout([a, b], layout), [b, a]);
    });
  });

  group('ajustes v3', () {
    late Directory dir;
    setUp(() => dir = makeTempDir());
    tearDown(() => deleteTempDir(dir));

    test('el orden, lo oculto y pasar al siguiente van y vuelven', () async {
      final path = '${dir.path}/settings.json';
      final store = await SettingsStore.open(path);
      await store.save(
        store.value.copyWith(
          homeLayout: HomeLayout(order: ['x|movie|a'], hidden: {'y|movie|b'}),
          autoPlayNext: false,
        ),
      );
      final text = File(path).readAsStringSync();
      expect(jsonDecode(text)['version'], 3);

      final again = await SettingsStore.open(path);
      expect(again.value.homeLayout.order, ['x|movie|a']);
      expect(again.value.homeLayout.hidden, {'y|movie|b'});
      expect(again.value.autoPlayNext, isFalse);
    });

    test('un archivo v2 se lee sin perder nada y con lo nuevo por defecto', () {
      final settings = AppSettings.fromJson({
        'version': 2,
        'onboardingCompleted': true,
        'audioLanguage': 'eng',
        'subtitleLanguage': null,
        'quality': 'p720',
        'tmdbApiKey': 'k',
      });
      expect(settings.onboardingCompleted, isTrue);
      expect(settings.audioLanguage, 'eng');
      expect(settings.subtitleLanguage, isNull);
      expect(settings.quality, QualityPreference.p720);
      expect(settings.tmdbApiKey, 'k');
      expect(settings.homeLayout.order, isEmpty);
      expect(settings.homeLayout.hidden, isEmpty);
      expect(settings.autoPlayNext, isTrue);
    });

    test('lo que no tiene la forma esperada queda por defecto', () {
      final settings = AppSettings.fromJson({
        'version': 3,
        'homeOrder': 'no es una lista',
        'homeHidden': [1, 'ok'],
        'autoPlayNext': 'si',
      });
      expect(settings.homeLayout.order, isEmpty);
      expect(settings.homeLayout.hidden, {'ok'});
      expect(settings.autoPlayNext, isTrue);
    });
  });
}
