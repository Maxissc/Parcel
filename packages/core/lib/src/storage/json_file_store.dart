import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Guarda un objeto JSON en un archivo cuya ruta se inyecta.
///
/// La escritura es atómica (archivo temporal + rename) y las escrituras se
/// hacen de a una, en el orden en que se piden.
class JsonFileStore {
  JsonFileStore(this.path);

  final String path;
  Future<void> _lastWrite = Future.value();

  /// Lee el objeto guardado. Devuelve `null` si el archivo no existe o está
  /// corrupto; en ese caso el corrupto se conserva como `<path>.bak`.
  Future<Map<String, dynamic>?> readObject() async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // cae a conservar el archivo como .bak
    }
    await backupCorrupt();
    return null;
  }

  /// Mueve el archivo actual a `<path>.bak` (pisa el `.bak` anterior).
  Future<void> backupCorrupt() async {
    final file = File(path);
    if (await file.exists()) await file.rename('$path.bak');
  }

  /// Escribe [json] de forma atómica. La codificación se hace al llamar, así
  /// que cambios posteriores al objeto no afectan lo que se guarda.
  Future<void> write(Map<String, dynamic> json) {
    final text = jsonEncode(json);
    final run = _lastWrite.then((_) => _writeNow(text));
    _lastWrite = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _writeNow(String text) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsString(text, flush: true);
    await temp.rename(path);
  }
}
