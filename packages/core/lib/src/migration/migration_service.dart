import '../protocol/addon_exception.dart';
import '../storage/addon_repository.dart';
import 'migration_plan.dart';
import '../protocol/redact.dart';

/// Qué pasó con un addon al aplicar el plan.
enum MigrationOutcome { installed, alreadyInstalled, failed }

/// Resultado de un addon del plan.
class MigrationItemReport {
  const MigrationItemReport(this.candidate, this.outcome, this.message);

  final MigrationCandidate candidate;
  final MigrationOutcome outcome;

  /// Texto en español para mostrar. Nunca incluye la URL del addon.
  final String message;

  @override
  String toString() =>
      'MigrationItemReport(${redactAddonUrl(candidate.transportUrl, name: candidate.displayName)}: ${outcome.name})';
}

/// Informe de [MigrationService.apply], un renglón por addon intentado y en
/// el orden en que se intentaron.
class MigrationReport {
  MigrationReport(Iterable<MigrationItemReport> items)
    : items = List.unmodifiable(items);

  final List<MigrationItemReport> items;

  int get installedCount => _count(MigrationOutcome.installed);
  int get alreadyInstalledCount => _count(MigrationOutcome.alreadyInstalled);
  int get failedCount => _count(MigrationOutcome.failed);

  int _count(MigrationOutcome outcome) =>
      items.where((i) => i.outcome == outcome).length;

  @override
  String toString() =>
      'MigrationReport(instalados: $installedCount, ya estaban: '
      '$alreadyInstalledCount, fallaron: $failedCount)';
}

/// Instala en el repositorio de addons lo que el usuario eligió de un
/// [MigrationPlan].
class MigrationService {
  MigrationService(this._repository);

  final AddonRepository _repository;

  /// Instala los candidatos de [plan] que están en [selected], en el orden del
  /// plan (no en el de [selected]). Usa el manifest embebido si el candidato lo
  /// trae y si no lo baja. Sigue ante fallas: cada addon queda en el informe
  /// como instalado, ya instalado o fallido con su motivo.
  ///
  /// Los candidatos de [selected] que no son del plan se ignoran. Un mismo
  /// addon (misma URL) se instala una sola vez.
  Future<MigrationReport> apply(
    MigrationPlan plan,
    Iterable<MigrationCandidate> selected,
  ) async {
    final wanted = {for (final c in selected) c.transportUrl};
    final done = <String>{};
    final items = <MigrationItemReport>[];
    for (final candidate in plan.candidates) {
      if (!wanted.contains(candidate.transportUrl)) continue;
      if (!done.add(candidate.transportUrl)) continue;
      items.add(await _install(candidate));
    }
    return MigrationReport(items);
  }

  Future<MigrationItemReport> _install(MigrationCandidate candidate) async {
    final manifest = candidate.manifest;
    final result = manifest != null
        ? await _repository.installManifest(candidate.transportUrl, manifest)
        : await _repository.install(candidate.transportUrl);
    return switch (result) {
      Installed() => MigrationItemReport(
        candidate,
        MigrationOutcome.installed,
        'Instalado.',
      ),
      AlreadyInstalled() => MigrationItemReport(
        candidate,
        MigrationOutcome.alreadyInstalled,
        'Ya estaba instalado.',
      ),
      InstallFailed(:final error) => MigrationItemReport(
        candidate,
        MigrationOutcome.failed,
        _describe(error),
      ),
    };
  }

  String _describe(AddonException error) => switch (error.reason) {
    AddonFailureReason.invalidUrl => 'La dirección del addon no es válida.',
    AddonFailureReason.timeout => 'El addon no respondió a tiempo.',
    AddonFailureReason.http =>
      error.statusCode == null
          ? 'El addon respondió con un error.'
          : 'El addon respondió con un error (HTTP ${error.statusCode}).',
    AddonFailureReason.network => 'No se pudo conectar con el addon.',
    AddonFailureReason.parse => 'El addon no devolvió un manifest válido.',
  };
}
