import 'package:flutter/material.dart';

/// Espaciados de la app: todos múltiplos de 4 para que las pantallas se vean
/// parejas.
abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Ancho máximo del contenido de una pantalla; en ventanas anchas se centra.
const double contentMaxWidth = 920;

/// Tema oscuro Material 3 con color semilla índigo y la tipografía del
/// sistema.
ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}
