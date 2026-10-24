import 'package:parcel_desktop/data/platform.dart';

/// Ventana de mentira que recuerda si está en pantalla completa y el título.
class FakeWindowService implements WindowService {
  FakeWindowService({this.fullScreen = false});

  bool fullScreen;
  String? title;

  @override
  Future<void> setFullScreen(bool value) async => fullScreen = value;

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<void> setTitle(String value) async => title = value;

  /// Lo que la app pidió hacer antes de cerrar; el test lo corre como si el
  /// usuario cerrara la ventana.
  Future<void> Function()? beforeClose;

  @override
  Future<void> setCloseHandler(Future<void> Function()? handler) async =>
      beforeClose = handler;
}
