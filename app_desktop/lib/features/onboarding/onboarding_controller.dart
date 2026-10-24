import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/diagnostics/diag_log.dart';
import '../../data/providers.dart';

/// Pasos del asistente de migración.
enum OnboardingStep { welcome, stremio, nuvio, paste, review, progress }

/// Estado del asistente.
class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.welcome,
    this.plan,
    this.profileId,
    this.selected = const {},
    this.pasteText = '',
    this.importing = false,
    this.total = 0,
    this.done = 0,
    this.current,
    this.items = const [],
  });

  final OnboardingStep step;

  /// Lo que se puede traer de la fuente elegida; `null` hasta que se lee.
  final MigrationPlan? plan;

  /// Perfil elegido (solo Nuvio).
  final int? profileId;

  /// `transportUrl` de los candidatos tildados.
  final Set<String> selected;

  /// Lo último que se escribió en «Pegar lista».
  final String pasteText;

  /// Se están instalando addons.
  final bool importing;

  /// Cuántos addons se instalan en esta tanda y cuántos van.
  final int total;
  final int done;

  /// Nombre del addon que se está instalando.
  final String? current;

  /// Resultado por addon, en el orden del plan.
  final List<MigrationItemReport> items;

  /// Candidatos que se muestran en «Revisar»: los del perfil elegido.
  List<MigrationCandidate> get candidates =>
      plan?.candidatesForProfile(profileId) ?? const [];

  /// Los que no se pueden traer (con su motivo), del perfil elegido.
  List<MigrationCandidate> get discarded {
    final p = plan;
    if (p == null) return const [];
    return profileId == null
        ? p.discarded
        : p.discarded.where((c) => c.profileId == profileId).toList();
  }

  List<MigrationCandidate> get selectedCandidates =>
      candidates.where((c) => selected.contains(c.transportUrl)).toList();

  int get installedCount =>
      items.where((i) => i.outcome == MigrationOutcome.installed).length;
  int get alreadyInstalledCount =>
      items.where((i) => i.outcome == MigrationOutcome.alreadyInstalled).length;
  List<MigrationItemReport> get failed =>
      items.where((i) => i.outcome == MigrationOutcome.failed).toList();

  OnboardingState copyWith({
    OnboardingStep? step,
    Object? plan = _keep,
    Object? profileId = _keep,
    Set<String>? selected,
    String? pasteText,
    bool? importing,
    int? total,
    int? done,
    Object? current = _keep,
    List<MigrationItemReport>? items,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      plan: identical(plan, _keep) ? this.plan : plan as MigrationPlan?,
      profileId: identical(profileId, _keep)
          ? this.profileId
          : profileId as int?,
      selected: selected ?? this.selected,
      pasteText: pasteText ?? this.pasteText,
      importing: importing ?? this.importing,
      total: total ?? this.total,
      done: done ?? this.done,
      current: identical(current, _keep) ? this.current : current as String?,
      items: items ?? this.items,
    );
  }
}

const Object _keep = Object();

final onboardingProvider =
    NotifierProvider.autoDispose<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );

/// Lógica del asistente: qué paso se ve, qué plan se leyó, qué se tildó y cómo
/// va la instalación. No sabe de widgets.
class OnboardingController extends Notifier<OnboardingState> {
  DiagLog get _diag => ref.read(diagLogProvider);

  @override
  OnboardingState build() {
    _diag.log('onboarding paso=${OnboardingStep.welcome.name}');
    return const OnboardingState();
  }

  void _goTo(OnboardingStep step, [OnboardingState? base]) {
    state = (base ?? state).copyWith(step: step);
    _diag.log('onboarding paso=${step.name}');
  }

