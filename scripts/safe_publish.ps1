param(
    [string]$RemoteUrl,
    [string]$Branch = 'main',
    [switch]$Push,
    [string]$CommitMessage = 'chore: secure initial publish setup'
)

$ErrorActionPreference = 'Stop'

function Run([string]$Command) {
    Write-Host "> $Command" -ForegroundColor DarkGray
    Invoke-Expression $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command"
    }
}

if (-not (Test-Path '.git')) {
    Write-Host 'Inicializando repositorio git local...' -ForegroundColor Cyan
    Run 'git init'
}

Run "git branch -M $Branch"

Write-Host 'Instalando hooks de seguridad...' -ForegroundColor Cyan
Run 'powershell -ExecutionPolicy Bypass -File .\scripts\install_git_hooks.ps1'

Write-Host 'Ejecutando validación estricta pre-push...' -ForegroundColor Cyan
Run 'powershell -ExecutionPolicy Bypass -File .\scripts\security_prepush.ps1 -Strict'

if (-not [string]::IsNullOrWhiteSpace($RemoteUrl)) {
    $originExists = $false
    git remote get-url origin *> $null
    if ($LASTEXITCODE -eq 0) {
        $originExists = $true
    }

    if ($originExists) {
        Run "git remote set-url origin $RemoteUrl"
    } else {
        Run "git remote add origin $RemoteUrl"
    }
}

if ($Push) {
    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
        throw 'Para usar -Push debes indicar -RemoteUrl.'
    }

    Run 'git add .'

    git rev-parse --verify HEAD *> $null
    if ($LASTEXITCODE -ne 0) {
        Run "git commit -m \"$CommitMessage\""
    } else {
        $hasChanges = git status --porcelain
        if ($hasChanges) {
            Run "git commit -m \"$CommitMessage\""
        } else {
            Write-Host 'No hay cambios para commit.' -ForegroundColor Yellow
        }
    }

    Run "git push -u origin $Branch"
}

Write-Host ''
Write-Host 'Safe publish setup completado.' -ForegroundColor Green
if (-not $Push) {
    Write-Host 'Siguiente paso opcional:' -ForegroundColor Cyan
    Write-Host "powershell -ExecutionPolicy Bypass -File .\scripts\safe_publish.ps1 -RemoteUrl <URL_REPO> -Push"
}
