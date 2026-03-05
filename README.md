# Infection Protocol

Party game offline de deducción social para Android en dispositivo rotativo.

## Arquitectura actual

- `domain`: motor determinista, modelos y reglas de juego.
- `flow`: orquestación de turnos/fases (`TurnFlowController`).
- `security`: anti-spoiler en rotación de dispositivo (`AntiSpoilerSystem`).
- `ui`: pantallas consumiendo turnos del motor sin lógica de reglas.

Flujo implementado:

`BOOT -> SETUP -> TRANSFER -> ROLE_REVEAL -> NIGHT_ACTION / INFECTED_CONSENSUS -> DAY_DISCUSSION -> VOTING -> VOTE_RESOLUTION -> CHECK_WIN -> GAME_END`

## Multimedia del frontend

Estado actual del frontend:

- Imágenes de roles: presentes en `assets/images/roles`
- Sonidos de eventos requeridos: presentes en `assets/audio`
	- `vote_cast.wav`
	- `night_kill.wav`
	- `sabotage.wav`
	- `timer_warning.wav`
	- `victory.wav`

Los audios ya están declarados en `pubspec.yaml` para empaquetado.

## Firma release Android

Configurado:

- Firma release soportada con credenciales locales no versionadas.
- Plantilla local: `android/key.properties.example`.
- Build release endurecido para evitar fallback inseguro.

> Seguridad: ya no hay fallback a firma `debug` para `release`.

## Requisitos

- Flutter SDK 3.22+ (incluye Dart)
- Android SDK + `platform-tools`
- JDK 17

## Comandos (Windows PowerShell)

```powershell
# 1) Obtener dependencias
flutter pub get

# 2) Ejecutar tests del core (TDD)
flutter test

# 3) Ejecutar app en debug
flutter run

# 4) Build APK release instalable
flutter build apk --release

# 5) Build AAB release (Play Store)
flutter build appbundle --release

# 6) Build release endurecido (recomendado)
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

APK esperado:

`build\app\outputs\flutter-apk\app-release.apk`

AAB esperado:

`build\app\outputs\bundle\release\app-release.aab`

## Seguridad antes de publicar en GitHub

Checklist mínimo:

- Confirmar que **NO** se suben:
	- `android/key.properties`
	- `*.jks` / `*.keystore`
	- `log_hot_capture.txt` y `*.log`
- Ejecutar localmente:
	- `flutter analyze`
	- `flutter test`

Automatizaciones incluidas en el repo:

- CI: `.github/workflows/ci.yml`
- Security scan: `.github/workflows/security.yml`
- Dependabot: `.github/dependabot.yml`
- Política: `SECURITY.md`

## Automatización local pre-push

Scripts incluidos:

- `scripts/security_prepush.ps1`: ejecuta checks de seguridad antes de push.
- `scripts/install_git_hooks.ps1`: instala hook git local (`pre-push`).

Uso:

```powershell
# instala hook local (una sola vez)
powershell -ExecutionPolicy Bypass -File .\scripts\install_git_hooks.ps1

# ejecutar checks manualmente
powershell -ExecutionPolicy Bypass -File .\scripts\security_prepush.ps1

# modo estricto (falla si falta gitleaks)
powershell -ExecutionPolicy Bypass -File .\scripts\security_prepush.ps1 -Strict
```

## Comando único de publicación segura

```powershell
# prepara repo seguro local (init git si falta, hooks, checks estrictos)
powershell -ExecutionPolicy Bypass -File .\scripts\safe_publish.ps1

# prepara + configura remoto + hace push seguro
powershell -ExecutionPolicy Bypass -File .\scripts\safe_publish.ps1 -RemoteUrl <URL_REPO> -Push
```

