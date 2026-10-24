import 'package:flutter/material.dart';

/// Lo que se pide en el diálogo de prueba del reproductor.
typedef TryPlayerRequest = ({String url, String? subtitleUrl});

/// Pide una URL de video y, opcionalmente, una de subtítulo externo.
/// Devuelve `null` si se cancela.
Future<TryPlayerRequest?> showTryPlayerDialog(BuildContext context) {
  return showDialog<TryPlayerRequest>(
    context: context,
    builder: (_) => const _TryPlayerDialog(),
  );
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

class _TryPlayerDialog extends StatefulWidget {
  const _TryPlayerDialog();

  @override
  State<_TryPlayerDialog> createState() => _TryPlayerDialogState();
}

class _TryPlayerDialogState extends State<_TryPlayerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _subtitle = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final sub = _subtitle.text.trim();
    Navigator.of(context)
        .pop((url: _url.text.trim(), subtitleUrl: sub.isEmpty ? null : sub));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Probar reproductor'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('try-url'),
                controller: _url,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'URL del video',
                  hintText: 'https://…',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                validator: (v) => _isHttpUrl(v ?? '')
                    ? null
                    : 'Poné una URL que empiece con http:// o https://',
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('try-subtitle'),
                controller: _subtitle,
                decoration: const InputDecoration(
                  labelText: 'URL de subtítulo externo (opcional)',
                  hintText: 'https://…/subtitulo.srt',
                ),
                keyboardType: TextInputType.url,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? null
                    : (_isHttpUrl(v)
                          ? null
                          : 'Poné una URL que empiece con http:// o https://'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Reproducir')),
      ],
    );
  }
}
