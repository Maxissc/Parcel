/// Por qué falló un pedido a un addon.
enum AddonFailureReason {
  /// La URL del addon no es válida.
  invalidUrl,

  /// El addon no respondió a tiempo.
  timeout,

  /// El addon respondió con un status que no es 2xx.
  http,

  /// No se pudo conectar (sin red, DNS, conexión cortada).
  network,

  /// La respuesta no es JSON o no tiene la forma esperada.
  parse,
}

/// Falla al hablar con un addon.
class AddonException implements Exception {
  const AddonException(this.reason, this.message, {this.statusCode, this.url});

  final AddonFailureReason reason;
  final String message;

  /// Status HTTP, cuando [reason] es [AddonFailureReason.http].
  final int? statusCode;

  /// URL pedida, si se conoce. Es sensible (puede llevar tokens del usuario en
  /// la ruta o la query): no se muestra, ni se escribe en logs ni en
  /// [toString]. Para mostrar algo, usar `redactAddonUrl`.
  final String? url;

  @override
  String toString() => 'AddonException(${reason.name}): $message';
}
