/// Paso de los atajos G y H.
const Duration subtitleDelayStep = Duration(milliseconds: 100);

/// «+0,3 s», «−1,2 s» o «0,0 s»: un retraso de subtítulos con una decimal y
/// signo explícito (positivo es retrasar).
String formatDelay(Duration delay) {
  final tenths = (delay.inMilliseconds / 100).round();
  final sign = tenths > 0 ? '+' : (tenths < 0 ? '−' : '');
  final abs = tenths.abs();
  return '$sign${abs ~/ 10},${abs % 10} s';
}
