import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/shared/media_row.dart';

void main() {
  testWidgets('desplazar la fila no la redibuja entera en cada paso', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Shelf(
            itemCount: 60,
            itemBuilder: (context, index) {
              builds++;
              return SizedBox(width: 150, child: Text('Ítem $index'));
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    // El primer paso hace aparecer la flecha de «anteriores».
    await gesture.moveBy(const Offset(-6, 0));
    await tester.pump();
    await tester.pump();
    final afterFirst = builds;

    // Los siguientes no cambian ninguna flecha ni traen ítems nuevos.
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-3, 0));
      await tester.pump();
    }
    await gesture.up();

    expect(builds, afterFirst);
  });

  testWidgets('las flechas aparecen al pasar el mouse según se pueda mover', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Shelf(
            itemCount: 60,
            itemBuilder: (context, index) =>
                SizedBox(width: 150, child: Text('Ítem $index')),
          ),
        ),
      ),
    );
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(Shelf)));
    await tester.pump(const Duration(milliseconds: 300));

    double opacityOf(String tooltip) => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byTooltip(tooltip),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;

    // Al principio solo se puede ir hacia adelante.
    expect(opacityOf('Ver más'), 1);
    expect(opacityOf('Ver anteriores'), 0);

    await tester.tap(find.byTooltip('Ver más'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));

    expect(opacityOf('Ver anteriores'), 1);
    await mouse.removePointer();
  });
}
