import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/shared/remote_image.dart';

Future<Image> _pump(WidgetTester tester, double width, {double dpr = 1}) async {
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 2000,
        height: 400,
        child: RemoteImage('https://img.example.com/a.jpg', width: width),
      ),
    ),
  );
  return tester.widget<Image>(find.byType(Image));
}

int? _decodeWidth(Image image) => (image.image as ResizeImage).width;

void main() {
  testWidgets('las imágenes anchas se decodifican en escalones de 480 px para '
      'que redimensionar no vuelva a bajarlas', (tester) async {
    expect(_decodeWidth(await _pump(tester, 1000)), 1440);
    expect(_decodeWidth(await _pump(tester, 1100)), 1440);
    expect(_decodeWidth(await _pump(tester, 1400)), 1440);
    expect(_decodeWidth(await _pump(tester, 1500)), 1920);
    expect(_decodeWidth(await _pump(tester, 600, dpr: 2)), 1440);
  });

  testWidgets('las chicas (pósters) se decodifican a su tamaño', (
    tester,
  ) async {
    expect(_decodeWidth(await _pump(tester, 189)), 189);
    expect(_decodeWidth(await _pump(tester, 140, dpr: 2)), 280);
  });

  testWidgets('conserva la imagen anterior mientras llega la nueva', (
    tester,
  ) async {
    final image = await _pump(tester, 1000);
    expect(image.gaplessPlayback, isTrue);
  });
}
