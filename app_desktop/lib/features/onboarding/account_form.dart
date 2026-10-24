import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';

/// Formulario de email y contraseña de una cuenta (Stremio con email o Nuvio).
///
/// Enter en el email pasa a la contraseña y Enter en la contraseña envía. Los
/// errores de la cuenta aparecen debajo del campo que corresponde.
class AccountForm extends StatefulWidget {
  const AccountForm({
    super.key,
    required this.submitLabel,
    required this.onSubmit,
    this.autofocus = true,
    this.note,
  });

  final String submitLabel;

  /// Hace el login y lo que siga. Si lanza [AccountException], el formulario
  /// muestra el mensaje; si termina bien, no hace nada más.
  final Future<void> Function(String email, String password) onSubmit;
  final bool autofocus;

  /// Texto de ayuda debajo del botón.
  final String? note;

  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  bool _showPassword = false;
  String? _emailError;
  String? _passwordError;
  String? _generalError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;
    setState(() {
      _emailError = email.isEmpty ? 'Escribí tu email.' : null;
      _passwordError = password.isEmpty ? 'Escribí tu contraseña.' : null;
      _generalError = null;
    });
    if (_emailError != null || _passwordError != null) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(email, password);
    } on AccountException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.reason) {
          case AccountFailureReason.accountNotFound:
            _emailError = e.message;
          case AccountFailureReason.wrongPassword:
          case AccountFailureReason.invalidCredentials:
            _passwordError = e.message;
          default:
            _generalError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('account-email'),
            controller: _email,
            autofocus: widget.autofocus,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: 'Email',
              errorText: _emailError,
            ),
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            key: const Key('account-password'),
            controller: _password,
            focusNode: _passwordFocus,
            enabled: !_busy,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Contraseña',
              errorText: _passwordError,
              suffixIcon: IconButton(
                tooltip: _showPassword
                    ? 'Ocultar contraseña'
                    : 'Mostrar contraseña',
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_generalError != null) ...[
            const SizedBox(height: Spacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    _generalError!,
                    key: const Key('account-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Spacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('account-submit'),
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
                        Text('Trayendo addons…'),
                      ],
                    )
                  : Text(widget.submitLabel),
            ),
          ),
          if (widget.note != null) ...[
            const SizedBox(height: Spacing.md),
            Text(
              widget.note!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
