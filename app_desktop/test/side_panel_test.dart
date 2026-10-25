import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/features/player/player_screen.dart';
import 'package:parcel_desktop/features/player/side_panel.dart';
import 'package:parcel_desktop/features/player/source_candidates.dart';
import 'package:parcel_desktop/features/player/source_menu.dart';

const _audioEs = AudioTrack(id: '1', language: 'spa', title: 'Castellano');
const _audioEn = AudioTrack(id: '2', language: 'eng', title: 'Original');

const _longName = 'Michael.2026.2160p.UHD.BluRay.REMUX.HDR10Plus.DV-GRUPO.mkv';

/// Un nombre tan largo que no entra en tres líneas.
const _hugeName =
    'Michael.2026.2160p.UHD.BluRay.REMUX.HDR10Plus.DV.HEVC.TrueHD.Atmos.7.1-'
    'FraMeSToR.Extended.Cut.Director.Edition.Proper.Multi.Subs.Dual.Audio.'
    'Latino.Castellano.English.Commentary.Special.Features.Included.mkv';

/// Un texto sin los cortes invisibles que se le agregan para partirlo.
Finder _text(String text) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').replaceAll('​', '').contains(text),
);

SourceCandidate _candidate(String name, String title, {String? addon}) =>
    SourceCandidate(
      stream: AddonStream.fromJson({
        'url': 'http://media.example.com/v.mkv?token=SECRETO',
        'name': name,
        'title': title,
      }),
      addonUrl: 'https://a.example.com/manifest.json',
      addonName: addon ?? 'Torrentio RD',
    );

FakePlaybackEngine _engine() => FakePlaybackEngine(
  mediaDuration: const Duration(minutes: 2),
  audioTracks: const [_audioEs, _audioEn],
);

Future<void> _pump(
  WidgetTester tester,
  FakePlaybackEngine engine, {
  SourceMenu? sourceMenu,
  Size size = const Size(960, 600),
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: PlayerScreen(
        engine: engine,
        source: PlaybackSource(url: 'http://x/video.mkv'),
        sourceMenu: sourceMenu,
        title: 'video.mkv',
      ),
    ),
  );
  await tester.pump();
}

Finder get _panel => find.byKey(const Key('player-side-panel'));

