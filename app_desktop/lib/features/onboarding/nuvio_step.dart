import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'account_form.dart';
import 'onboarding_controller.dart';
import 'wizard_scaffold.dart';

/// Paso 3: traer los addons de Nuvio con email y contraseña. Si la cuenta
/// tiene varios perfiles, se elige uno antes de revisar.
class NuvioStep extends ConsumerWidget {
  const NuvioStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);
    final plan = state.plan;
    if (plan != null && plan.profileIds.length > 1) {
      return WizardScaffold(
        title: 'Elegí un perfil de Nuvio',
        subtitle: 'Tu cuenta tiene más de un perfil, cada uno con sus addons.',
        onBack: controller.back,
        actions: [
          FilledButton(
            key: const Key('profile-continue'),
            onPressed: controller.continueWithProfile,
            child: const Text('Continuar'),
          ),
        ],
        child: Column(
          children: [
            for (final id in plan.profileIds)
              _ProfileTile(
                profileId: id,
                addonCount: plan.candidatesForProfile(id).length,
                selected: state.profileId == id,
                onTap: () => controller.chooseProfile(id),
              ),
          ],
        ),
      );
    }
    return WizardScaffold(
      title: 'Traé tus addons de Nuvio',
      subtitle: 'Entrá con tu cuenta de Nuvio. No guardamos tu contraseña.',
      onBack: controller.back,
      child: AccountForm(
        submitLabel: 'Traer addons',
        onSubmit: controller.fetchNuvio,
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profileId,
    required this.addonCount,
    required this.selected,
    required this.onTap,
  });

  final int profileId;
  final int addonCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Semantics(
          selected: selected,
          child: ListTile(
            key: Key('profile-$profileId'),
            autofocus: selected,
            leading: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? scheme.primary : null,
            ),
            title: Text('Perfil $profileId'),
            subtitle: Text(addonCount == 1 ? '1 addon' : '$addonCount addons'),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
