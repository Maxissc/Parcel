import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

import 'support.dart';

Meta _meta(String fixtureName) =>
    Meta.fromJson(fixture(fixtureName)['meta'] as Map<String, dynamic>);

List<String> _names(List<CastMember> cast) => [for (final c in cast) c.name];

void main() {
  group('Cinemeta real: película (tt0111161)', () {
    final meta = _meta('cinemeta_meta_movie_tt0111161.json');

    test('trae el elenco, la dirección y el guion', () {
      final credits = meta.credits;
      expect(_names(credits.cast), [
        'Tim Robbins',
        'Morgan Freeman',
        'Bob Gunton',
      ]);
      expect(credits.directors, ['Frank Darabont']);
      expect(credits.writers, ['Stephen King', 'Frank Darabont']);
    });

    test('sin app_extras no hay fotos ni personajes', () {
      for (final member in meta.credits.cast) {
        expect(member.photoUrl, isNull);
        expect(member.character, isNull);
      }
    });

    test('lee los datos nuevos de la meta', () {
      expect(meta.country, 'United States');
      expect(meta.awards, startsWith('Nominated for 7 Oscars'));
      expect(meta.runtime, '142 min');
      expect(meta.writers, ['Stephen King', 'Frank Darabont']);
      expect(meta.trailerStreams.map((t) => t.ytId), [
        'PLl99DlL6b4',
        'xyXX8LXiNJ4',
      ]);
      expect(meta.trailerStreams.first.title, 'The Shawshank Redemption');
      expect(meta.links.where((l) => l.category == 'Directors'), hasLength(1));
      expect(meta.originalLanguage, isNull);
    });

    test('mantiene la API anterior', () {
      expect(meta.cast, ['Tim Robbins', 'Morgan Freeman', 'Bob Gunton']);
      expect(meta.directors, ['Frank Darabont']);
    });
  });

  group('Cinemeta real: serie (tt0903747), con director null', () {
    final meta = _meta('cinemeta_meta_series_tt0903747.json');

    test('sin dirección y con guion', () {
      final credits = meta.credits;
      expect(credits.directors, isEmpty);
      expect(credits.writers, ['Vince Gilligan']);
      expect(_names(credits.cast), [
        'Bryan Cranston',
        'Aaron Paul',
        'Anna Gunn',
      ]);
    });

    test('premios, país y tráiler', () {
      expect(meta.awards, startsWith('Won 16 Primetime Emmys'));
      expect(meta.country, 'United States');
      expect(meta.trailerStreams.single.ytId, 'VFkjBy2b50Q');
    });
  });

  group('fixture sintético con app_extras.cast', () {
    final meta = _meta('meta_app_extras_synthetic.json');

    test('lee original_language y el país', () {
      expect(meta.originalLanguage, 'es');
      expect(meta.country, 'Argentina, Spain');
    });

    test('las fotos y personajes de app_extras ganan', () {
      final ana = meta.credits.cast.firstWhere((c) => c.name == 'Ana Pérez');
      expect(ana.character, 'Lucía');
      expect(ana.photoUrl, 'https://img.example.com/ana.jpg');
    });

    test('no duplica nombres aunque cambien mayúsculas o tildes', () {
      final names = _names(meta.credits.cast);
      expect(names.where((n) => n.toLowerCase().contains('gom')), hasLength(1));
      expect(names.where((n) => n == 'Ana Pérez'), hasLength(1));
    });

    test('orden: primero app_extras, después cast y links sin repetir', () {
      expect(_names(meta.credits.cast), [
        'Ana Pérez',
        'luis gomez',
        'Zoe Extra',
        'Marta Díaz',
        'Pedro Nuevo',
      ]);
    });

    test('descarta las entradas de app_extras sin nombre o mal formadas', () {
      expect(
        meta.credits.cast.map((c) => c.character),
        isNot(contains('Sin nombre')),
      );
    });

    test('dirección y guion se mezclan con los links sin duplicar', () {
      expect(meta.credits.directors, ['Dir Uno', 'Dir Dos']);
      expect(meta.credits.writers, ['Guionista Uno', 'Guionista Dos']);
    });

    test('descarta tráilers sin ytId', () {
      expect(meta.trailerStreams.map((t) => t.ytId), ['abc123', 'def456']);
      expect(meta.trailerStreams.last.title, isNull);
    });
  });

  group('casos borde', () {
    Meta base(Map<String, Object?> extra) =>
        Meta.fromJson({'id': 'tt1', 'type': 'movie', 'name': 'X', ...extra});

    test('sin ningún dato de elenco', () {
      final credits = base({}).credits;
      expect(credits.cast, isEmpty);
      expect(credits.directors, isEmpty);
      expect(credits.writers, isEmpty);
    });

    test('los links sin nombre o categoría se ignoran', () {
      final meta = base({
        'links': [
          {'category': 'Cast'},
          {'name': 'Sin categoría'},
          'basura',
          {'name': 'Bien', 'category': 'Cast'},
        ],
      });
      expect(_names(meta.credits.cast), ['Bien']);
    });

    test('la categoría de los links no distingue mayúsculas', () {
      final meta = base({
        'links': [
          {'name': 'A', 'category': 'cast'},
          {'name': 'B', 'category': 'DIRECTORS'},
          {'name': 'C', 'category': 'writers'},
        ],
      });
      expect(_names(meta.credits.cast), ['A']);
      expect(meta.credits.directors, ['B']);
      expect(meta.credits.writers, ['C']);
    });

    test('director y writer pueden venir como un solo string', () {
      final meta = base({'director': 'Solo Uno', 'writer': 'Solo Dos'});
      expect(meta.credits.directors, ['Solo Uno']);
      expect(meta.credits.writers, ['Solo Dos']);
    });

    test('copyWith suma elenco con fotos y el idioma original', () {
      final meta =
          base({
            'cast': ['Ana'],
          }).copyWith(
            castDetails: const [
              CastMember(
                name: 'ana',
                character: 'Lucía',
                photoUrl: 'https://i/a.jpg',
              ),
            ],
            originalLanguage: 'ja',
          );
      expect(meta.credits.cast.single.photoUrl, 'https://i/a.jpg');
      expect(meta.originalLanguage, 'ja');
    });

    test('CastMember compara por valores', () {
      expect(
        const CastMember(name: 'A', character: 'B', photoUrl: 'C'),
        const CastMember(name: 'A', character: 'B', photoUrl: 'C'),
      );
    });
  });
}
