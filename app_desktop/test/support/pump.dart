import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/app.dart';
import 'package:parcel_desktop/data/app_data.dart';
import 'package:parcel_desktop/data/platform.dart';

import 'test_env.dart';

/// Espera a que `addons.json` en [dir] cumpla [matcher] (hasta [timeout] de
/// tiempo real) y recién después lo verifica. Con un número fijo de ticks, un
/// disco lento (el runner de CI) hacía fallar la verificación.
Future<void> expectSavedAddons(
  WidgetTester tester,
  Directory dir,
  Object matcher, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final wrapped = wrapMatcher(matcher);
  final deadline = DateTime.now().add(timeout);
  while (!wrapped.matches(savedAddonNames(dir), {}) &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
  expect(savedAddonNames(dir), matcher);
}

/// Espera hasta que aparezca [finder], dejando correr el disco y la red falsa
/// de verdad (los tests de widgets corren con reloj falso, y el disco no).
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxTries = 200,
}) async {
  for (var i = 0; i < maxTries; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  // Un último intento con el mensaje de error de siempre.
  expect(finder, findsWidgets);
}

/// Espera a que pasen [ticks] vueltas de disco y de animaciones.
Future<void> pumpIo(WidgetTester tester, {int ticks = 10}) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pump();
}

/// Prepara la carpeta [dir] como si la app ya se hubiera usado: [urls]
/// instalados y, si [onboardingCompleted], el asistente terminado.
Future<void> seedData(
  WidgetTester tester,
  Directory dir,
  http.Client client, {
  List<String> urls = const [],
  bool onboardingCompleted = false,
  String? audioLanguage,
  String? subtitleLanguage,
  bool? autoSelectSource,
  bool? openFullScreen,
  String? tmdbApiKey,
  List<PlaybackProgress> progress = const [],
}) async {
  await tester.runAsync(() async {
    final data = await AppData.open(dir, client: AddonClient(client));
    for (final url in urls) {
      await data.addons.install(url);
    }
    if (onboardingCompleted ||
        audioLanguage != null ||
        subtitleLanguage != null ||
        autoSelectSource != null ||
        openFullScreen != null ||
        tmdbApiKey != null) {
      var next = data.settings.value.copyWith(
        onboardingCompleted: onboardingCompleted ? true : null,
        autoSelectSource: autoSelectSource,
        openFullScreen: openFullScreen,
      );
      if (audioLanguage != null) {
        next = next.copyWith(audioLanguage: audioLanguage);
      }
      if (subtitleLanguage != null) {
        next = next.copyWith(subtitleLanguage: subtitleLanguage);
      }
      if (tmdbApiKey != null) next = next.copyWith(tmdbApiKey: tmdbApiKey);
      await data.settings.save(next);
    }
    for (final p in progress) {
      await data.progress.save(p);
    }
    await data.dispose();
  });
}

/// Arranca la app sobre [dir] y espera a que termine de cargar los datos.
Future<void> pumpApp(
  WidgetTester tester,
  Directory dir,
  http.Client client, {
  List<Override> overrides = const [],
  List<Uri>? openedUrls,
  WindowService window = const NoopWindowService(),
  StreamProber? prober,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...testOverrides(
          dir,
          client,
          openedUrls: openedUrls,
          window: window,
          prober: prober,
        ),
        ...overrides,
      ],
      child: const ParcelApp(),
    ),
  );
  await pumpUntil(tester, find.byType(Router<Object>));
  await tester.pump(const Duration(milliseconds: 100));
}
