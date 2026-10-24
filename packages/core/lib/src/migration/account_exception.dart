/// Por qué falló un pedido a una cuenta de Stremio o de Nuvio.
enum AccountFailureReason {
  /// No existe una cuenta con ese email.
  accountNotFound,

  /// La contraseña es incorrecta.
  wrongPassword,

  /// Email o contraseña inválidos (Nuvio no distingue cuál de los dos).
  invalidCredentials,

  /// El código de vinculación venció.
  linkExpired,

  /// La sesión no existe o venció.
  sessionExpired,

  /// El servicio no está disponible (5xx, respuesta inesperada del servidor).
  serviceUnavailable,

  /// No se pudo conectar.
  network,

  /// El servidor rechazó el pedido por otro motivo.
  rejected,

  /// La respuesta no tiene la forma esperada.
  parse,
}

/// Falla al hablar con una cuenta de Stremio o de Nuvio.
///
/// [message] está en español, pensado para mostrarse en la UI. Nunca incluye
/// contraseñas, `authKey`, tokens ni URLs de addons.
class AccountException implements Exception {
  const AccountException(this.reason, this.message);

  final AccountFailureReason reason;
  final String message;

  @override
  String toString() => 'AccountException(${reason.name}): $message';
}

/// El código de vinculación de Stremio venció (o nunca existió).
class LinkCodeExpired extends AccountException {
  const LinkCodeExpired()
    : super(
        AccountFailureReason.linkExpired,
        'El código venció. Generá uno nuevo.',
      );
}
