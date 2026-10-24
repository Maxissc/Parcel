import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

Duration _t(int h, int m, int s, [int ms = 0]) =>
    Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);

void main() {
  group('SRT', () {
    test('lee índices, tiempos y texto', () {
      final cues = SubtitleParser.parse(
        '1\n00:00:01,000 --> 00:00:03,500\nHola, mundo.\n\n'
        '2\n00:01:05,250 --> 00:01:07,000\nSegunda línea\ny tercera.\n',
      );
      expect(cues, hasLength(2));
      expect(cues[0].start, _t(0, 0, 1));
      expect(cues[0].end, _t(0, 0, 3, 500));
      expect(cues[0].text, 'Hola, mundo.');
      expect(cues[1].start, _t(0, 1, 5, 250));
      expect(cues[1].end, _t(0, 1, 7));
      expect(cues[1].text, 'Segunda línea\ny tercera.');
    });

    test('tolera BOM y CRLF', () {
      final cues = SubtitleParser.parse(
        '﻿1\r\n00:00:01,000 --> 00:00:02,000\r\nUno\r\n\r\n'
        '2\r\n00:00:03,000 --> 00:00:04,000\r\nDos\r\n',
      );
      expect(cues.map((c) => c.text), ['Uno', 'Dos']);
      expect(cues[0].start, _t(0, 0, 1));
    });

    test('tolera CR solo (Mac viejo)', () {
      final cues = SubtitleParser.parse(
        '1\r00:00:01,000 --> 00:00:02,000\rUno\r\r2\r00:00:03,000 --> 00:00:04,000\rDos',
      );
      expect(cues.map((c) => c.text), ['Uno', 'Dos']);
    });

    test('tolera índices faltantes', () {
      final cues = SubtitleParser.parse(
        '00:00:01,000 --> 00:00:02,000\nUno\n\n00:00:03,000 --> 00:00:04,000\nDos\n',
      );
      expect(cues.map((c) => c.text), ['Uno', 'Dos']);
    });

    test('tolera tiempos con punto en lugar de coma', () {
      final cues = SubtitleParser.parse(
        '1\n00:00:01.250 --> 00:00:02.500\nUno\n',
      );
      expect(cues.single.start, _t(0, 0, 1, 250));
      expect(cues.single.end, _t(0, 0, 2, 500));
    });

    test('milisegundos de 1 o 2 dígitos y espacios raros', () {
      final cues = SubtitleParser.parse(
        '1\n0:00:01,5   -->   0:00:02,25\nUno\n',
      );
      expect(cues.single.start, _t(0, 0, 1, 500));
      expect(cues.single.end, _t(0, 0, 2, 250));
    });

    test('cues pegados, sin línea en blanco entre ellos', () {
      final cues = SubtitleParser.parse(
        '1\n00:00:01,000 --> 00:00:02,000\nUno\n'
        '2\n00:00:03,000 --> 00:00:04,000\nDos\n'
        '3\n00:00:05,000 --> 00:00:06,000\nTres\n',
      );
      expect(cues.map((c) => c.text), ['Uno', 'Dos', 'Tres']);
    });

    test('saca etiquetas HTML y de estilo', () {
      final cues = SubtitleParser.parse(
        '1\n00:00:01,000 --> 00:00:02,000\n{\\an8}<i>Hola</i> <font color="#fff">vos</font> &amp; yo&nbsp;ya\n',
      );
      expect(cues.single.text, 'Hola vos & yo ya');
    });

    test('ordena por inicio y descarta cues rotos', () {
      final cues = SubtitleParser.parse(
        '2\n00:00:10,000 --> 00:00:11,000\nSegundo\n\n'
        '1\n00:00:01,000 --> 00:00:02,000\nPrimero\n\n'
        '3\n00:00:20,000 --> 00:00:19,000\nAl revés\n\n'
        '4\nbasura --> más basura\nRoto\n\n'
        '5\n00:00:30,000 --> 00:00:31,000\n\n',
      );
      expect(cues.map((c) => c.text), ['Primero', 'Segundo']);
    });

    test('un texto que no es subtítulo da una lista vacía', () {
      expect(SubtitleParser.parse(''), isEmpty);
      expect(
        SubtitleParser.parse('<html><body>Error 404</body></html>'),
        isEmpty,
      );
    });
  });

  group('WebVTT', () {
    test('lee el encabezado, los ids, los ajustes y las notas', () {
      final cues = SubtitleParser.parse(
        'WEBVTT - un título\n\n'
        'NOTE esto es un comentario\ncon dos líneas\n\n'
        'STYLE\n::cue { color: red }\n\n'
        'intro\n00:01.000 --> 00:03.000 align:start position:10%\nHola\n\n'
        '00:00:04.000 --> 00:00:05.500\n<c.yellow>Chau</c>\n<00:00:05.000>fin\n\n'
        '1:02:03.004 --> 1:02:04.000\nHora\n',
      );
      expect(cues, hasLength(3));
      expect(cues[0].start, _t(0, 0, 1));
      expect(cues[0].end, _t(0, 0, 3));
      expect(cues[0].text, 'Hola');
      expect(cues[1].start, _t(0, 0, 4));
      expect(cues[1].end, _t(0, 0, 5, 500));
      expect(cues[1].text, 'Chau\nfin');
      expect(cues[2].start, _t(1, 2, 3, 4));
      expect(cues[2].text, 'Hora');
    });

    test('tolera BOM, CRLF y coma decimal', () {
      final cues = SubtitleParser.parse(
        '﻿WEBVTT\r\n\r\n00:00:01,500 --> 00:00:02,000\r\nUno\r\n',
      );
      expect(cues.single.start, _t(0, 0, 1, 500));
      expect(cues.single.text, 'Uno');
    });
  });
}
