import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'onboarding_controller.dart';
import 'wizard_scaffold.dart';

/// Paso 4: pegar una lista de URLs de manifests.
class PasteStep extends ConsumerStatefulWidget {
  const PasteStep({super.key});

  @override
  ConsumerState<PasteStep> createState() => _PasteStepState();
}

class _PasteStepState extends ConsumerState<PasteStep> {
  late final TextEditingController _text;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(onboardingProvider).pasteText;
    _text = TextEditingController(text: saved);
    _count = ref.read(onboardingProvider.notifier).countPasted(saved);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed(String value) {
    final controller = ref.read(onboardingProvider.notifier);
    controller.setPasteText(value);
    setState(() => _count = controller.countPasted(value));
  }

  void _submit() {
    if (_count == 0) return;
    ref.read(onboardingProvider.notifier).submitPaste(_text.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ref.read(onboardingProvider.notifier);
    return WizardScaffold(
      title: 'Pegá tu lista de addons',
      subtitle:
          'Pegá las URLs de los manifests, una por línea o como venga. '
          'También sirve una lista exportada.',
      onBack: controller.back,
      actions: [
        FilledButton(
          key: const Key('paste-continue'),
          onPressed: _count == 0 ? null : _submit,
          child: const Text('Revisar'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _submit,
            },
            child: TextField(
              key: const Key('paste-text'),
              controller: _text,
              autofocus: true,
              minLines: 8,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              onChanged: _changed,
              decoration: const InputDecoration(
                hintText:
                    'https://v3-cinemeta.strem.io/manifest.json\n'
                    'https://opensubtitles-v3.strem.io/manifest.json',
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            _count == 0
                ? 'Todavía no detectamos ninguna URL. Ctrl+Enter para revisar.'
                : (_count == 1
                      ? '1 URL detectada. Ctrl+Enter para revisar.'
                      : '$_count URLs detectadas. Ctrl+Enter para revisar.'),
            key: const Key('paste-count'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
