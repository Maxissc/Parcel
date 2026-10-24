# Parcel

Cliente de escritorio para addons compatibles con el protocolo de Stremio. Windows primero; multiplataforma más adelante.

> En desarrollo temprano: todavía no hay una versión usable.

## Stack

- [Flutter](https://flutter.dev) desktop
- [media_kit](https://github.com/media-kit/media-kit) (libmpv) para reproducción

## Desarrollo

El repo es un workspace de pub con dos paquetes: `app_desktop/` (la app Flutter, `parcel_desktop`) y `packages/core/` (Dart puro, `parcel_core`).

### Requisitos

- Windows 10 o superior.
- [Flutter](https://docs.flutter.dev/get-started/install/windows/desktop) 3.47.8 (canal stable), con Dart 3.13.
- Visual Studio con la carga de trabajo «Desarrollo para el escritorio con C++» (la pide Flutter para compilar en Windows).

### Comandos

Desde la raíz del repo:

```powershell
flutter pub get        # instala las dependencias del workspace
flutter analyze        # análisis estático de los dos paquetes
./tool/test.ps1        # tests de parcel_core y parcel_desktop
```

Desde `app_desktop/`:

```powershell
flutter run -d windows            # corre la app
flutter build windows --debug     # compila la app
```

## Aviso

Parcel no incluye ni preinstala addons ni contenido. Cada usuario agrega los addons que quiere por la URL de su manifest y es responsable de lo que usa.

## Licencia

[MIT](LICENSE)
