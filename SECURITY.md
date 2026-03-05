# Security Policy

## Reportar vulnerabilidades

Si encuentras una vulnerabilidad, no la publiques en un issue público.
Abre un canal privado con el mantenedor y comparte:

- Descripción del problema
- Impacto esperado
- Pasos para reproducir
- Propuesta de mitigación (si aplica)

## Buenas prácticas obligatorias

- Nunca subir `android/key.properties` ni archivos `*.jks` / `*.keystore`.
- Nunca subir logs locales (`*.log`, `log_hot_capture.txt`).
- Ejecutar `flutter analyze` y `flutter test` antes de cada push.
- Mantener dependencias actualizadas mediante Dependabot.
- Mantener activado el escaneo de secretos en GitHub Actions.

## Alcance

Este proyecto está diseñado para juego offline local. Cualquier nueva funcionalidad de red debe incluir revisión de seguridad específica antes de merge.
