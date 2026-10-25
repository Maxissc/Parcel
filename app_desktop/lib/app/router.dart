import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart' show CatalogRef, Meta;

import '../data/providers.dart';
import '../features/addons/addons_screen.dart';
import '../features/catalog/catalog_screen.dart';
import '../features/detail/detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/player/play_args.dart';
import '../features/player/play_route.dart';
import '../features/player/player_route.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/streams/streams_args.dart';
import '../features/streams/streams_screen.dart';
import '../shared/state_views.dart';
import 'shell.dart';

/// Rutas de la app.
abstract final class Routes {
  static const home = '/';
  static const search = '/search';
  static const addons = '/addons';
  static const settings = '/settings';
  static const onboarding = '/onboarding';
  static const player = '/player';
  static const play = '/play';
  static const streams = '/streams';
  static const catalog = '/catalog';
  static const detail = '/detail/:type/:id';

  /// Dirección del detalle de un contenido.
  static String detailPath(String type, String id) =>
      '/detail/${Uri.encodeComponent(type)}/${Uri.encodeComponent(id)}';
}

/// Si hay que abrir el asistente: sin addons y sin haberlo completado nunca.
bool needsOnboarding(Ref ref) =>
    ref.read(addonRepositoryProvider).addons.isEmpty &&
    !ref.read(appSettingsProvider).onboardingCompleted;

/// El router. Se arma de nuevo cuando se recargan los datos (por ejemplo, al
/// borrar todo), para volver a evaluar el primer arranque.
final routerProvider = Provider<GoRouter>((ref) {
  ref.watch(appDataProvider);
  final router = GoRouter(
    initialLocation: Routes.home,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (location == Routes.player && state.extra is! PlayerArgs) {
        return Routes.home;
      }
      if (location == Routes.play && state.extra is! PlayArgs) {
        return Routes.home;
      }
      if (location == Routes.streams && state.extra is! StreamsArgs) {
        return Routes.home;
      }
      if (location == Routes.catalog && state.extra is! CatalogRef) {
        return Routes.home;
      }
      if (location != Routes.onboarding &&
          location != Routes.player &&
          location != Routes.play &&
          needsOnboarding(ref)) {
        return Routes.onboarding;
      }
      return null;
    },
    errorBuilder: (context, state) => const Scaffold(
      body: ErrorState(
        title: 'No encontramos esa pantalla',
        message: 'Volvé al inicio desde el menú.',
      ),
    ),
    routes: [
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.player,
        builder: (context, state) =>
            PlayerRoute(args: state.extra! as PlayerArgs),
      ),
      GoRoute(
        path: Routes.play,
        builder: (context, state) => PlayRoute(args: state.extra! as PlayArgs),
      ),
      GoRoute(
        path: Routes.detail,
        builder: (context, state) => DetailScreen(
          type: state.pathParameters['type']!,
          id: state.pathParameters['id']!,
          hint: state.extra is Meta ? state.extra! as Meta : null,
        ),
      ),
      GoRoute(
        path: Routes.catalog,
        builder: (context, state) =>
            CatalogScreen(catalog: state.extra! as CatalogRef),
      ),
      GoRoute(
        path: Routes.streams,
        builder: (context, state) =>
            StreamsScreen(args: state.extra! as StreamsArgs),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.search,
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.addons,
                builder: (context, state) => const AddonsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
