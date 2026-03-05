$ErrorActionPreference = 'Stop'

if (-not (Test-Path '.git')) {
    throw 'Este directorio no contiene un repositorio git (.git). Inicializa git primero.'
}

git config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo configurar core.hooksPath'
}

Write-Host 'Hooks instalados: core.hooksPath=.githooks' -ForegroundColor Green
Write-Host 'Pre-push activo: .githooks/pre-push' -ForegroundColor Green
