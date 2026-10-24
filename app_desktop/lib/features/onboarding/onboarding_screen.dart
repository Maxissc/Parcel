import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import 'nuvio_step.dart';
import 'onboarding_controller.dart';
import 'paste_step.dart';
import 'progress_step.dart';
import 'review_step.dart';
import 'stremio_step.dart';
import 'welcome_step.dart';

/// Asistente de migración: trae los addons desde Stremio, Nuvio o una lista
/// pegada. Se abre solo en el primer arranque y se puede volver a abrir desde
/// Addons y Ajustes. Esc vuelve un paso.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
    // Esc se escucha a nivel teclado y no por foco: así funciona en cualquier
    // paso, aunque ningún widget tenga el foco.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    _back();
    return false;
  }

  void _back() {
    final moved = ref.read(onboardingProvider.notifier).back();
    final step = ref.read(onboardingProvider).step;
    if (!moved && step == OnboardingStep.welcome && context.canPop()) {
      context.pop();
    }
  }

  Future<void> _finish() async {
    await ref.read(onboardingProvider.notifier).finish();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(onboardingProvider.select((s) => s.step));
    return Scaffold(
      body: SafeArea(
        child: switch (step) {
          OnboardingStep.welcome => WelcomeStep(
            onLeave: context.canPop() ? () => context.pop() : null,
          ),
          OnboardingStep.stremio => const StremioStep(),
          OnboardingStep.nuvio => const NuvioStep(),
          OnboardingStep.paste => const PasteStep(),
          OnboardingStep.review => const ReviewStep(),
          OnboardingStep.progress => ProgressStep(onFinish: _finish),
        },
      ),
    );
  }
}
