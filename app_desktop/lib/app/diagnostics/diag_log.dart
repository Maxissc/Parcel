import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_diagnostics.dart';

/// Log de diagnóstico de la interfaz: líneas `[diag] ...` por stdout (y al
/// archivo de `PARCEL_DIAG_LOG`, si está).
///
/// Solo existe en debug con `PARCEL_DIAG=1`; si no, [log] no hace nada. Quien
/// lo usa tiene que pasar mensajes sin credenciales ni URLs completas (usar
/// `redactAddonUrl`).
class DiagLog {
  DiagLog({this._sink});

  /// Un log que descarta todo.
  const DiagLog.disabled() : _sink = null;

  /// Un log que escribe donde dice [config].
  factory DiagLog.fromConfig(DiagnosticsConfig config) {
    final path = config.logPath;
    return DiagLog(
      sink: (line) {
        stdout.writeln(line);
        if (path != null) {
          File(path).writeAsStringSync('$line\n', mode: FileMode.append);
        }
      },
    );
  }

  final void Function(String line)? _sink;

  bool get enabled => _sink != null;

  void log(String message) => _sink?.call('[diag] $message');
}

/// Configuración del diagnóstico, o `null` si está apagado. La define `main`.
final diagnosticsConfigProvider = Provider<DiagnosticsConfig?>((ref) => null);

final diagLogProvider = Provider<DiagLog>((ref) {
  final config = ref.watch(diagnosticsConfigProvider);
  return config == null ? const DiagLog.disabled() : DiagLog.fromConfig(config);
});
