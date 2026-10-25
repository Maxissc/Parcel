import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/features/player/subtitle_sync_overlay.dart';

void main() {
  Future<void> pumpOverlay(
    WidgetTester tester, {
    required List<Duration> marks,
    required bool analyzing,
    List<SyncCandidate> candidates = const [],
  }) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubtitleSyncOverlay(
            candidates: candidates,
            marks: marks,
            videoDuration: const Duration(minutes: 10),
            priority: SubtitleLanguage.defaultPriority,
            labelOf: (s) => s.lang,
            onMark: () {},
            onApply: (_) {},
            onClose: () {},
            focusNode: focus,
            analyzing: analyzing,
          ),
        ),
      ),
    );
  }

  testWidgets('con el análisis en curso dice «Analizando subtítulos…» y no '
      '«Quedan 0»', (tester) async {
    await pumpOverlay(
      tester,
      marks: const [Duration(seconds: 15)],
      analyzing: true,
    );

    expect(find.text('Analizando subtítulos…'), findsOneWidget);
    expect(find.textContaining('Quedan'), findsNothing);
  });

  testWidgets('sin análisis en curso cuenta los que quedan', (tester) async {
    await pumpOverlay(
      tester,
      marks: const [Duration(seconds: 15)],
      analyzing: false,
    );

    expect(find.text('Analizando subtítulos…'), findsNothing);
    expect(find.text('Quedan 0 subtítulos que coinciden'), findsOneWidget);
  });
}
