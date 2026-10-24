import '../models/installed_addon.dart';
import '../protocol/addon_exception.dart';

/// Resultado de pedirle algo a un addon: éxito o falla con motivo.
sealed class AddonResult<T> {
  const AddonResult(this.addon);

  /// El addon que respondió (o falló).
  final InstalledAddon addon;
}

/// El addon respondió bien con [value].
final class AddonSuccess<T> extends AddonResult<T> {
  const AddonSuccess(super.addon, this.value);

  final T value;
}

/// El addon falló: [error] dice por qué (timeout, HTTP, parseo...).
final class AddonFailure<T> extends AddonResult<T> {
  const AddonFailure(super.addon, this.error);

  final AddonException error;

  AddonFailureReason get reason => error.reason;
}