  /// Vuelve al paso anterior. En «Bienvenida» no hace nada (quien llama decide
  /// si sale del asistente). Devuelve `false` si no había adónde volver.
  bool back() {
    if (state.importing) return false;
    switch (state.step) {
      case OnboardingStep.welcome:
      case OnboardingStep.progress:
        return false;
      case OnboardingStep.stremio:
      case OnboardingStep.paste:
        _goTo(OnboardingStep.welcome, state.copyWith(plan: null));
      case OnboardingStep.nuvio:
        // Con el selector de perfil abierto, «Atrás» vuelve al formulario.
        if (state.plan != null) {
          state = state.copyWith(plan: null, profileId: null);
        } else {
          _goTo(OnboardingStep.welcome);
        }
      case OnboardingStep.review:
        _goTo(switch (state.plan?.source) {
          MigrationSource.stremio => OnboardingStep.stremio,
          MigrationSource.nuvio => OnboardingStep.nuvio,
          _ => OnboardingStep.paste,
        });
    }
    return true;
  }

  void chooseSource(OnboardingStep step) {
    assert(
      step == OnboardingStep.stremio ||
          step == OnboardingStep.nuvio ||
          step == OnboardingStep.paste,
    );
    _goTo(step, state.copyWith(plan: null, profileId: null));
  }

  // --- Leer la fuente ---------------------------------------------------------

  List<InstalledAddon> get _installed =>
      ref.read(addonRepositoryProvider).addons;

  /// Trae los addons de Stremio con email y contraseña. Lanza
  /// [AccountException] con un mensaje para la UI si algo falla.
  Future<void> fetchStremioWithPassword(String email, String password) async {
    final client = ref.read(stremioAccountClientProvider);
    final authKey = await client.login(email.trim(), password);
    if (!ref.mounted) return;
    await fetchStremioWithAuthKey(authKey);
  }

  /// Trae los addons de Stremio con un `authKey` ya obtenido y cierra la
  /// sesión. Lanza [AccountException] si falla.
  Future<void> fetchStremioWithAuthKey(String authKey) async {
    final client = ref.read(stremioAccountClientProvider);
    final List<StremioAddonEntry> entries;
    try {
      entries = await client.getAddonCollection(authKey);
    } finally {
      await client.logout(authKey);
    }
    if (!ref.mounted) return;
    _setPlan(MigrationPlan.fromStremio(entries, installed: _installed));
  }

  /// Trae los addons de Nuvio. Si la cuenta tiene más de un perfil se queda en
  /// el paso de Nuvio para que el usuario elija. Lanza [AccountException] si
  /// falla.
  Future<void> fetchNuvio(String email, String password) async {
    final client = ref.read(nuvioAccountClientProvider);
    final session = await client.login(email.trim(), password);
    if (!ref.mounted) return;
    final List<NuvioAddon> rows;
    try {
      rows = await client.getAddons(session);
    } finally {
      await client.logout(session);
    }
    if (!ref.mounted) return;
    _setPlan(MigrationPlan.fromNuvio(rows, installed: _installed));
  }

  /// Cuando hay más de un perfil, [chooseProfile] y [continueWithProfile]
  /// terminan el paso de Nuvio.
  void chooseProfile(int profileId) {
    state = state.copyWith(profileId: profileId);
  }

  void continueWithProfile() {
    final plan = state.plan;
    if (plan == null) return;
    _enterReview(plan, state.profileId);
  }

  /// Guarda lo que se va escribiendo en «Pegar lista».
  void setPasteText(String text) => state = state.copyWith(pasteText: text);

  /// Cuántas URLs de addons hay en [text].
  int countPasted(String text) => PastedAddonsParser.parse(text).length;

  /// Lee el texto pegado y pasa a revisar.
  void submitPaste(String text) {
    state = state.copyWith(pasteText: text);
    _setPlan(MigrationPlan.fromPastedText(text, installed: _installed));
  }

  void _setPlan(MigrationPlan plan) {
    _diag.log(
      'onboarding fuente=${plan.source.name} '
      'candidatos=${plan.candidates.length} '
      'descartados=${plan.discarded.length}'
      '${plan.profileIds.isEmpty ? '' : ' perfiles=${plan.profileIds.length}'}',
    );
    if (plan.profileIds.length > 1) {
      // Nuvio con varios perfiles: elegir antes de revisar.
      state = state.copyWith(plan: plan, profileId: plan.defaultProfileId);
      return;
    }
    _enterReview(plan, plan.defaultProfileId);
  }

