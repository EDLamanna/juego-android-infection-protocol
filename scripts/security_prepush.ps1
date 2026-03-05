param(
    [switch]$SkipAnalyze,
    [switch]$SkipTests,
    [switch]$SkipGitleaks,
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked([string]$Command) {
    Write-Host "> $Command" -ForegroundColor DarkGray
    Invoke-Expression $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command"
    }
}

function Invoke-CheckedBinary([string]$BinaryPath, [string[]]$Arguments) {
    Write-Host "> $BinaryPath $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $BinaryPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $BinaryPath"
    }
}

Write-Step "Validando archivos sensibles versionados"
$forbiddenTracked = @(
    'android/key.properties',
    'android/app/upload-keystore.jks'
)

if (Test-Path '.git') {
    foreach ($file in $forbiddenTracked) {
        $tracked = git ls-files -- $file
        if (-not [string]::IsNullOrWhiteSpace(($tracked -join ''))) {
            throw "Archivo sensible versionado detectado: $file"
        }
    }

    $trackedJks = git ls-files "*.jks" "*.keystore"
    if ($trackedJks) {
        throw "Se detectaron keystores versionados: $($trackedJks -join ', ')"
    }
} else {
    Write-Host "No se detectó repositorio git local; se omiten checks de índice." -ForegroundColor Yellow
}

if (-not $SkipAnalyze) {
    Write-Step "flutter analyze"
    Invoke-Checked "flutter analyze"
}

if (-not $SkipTests) {
    Write-Step "flutter test --no-pub"
    Invoke-Checked "flutter test --no-pub"
}

if (-not $SkipGitleaks) {
    Write-Step "Escaneo de secretos con gitleaks"
    $gitleaksPath = $null

    $gitleaksCmd = Get-Command gitleaks -ErrorAction SilentlyContinue
    if ($null -ne $gitleaksCmd) {
        $gitleaksPath = $gitleaksCmd.Source
    }

    if ($null -eq $gitleaksPath) {
        $wingetLink = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\gitleaks.exe'
        if (Test-Path $wingetLink) {
            $gitleaksPath = $wingetLink
        }
    }

    if ($null -eq $gitleaksPath) {
        $wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        if (Test-Path $wingetPackages) {
            $found = Get-ChildItem $wingetPackages -Recurse -Filter 'gitleaks.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $found) {
                $gitleaksPath = $found.FullName
            }
        }
    }

    if ($null -ne $gitleaksPath) {
        Invoke-CheckedBinary $gitleaksPath @('detect', '--source', '.', '--config', '.gitleaks.toml', '--redact', '--no-banner')
    } elseif ($Strict) {
        throw "gitleaks no está instalado y se ejecutó en modo estricto."
    } else {
        Write-Host "gitleaks no está instalado. Instálalo para habilitar escaneo local de secretos." -ForegroundColor Yellow
    }
}

Write-Host "`nPre-push security checks OK." -ForegroundColor Green
