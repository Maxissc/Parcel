import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/data/platform.dart';

/// Las llamadas que `window_manager` le hace a Windows, anotadas en orden.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  late List<String> calls;
  late bool maximized;

  setUp(() {
    calls = [];
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isMaximized':
              return maximized;
            case 'setTitleBarStyle':
              calls.add('titulo:${(call.arguments as Map)['titleBarStyle']}');
            case 'setFullScreen':
              calls.add('completa:${(call.arguments as Map)['isFullScreen']}');
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('desde maximizada oculta el título antes de la pantalla completa y lo '
      'devuelve al salir', () async {
    maximized = true;
    const window = DesktopWindowService();

    await window.setFullScreen(true);
    expect(calls, ['titulo:hidden', 'completa:true']);

    calls.clear();
    await window.setFullScreen(false);
    expect(calls, ['completa:false', 'titulo:normal']);
  });

  test('desde una ventana normal solo cambia la pantalla completa', () async {
    const window = DesktopWindowService();

    await window.setFullScreen(true);
    await window.setFullScreen(false);

    expect(calls, ['completa:true', 'completa:false']);
  });

  test('salir sin haber entrado por maximizada no toca el título', () async {
    const window = DesktopWindowService();

    await window.setFullScreen(false);

    expect(calls, ['completa:false']);
  });
}
