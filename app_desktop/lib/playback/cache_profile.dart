import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const int _mib = 1024 * 1024;
const int _gib = 1024 * _mib;

/// Qué tan grande es la caché del reproductor.
enum CacheLevel { low, medium, high }

/// Cómo se arma la caché de mpv según la memoria del equipo.
///
/// Siempre hay caché activa y al menos 10 s por delante (se pide 20 s para
/// tener margen); lo que cambia con la RAM es cuánto video ya visto se guarda
/// hacia atrás para volver sin recargar.
class CacheProfile {
  const CacheProfile._(
    this.level,
    this._name,
    this.maxBytes,
    this.maxBackBytes,
  );

  final CacheLevel level;
  final String _name;

  /// Tope de la caché hacia adelante (`demuxer-max-bytes`).
  final int maxBytes;

  /// Tope de lo ya visto que se guarda (`demuxer-max-back-bytes`).
  final int maxBackBytes;

  /// Segundos de video que se leen por adelantado.
  int get readaheadSeconds => 20;

  /// Nombre y tamaño para el panel de datos, por ejemplo «Media · 300 MB».
  String get label => '$_name · ${maxBytes ~/ _mib} MB';

  /// Opciones de mpv, para fijar antes de abrir el medio.
  Map<String, String> get mpvOptions => {
    'cache': 'yes',
    'demuxer-readahead-secs': '$readaheadSeconds',
    'demuxer-seekable-cache': 'yes',
    'demuxer-max-bytes': '$maxBytes',
    'demuxer-max-back-bytes': '$maxBackBytes',
  };

  static const CacheProfile low = CacheProfile._(
    CacheLevel.low,
    'Chica',
    150 * _mib,
    50 * _mib,
  );
  static const CacheProfile medium = CacheProfile._(
    CacheLevel.medium,
    'Media',
    300 * _mib,
    120 * _mib,
  );
  static const CacheProfile high = CacheProfile._(
    CacheLevel.high,
    'Grande',
    600 * _mib,
    250 * _mib,
  );
}

/// El perfil que corresponde a [totalRamBytes]: menos de 6 GB, chica; de 6 a
/// 12 GB (inclusive), media; más de 12 GB, grande.
CacheProfile cacheProfileForRam(int totalRamBytes) {
  if (totalRamBytes < 6 * _gib) return CacheProfile.low;
  if (totalRamBytes <= 12 * _gib) return CacheProfile.medium;
  return CacheProfile.high;
}

/// Lee cuánta RAM física tiene el equipo, o `null` si no se puede.
typedef RamReader = int? Function();

/// Elige el perfil de caché con la RAM que dice [readRam]. Si no se puede leer
/// (o lanza, o devuelve algo que no tiene sentido), usa el nivel medio.
CacheProfile detectCacheProfile({RamReader readRam = readTotalRamBytes}) {
  try {
    final ram = readRam();
    if (ram != null && ram > 0) return cacheProfileForRam(ram);
  } on Object {
    // Cae al nivel medio.
  }
  return CacheProfile.medium;
}

final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

typedef _GlobalMemoryStatusExNative = Int32 Function(Pointer<_MemoryStatusEx>);
typedef _GlobalMemoryStatusExDart = int Function(Pointer<_MemoryStatusEx>);

/// RAM física total en Windows (`GlobalMemoryStatusEx`); `null` en otros
/// sistemas o si la llamada falla.
int? readTotalRamBytes() {
  if (!Platform.isWindows) return null;
  final status = calloc<_MemoryStatusEx>();
  try {
    status.ref.dwLength = sizeOf<_MemoryStatusEx>();
    final call = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_GlobalMemoryStatusExNative, _GlobalMemoryStatusExDart>(
          'GlobalMemoryStatusEx',
        );
    if (call(status) == 0) return null;
    return status.ref.ullTotalPhys;
  } on Object {
    return null;
  } finally {
    calloc.free(status);
  }
}
