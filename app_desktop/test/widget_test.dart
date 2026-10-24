import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/main.dart';

void main() {
  testWidgets('monta la app y muestra Parcel', (WidgetTester tester) async {
    await tester.pumpWidget(const ParcelApp());

    expect(find.text('Parcel'), findsOneWidget);
    expect(find.text('Probar reproductor'), findsOneWidget);
  });

  testWidgets(
    'Probar reproductor pide la URL y abre la pantalla del reproductor',
    (WidgetTester tester) async {
      final engine = FakePlaybackEngine(
        mediaDuration: const Duration(minutes: 1),
      );
      await tester.pumpWidget(ParcelApp(engineFactory: () => engine));

      await tester.tap(find.text('Probar reproductor'));
      await tester.pumpAndSettle();

      // Una URL inválida no abre nada y avisa.
      await tester.enterText(find.byKey(const Key('try-url')), 'no es una url');
      await tester.tap(find.text('Reproducir'));
      await tester.pump();
      expect(find.textContaining('http://'), findsWidgets);
      expect(engine.lastSource, isNull);

      await tester.enterText(
        find.byKey(const Key('try-url')),
        'http://localhost/video.mkv',
      );
      await tester.enterText(
        find.byKey(const Key('try-subtitle')),
        'http://localhost/sub.srt',
      );
      await tester.tap(find.text('Reproducir'));
      await tester.pumpAndSettle();

      expect(engine.lastSource?.url, 'http://localhost/video.mkv');
      expect(engine.state.subtitleTracks.single.isExternal, isTrue);
      expect(find.byKey(const Key('player-controls')), findsOneWidget);
    },
  );
}
