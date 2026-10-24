import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';
import 'subtitle_delay.dart';

/// Asistente para dejar los subtítulos sincronizados: el usuario marca cuándo
/// empieza a hablar alguien y se descartan los subtítulos que no tienen
/// diálogo en ese momento.
class SubtitleSyncOverlay extends StatefulWidget {
  const SubtitleSyncOverlay({
    super.key,
    required this.candidates,
    required this.marks,
    required this.videoDuration,
    required this.priority,
    required this.labelOf,
    required this.onMark,
    required this.onApply,
    required this.onClose,
  });

  /// Los subtítulos externos ya bajados y analizados.
  final List<SyncCandidate> candidates;

  /// Las posiciones marcadas hasta ahora.
  final List<Duration> marks;
  final Duration? videoDuration;
  final List<SubtitleLanguage> priority;

  /// Nombre para mostrar de un subtítulo.
  final String Function(Subtitle subtitle) labelOf;

  /// El usuario marca «ahora».
  final VoidCallback onMark;

  /// El usuario eligió uno: hay que cargarlo con su retraso sugerido.
  final void Function(SyncMatch match) onApply;
  final VoidCallback onClose;

  @override
  State<SubtitleSyncOverlay> createState() => _SubtitleSyncOverlayState();
}

class _SubtitleSyncOverlayState extends State<SubtitleSyncOverlay> {
  bool _showDiscarded = false;
  int _selected = 0;

  SyncMatchResult _result() => SubtitleSyncMatcher.match(
    candidates: widget.candidates,
    marks: widget.marks,
    videoDuration: widget.videoDuration,
    priority: widget.priority,
  );

  List<SyncMatch> _visible(SyncMatchResult r) {
    if (widget.marks.length < 2) return const [];
    return _showDiscarded ? [...r.matches, ...r.discarded] : r.matches;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final rows = _visible(_result());
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
    } else if (key == LogicalKeyboardKey.keyS && event is KeyDownEvent) {
      widget.onMark();
    } else if (key == LogicalKeyboardKey.keyD && event is KeyDownEvent) {
      setState(() => _showDiscarded = !_showDiscarded);
    } else if (key == LogicalKeyboardKey.arrowDown && rows.isNotEmpty) {
      setState(() => _selected = (_selected + 1) % rows.length);
    } else if (key == LogicalKeyboardKey.arrowUp && rows.isNotEmpty) {
      setState(() => _selected = (_selected - 1 + rows.length) % rows.length);
    } else if (key == LogicalKeyboardKey.enter &&
        event is KeyDownEvent &&
        rows.isNotEmpty) {
      widget.onApply(rows[_selected.clamp(0, rows.length - 1)]);
    } else {
      // Las demás teclas (volumen, pausa...) siguen andando.
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result();
    final marks = widget.marks;
    final rows = _visible(result);
    final keptCount = result.matches.length;
    final selected = rows.isEmpty ? 0 : _selected.clamp(0, rows.length - 1);

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        key: const Key('sync-overlay'),
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sincronizar subtítulos',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Salir (Esc)',
                      icon: const Icon(Icons.close),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
                const Text(
                  'Apretá S (o hacé clic acá) justo cuando alguien empieza '
                  'a hablar.',
                ),
                const SizedBox(height: Spacing.sm),
                Row(
                  children: [
                    FilledButton.icon(
                      key: const Key('sync-mark'),
                      onPressed: widget.onMark,
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Marcar ahora (S)'),
                    ),
                    const SizedBox(width: Spacing.md),
                    Text(
                      marks.isEmpty
                          ? 'Todavía no marcaste nada'
                          : '${marks.length} ${marks.length == 1 ? 'marca' : 'marcas'}',
                      key: const Key('sync-marks'),
                    ),
                  ],
                ),
                if (marks.isNotEmpty) ...[
                  const SizedBox(height: Spacing.sm),
                  Text(
                    keptCount == 1
                        ? 'Queda 1 subtítulo que coincide'
                        : 'Quedan $keptCount subtítulos que coinciden',
                    key: const Key('sync-remaining'),
                    style: theme.textTheme.titleSmall,
                  ),
                  if (marks.length < 2)
                    Text(
                      'Marcá otro momento para ver la lista.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
                if (rows.isNotEmpty)
                  Flexible(
                    child: ListView.builder(
                      key: const Key('sync-list'),
                      shrinkWrap: true,
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final match = rows[i];
                        final kept = i < keptCount;
                        final delay = match.suggestedDelay;
                        return ListTile(
                          key: Key('sync-row-${match.subtitle.id}'),
                          dense: true,
                          selected: i == selected,
                          enabled: true,
                          title: Text(
                            widget.labelOf(match.subtitle),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kept
                                ? null
                                : TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          subtitle: Text(
                            [
                              '${match.matchedMarks} de ${match.totalMarks} '
                                  'marcas',
                              if (delay != null)
                                'retraso ${formatDelay(delay)}',
                              if (!kept) 'descartado',
                            ].join(' · '),
                          ),
                          onTap: () => widget.onApply(match),
                        );
                      },
                    ),
                  ),
                if (marks.length >= 2 && result.discarded.isNotEmpty)
                  TextButton(
                    key: const Key('sync-discarded'),
                    onPressed: () => setState(() {
                      _showDiscarded = !_showDiscarded;
                      _selected = 0;
                    }),
                    child: Text(
                      _showDiscarded
                          ? 'Ocultar los descartados (D)'
                          : 'Ver los descartados (${result.discarded.length}) (D)',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
