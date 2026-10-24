import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';
import '../../data/providers.dart';
import 'addon_utils.dart';

/// Pide la URL de un addon, lo instala y devuelve el nombre del instalado (o
/// `null` si se cancela).
Future<String?> showAddAddonDialog(BuildContext context) => showDialog<String>(
  context: context,
  builder: (context) => const _AddAddonDialog(),
);

class _AddAddonDialog extends ConsumerStatefulWidget {
  const _AddAddonDialog();

  @override
  ConsumerState<_AddAddonDialog> createState() => _AddAddonDialogState();
}

class _AddAddonDialogState extends ConsumerState<_AddAddonDialog> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final text = _url.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Pegá la URL del manifest del addon.');
      return;
    }
    try {
      normalizeManifestUrl(text);
    } on FormatException {
      setState(
        () => _error =
            'Esa dirección no parece la de un addon. Tiene que empezar con '
            'http://, https:// o stremio://.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final result = await ref
          .read(installedAddonsProvider.notifier)
          .installUrl(text);
      switch (result) {
        case Installed(:final addon):
          if (mounted) Navigator.of(context).pop(addon.manifest.name);
          return;
        case AlreadyInstalled(:final existing):
          error = 'Ya tenés instalado ${existing.manifest.name}.';
        case InstallFailed(:final error):
          setState(() => _error = describeInstallFailure(error));
          return;
      }
    } on FileSystemException {
      error = 'No pudimos guardar el cambio en el disco.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar addon por URL'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pegá la dirección del manifest del addon (termina en '
              'manifest.json).',
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: const Key('add-addon-url'),
              controller: _url,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'URL del addon',
                hintText: 'https://…/manifest.json',
                errorText: _error,
                errorMaxLines: 3,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('add-addon-submit'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: Spacing.sm),
                    Text('Agregando…'),
                  ],
                )
              : const Text('Agregar'),
        ),
      ],
    );
  }
}
