import 'dart:convert';

import '../models/json_helpers.dart';
import '../protocol/manifest_url.dart';

/// Saca URLs de addons de un texto pegado por el usuario.
class PastedAddonsParser {
  const PastedAddonsParser._();

  static final RegExp _url = RegExp(
    r'''(?:https?|stremio)://[^\s,;"'<>()\[\]{}]+''',
    caseSensitive: false,
  );

  /// URLs de manifest normalizadas (ver `normalizeManifestUrl`), sin repetidas
  /// y en el orden en que aparecen.
  ///
  /// Acepta una URL por línea, separadas por espacios o comas, texto con prosa,
  /// una lista JSON de strings o la respuesta de `addonCollectionGet` de
  /// Stremio (de cada entrada toma solo `transportUrl`, no las URLs de logos o
  /// contacto del manifest embebido). Si el texto es un JSON, se leen sus
  /// strings; si no, se barre el texto crudo.
  static List<String> parse(String text) {
    final raw = <String>[];
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (decoded is List || decoded is Map) {
      _walk(decoded, raw);
    } else {
      _scan(text, raw);
    }

    final seen = <String>{};
    final result = <String>[];
    for (final candidate in raw) {
      final String normalized;
      try {
        normalized = normalizeManifestUrl(candidate);
      } on FormatException {
        continue;
      }
      if (seen.add(normalized)) result.add(normalized);
    }
    return List.unmodifiable(result);
  }

  static void _walk(Object? node, List<String> out) {
    if (node is String) {
      _scan(node, out);
    } else if (node is List) {
      for (final item in node) {
        _walk(item, out);
      }
    } else if (node is Map) {
      final map = asMap(node)!;
      final transport = asNonEmptyString(map['transportUrl']);
      if (transport != null) {
        _scan(transport, out);
        return;
      }
      for (final value in map.values) {
        _walk(value, out);
      }
    }
  }

  static void _scan(String text, List<String> out) {
    for (final match in _url.allMatches(text.replaceAll(r'\/', '/'))) {
      var url = match.group(0)!;
      while (url.endsWith('.')) {
        url = url.substring(0, url.length - 1);
      }
      out.add(url);
    }
  }
}
