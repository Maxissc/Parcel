/// Lógica de Parcel en Dart puro.
library;

export 'src/aggregation/addon_aggregator.dart';
export 'src/aggregation/addon_result.dart';
export 'src/defaults/default_addons.dart';
export 'src/migration/account_exception.dart';
export 'src/migration/pasted_addons_parser.dart';
export 'src/migration/redact.dart';
export 'src/models/addon_manifest.dart';
export 'src/models/addon_stream.dart';
export 'src/models/installed_addon.dart';
export 'src/models/meta.dart';
export 'src/models/playback_progress.dart';
export 'src/models/subtitle.dart';
export 'src/protocol/addon_client.dart';
export 'src/protocol/addon_exception.dart';
export 'src/protocol/manifest_url.dart';
export 'src/protocol/routes.dart';
export 'src/storage/addon_repository.dart';
export 'src/storage/progress_repository.dart';

/// Nombre de la app, para mostrar en la interfaz.
const String appName = 'Parcel';