void main() {
  testWidgets('abre a la derecha, elige una pista y se cierra', (tester) async {
    final engine = _engine();
    await _pump(tester, engine);

    await tester.tap(find.byKey(const Key('player-audio-menu')));
    await tester.pumpAndSettle();

    expect(_panel, findsOneWidget);
    final rect = tester.getRect(_panel);
    // Unos 420 px de ancho, contra el borde derecho y a toda la altura menos
    // los márgenes.
    expect(rect.width, 420);
    expect(rect.right, 960 - PlayerSidePanel.margin);
    expect(rect.top, PlayerSidePanel.margin);
    expect(rect.bottom, 600 - PlayerSidePanel.margin);
    expect(find.text('Audio'), findsWidgets);
    expect(find.byKey(const Key('player-panel-close')), findsOneWidget);
    // El foco quedó dentro del panel.
    final focus = FocusManager.instance.primaryFocus!;
    expect(
      find.descendant(
        of: _panel,
        matching: find.byWidgetPredicate((w) => w is Focus),
      ),
      findsWidgets,
    );
    expect(focus.debugLabel, 'player-side-panel');

    await tester.tap(find.widgetWithText(PanelOption, 'Original (eng)'));
    await tester.pumpAndSettle();

    expect(engine.state.selectedAudio, _audioEn);
    expect(_panel, findsNothing);
  });

  testWidgets('Esc, la X y un clic afuera lo cierran', (tester) async {
    await _pump(tester, _engine());

    Future<void> open() async {
      await tester.tap(find.byKey(const Key('player-audio-menu')));
      await tester.pumpAndSettle();
      expect(_panel, findsOneWidget);
    }

    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    // Un solo Esc: la pantalla sigue en pie.
    expect(find.byKey(const Key('player-controls')), findsOneWidget);

    await open();
    await tester.tap(find.byKey(const Key('player-panel-close')));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);

    await open();
    await tester.tapAt(const Offset(40, 300));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
  });

  testWidgets('entra y sale con deslizamiento y fundido de unos 220 ms', (
    tester,
  ) async {
    await _pump(tester, _engine());
    await tester.tap(find.byKey(const Key('player-audio-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));

    double opacity() => tester
        .widget<FadeTransition>(
          find
              .ancestor(of: _panel, matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
    final mid = opacity();
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
    final slidingRight = tester.getRect(_panel).right;
    expect(slidingRight, greaterThan(960 - PlayerSidePanel.margin));

    await tester.pump(const Duration(milliseconds: 200));
    expect(opacity(), 1);
    expect(tester.getRect(_panel).right, 960 - PlayerSidePanel.margin);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(_panel, findsOneWidget);
    expect(opacity(), lessThan(1));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(_panel, findsNothing);
  });

  testWidgets('con las animaciones apagadas entra y sale sin demora', (
    tester,
  ) async {
    await _pump(tester, _engine(), disableAnimations: true);
    await tester.tap(find.byKey(const Key('player-audio-menu')));
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(_panel).right, 960 - PlayerSidePanel.margin);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(_panel, findsNothing);
  });

  group('panel de fuentes', () {
    SourceMenu menu({void Function(int, Duration)? onPick}) => SourceMenu(
      candidates: [
        _candidate(
          'Torrentio\n[RD+] 4k DV | HDR',
          '$_longName\n👤 83 💾 12.4 GB ⚙️ ThePirateBay',
        ),
        _candidate(
          'Torrentio\n[RD download] 1080p',
          'Otra.Peli.2026.1080p.WEB-DL-GRUPO.mkv\n👤 3 💾 2 GB',
        ),
        _candidate('Statusio\n720p', 'Peli 720p', addon: 'Statusio'),
      ],
      current: 1,
      onPick: onPick ?? (_, _) {},
    );

    testWidgets('la actual va arriba y marcada, y el resto agrupado por '
        'addon', (tester) async {
      await _pump(tester, _engine(), sourceMenu: menu());
      await tester.tap(find.byKey(const Key('player-source-menu')));
      await tester.pumpAndSettle();

      final options = find.byType(PanelOption);
      expect(options, findsNWidgets(3));
      final first = tester.widget<PanelOption>(options.at(0));
      expect(first.checked, isTrue);
      expect(
        find.descendant(of: options.at(0), matching: _text('Otra.Peli')),
        findsOneWidget,
      );
      expect(tester.widget<PanelOption>(options.at(1)).checked, isFalse);
      expect(find.byType(PanelHeading), findsNWidgets(3));
      expect(find.text('Fuente actual'), findsOneWidget);
      // Los chips salen de las señales del stream.
      expect(find.text('4K'), findsOneWidget);
      expect(find.text('DV'), findsOneWidget);
      expect(find.text('HDR'), findsOneWidget);
      expect(find.text('⚡ Cacheado'), findsOneWidget);
      expect(find.text('Sin cachear'), findsOneWidget);
      expect(find.text('12.4 GB'), findsOneWidget);
      expect(find.text('👤 83'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un título largo se muestra completo y sin elipsis en la '
        'primera línea', (tester) async {
      await _pump(tester, _engine(), sourceMenu: menu());
      await tester.tap(find.byKey(const Key('player-source-menu')));
      await tester.pumpAndSettle();

      final title = find.byKey(const Key('source-title')).at(1);
      final paragraph = tester.renderObject<RenderParagraph>(title);
      final lines = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: 0,
              extentOffset: paragraph.text.toPlainText().length,
            ),
          )
          .map((b) => b.top.round())
          .toSet();
      // Hasta tres líneas, cortadas entre las partes del nombre.
      expect(lines.length, inInclusiveRange(2, 3));
      expect(paragraph.maxLines, 3);
      final shown = paragraph.text.toPlainText().replaceAll('​', '');
      expect(shown, _longName);
      // Con el ancho del panel el nombre entra en tres líneas: sin elipsis.
      expect(paragraph.didExceedMaxLines, isFalse);
      // Los datos sueltos del addon no se repiten en el título, y la URL no
      // aparece nunca.
      expect(_text('ThePirateBay'), findsNothing);
      expect(find.textContaining('SECRETO'), findsNothing);
      expect(find.textContaining('http'), findsNothing);
    });

    testWidgets('un nombre enorme se corta a tres líneas', (tester) async {
      final huge = SourceMenu(
        candidates: [_candidate('Torrentio\n1080p', _hugeName)],
        current: 0,
        onPick: (_, _) {},
      );
      await _pump(tester, _engine(), sourceMenu: huge);
      await tester.tap(find.byKey(const Key('player-source-menu')));
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(const Key('source-title')),
      );
      // Tres líneas de texto de 14 px y no una sola cortada.
      expect(paragraph.size.height, lessThan(3 * 14 * 1.6));
      expect(paragraph.size.height, greaterThan(2 * 14));
      expect(paragraph.didExceedMaxLines, isTrue);
    });

    testWidgets('elegir una fuente avisa con su índice y la posición', (
      tester,
    ) async {
      final picked = <(int, Duration)>[];
      final engine = _engine();
      await _pump(
        tester,
        engine,
        sourceMenu: menu(onPick: (i, p) => picked.add((i, p))),
      );
      engine.tick(const Duration(seconds: 42));
      await tester.pump();
      await tester.tap(find.byKey(const Key('player-source-menu')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PanelOption, 'Statusio').first);
      await tester.pumpAndSettle();

      expect(picked, [(2, const Duration(seconds: 42))]);
      expect(_panel, findsNothing);
    });

    testWidgets('a 960x600 con muchas fuentes no se desborda', (tester) async {
      final many = SourceMenu(
        candidates: [
          for (var i = 0; i < 12; i++)
            _candidate('Torrentio\n[RD+] 1080p', '$_longName.$i'),
        ],
        current: 0,
        onPick: (_, _) {},
      );
      await _pump(tester, _engine(), sourceMenu: many);
      await tester.tap(find.byKey(const Key('player-source-menu')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // La lista tiene scroll propio.
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