  void _enterReview(MigrationPlan plan, int? profileId) {
    final selection = plan.defaultSelection(profileId: profileId);
    _diag.log(
      'onboarding revisar candidatos=${plan.candidatesForProfile(profileId).length} '
      'seleccionados=${selection.length}',
    );
    _goTo(
      OnboardingStep.review,
      state.copyWith(
        plan: plan,
        profileId: profileId,
        selected: {for (final c in selection) c.transportUrl},
      ),
    );
  }

  // --- Revisar ----------------------------------------------------------------

  void toggle(MigrationCandidate candidate) {
    final next = {...state.selected};
    if (!next.remove(candidate.transportUrl)) next.add(candidate.transportUrl);
    state = state.copyWith(selected: next);
  }

  /// Tilda todo lo que se puede instalar (lo que ya está instalado no).
  void selectAll() => state = state.copyWith(
    selected: {
      for (final c in state.candidates)
        if (!c.alreadyInstalled) c.transportUrl,
    },
  );

  void selectNone() => state = state.copyWith(selected: {});

  // --- Instalar ---------------------------------------------------------------

  /// «Empezar con los addons básicos»: instala Cinemeta y OpenSubtitles v3.
  Future<void> useDefaults() {
    final plan = MigrationPlan.fromPasted(
      defaultAddonUrls,
      installed: _installed,
    );
    state = state.copyWith(
      plan: plan,
      profileId: null,
      selected: {for (final c in plan.candidates) c.transportUrl},
    );
    _diag.log('onboarding fuente=basicos candidatos=${plan.candidates.length}');
    return importSelected();
  }

  /// Instala los candidatos tildados, de a uno, mostrando el avance.
  Future<void> importSelected() async {
    final plan = state.plan;
    if (plan == null || state.importing) return;
    final list = state.selectedCandidates;
    _goTo(
      OnboardingStep.progress,
      state.copyWith(
        importing: true,
        total: list.length,
        done: 0,
        current: null,
        items: const [],
      ),
    );
    final items = <MigrationItemReport>[];
    for (final candidate in list) {
      state = state.copyWith(current: candidate.displayName);
      items.addAll(await _apply(plan, candidate));
      if (!ref.mounted) return;
      state = state.copyWith(done: items.length, items: List.of(items));
    }
    state = state.copyWith(importing: false, current: null);
    _logReport();
  }

  /// Vuelve a intentar los que fallaron, conservando el resto del informe.
  Future<void> retryFailed() async {
    final plan = state.plan;
    if (plan == null || state.importing) return;
    final failed = state.failed;
    if (failed.isEmpty) return;
    state = state.copyWith(
      importing: true,
      total: failed.length,
      done: 0,
      current: null,
    );
    final items = List.of(state.items);
    var done = 0;
    for (final item in failed) {
      state = state.copyWith(current: item.candidate.displayName);
      final result = await _apply(plan, item.candidate);
      if (!ref.mounted) return;
      final index = items.indexOf(item);
      if (index >= 0 && result.isNotEmpty) items[index] = result.single;
      done++;
      state = state.copyWith(done: done, items: List.of(items));
    }
    state = state.copyWith(importing: false, current: null);
    _logReport();
  }

  Future<List<MigrationItemReport>> _apply(
    MigrationPlan plan,
    MigrationCandidate candidate,
  ) async {
    final report = await ref.read(migrationServiceProvider).apply(plan, [
      candidate,
    ]);
    return report.items;
  }

  void _logReport() {
    if (!_diag.enabled) return;
    for (final item in state.items) {
      _diag.log(
        'onboarding addon '
        '${redactAddonUrl(item.candidate.transportUrl, name: item.candidate.displayName)} '
        'resultado=${item.outcome.name}'
        '${item.outcome == MigrationOutcome.failed ? ' motivo="${item.message}"' : ''}',
      );
    }
    _diag.log(
      'onboarding informe instalados=${state.installedCount} '
      'yaEstaban=${state.alreadyInstalledCount} fallaron=${state.failed.length}',
    );
  }

  /// Marca el asistente como terminado.
  Future<void> finish() =>
      ref.read(appSettingsProvider.notifier).completeOnboarding();
}
