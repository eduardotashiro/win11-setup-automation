$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"
Write-Host "Installer-Automation"

@'
 ________  __    __  __    __   ______
/        |/  |  /  |/  \  /  | /      \
$$$$$$$$/ $$ |  $$ |$$  \ $$ |/$$$$$$  |
  $$ |   $$ |  $$ |$$$  \$$ |$$ |__$$ |
  $$ |   $$ |  $$ |$$$$  $$ |$$    $$ |
  $$ |   $$ |  $$ |$$ $$ $$ |$$$$$$$$ |
  $$ |   $$ \__$$ |$$ |$$$$ |$$ |  $$ |
  $$ |   $$    $$/ $$ | $$$ |$$ |  $$ |
  $$/     $$$$$$/  $$/   $$/ $$/   $$/

__        __  ______  __    __          __      __
/  |  _  /  |/      |/  \  /  |        _/  |   _/  |
$$ | / \ $$ |$$$$$$/ $$  \ $$ |       / $$ |  / $$ |
$$ |/$  \$$ |  $$ |  $$$  \$$ |      $$$$ |  $$$$ |
$$ /$$$  $$ |  $$ |  $$$$  $$ |        $$ |    $$ |
$$ $$/$$ $$ |  $$ |  $$ $$ $$ |        $$ |    $$ |
$$$$/  $$$$ | _$$ |_ $$ |$$$$ |       _$$ |_  _$$ |_
$$$/    $$$ |/ $$   |$$ | $$$ |      / $$   |/ $$   |
$$/      $$/ $$$$$$/ $$/   $$/       $$$$$$/ $$$$$$/
'@

Write-Host ""
Write-Host ""

$Root = Split-Path -Parent $PSScriptRoot
$Config = Join-Path $Root "config\programs.json"

$Temp = Join-Path $env:TEMP "WindowsSetup"

if (!(Test-Path $Temp)) {
    New-Item -ItemType Directory -Path $Temp | Out-Null
}

# imports
. "$PSScriptRoot\installers.ps1"

$Architecture = $env:PROCESSOR_ARCHITECTURE

if ($env:PROCESSOR_ARCHITEW6432) {
    $Architecture = $env:PROCESSOR_ARCHITEW6432
}

switch ($Architecture.ToUpper()) {
    "AMD64" { $SystemArch = "x86_64" }
    "X86"   { throw "Sistema operacional de 32 bits nao suportado." }
    "ARM64" { $SystemArch = "ARM64" }
    default { throw "Arquitetura nao suportada: $Architecture" }
}

Write-Host "arquitetura : $SystemArch" -ForegroundColor Cyan

function Wait-Internet {
    param([int]$TimeoutSeconds = 900)

    Write-Host "aguardando conexao internet..."

    $TimeLimit = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $TimeLimit) {
        try {
            Invoke-WebRequest `
                -Uri "http://www.msftconnecttest.com/connecttest.txt" `
                -UseBasicParsing `
                -TimeoutSec 5 | Out-Null

            Write-Host "internet OK"
            return $true

        } catch {
            Start-Sleep -Seconds 30
        }
    }

    Write-Host "sem internet apos $TimeoutSeconds seg" -ForegroundColor Red
    return $false
}

function Wait-Winget {
    param([int]$TimeoutSeconds = 600)

    Write-Host "aguardando winget ficar disponivel..."

    $TimeLimit = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $TimeLimit) {

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "winget OK"
            return $true
        }

        try {
            Add-AppxPackage -RegisterByFamilyName `
                -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
        } catch {}

        Start-Sleep -Seconds 10
    }

    Write-Host "winget nao ficou disponivel." -ForegroundColor Red
    return $false
}

# https://massgrave.dev/
function Activate-Windows {

    Write-Host ""
    Write-Host "verificando ativacao do win..."

    try {
        $Process = Start-Process `
            -FilePath "cscript.exe" `
            -ArgumentList "//nologo `"$env:SystemRoot\System32\slmgr.vbs`" /ato" `
            -Wait `
            -PassThru `
            -NoNewWindow

        if ($Process.ExitCode -eq 0) {
            Write-Host "solicitacao de ativacao concluida" -ForegroundColor Green
        } else {
            Write-Host "ativacao nao concluida" -ForegroundColor Yellow
        }

    } catch {
        Write-Host "erro na ativacao: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if (!(Test-Path $Config)) {
    throw "arquivo de config nao encontrada: $Config"
}

$Programs = Get-Content $Config -Raw | ConvertFrom-Json
$FailedApps = @()

$HasInternet = Wait-Internet
$HasWinget = $false

if ($HasInternet) {
    $HasWinget = Wait-Winget
}

foreach ($Program in $Programs.programs) {

    if ($Program.architecture -and $Program.architecture -ne $SystemArch) {
        continue
    }

    Write-Host ""
    Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"
    Write-Host "Instalando: $($Program.name)"
    Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"

    try {

        if (-not $HasInternet) {
            throw "sem conexao com a internet"
        }

        if ($Program.type -eq "winget") {

            Install-WingetApp -Program $Program -HasWinget $HasWinget

        }
        elseif ($Program.type -eq "msi") {

            Install-MsiApp -Program $Program -TempFolder $Temp

        }
        elseif ($Program.type -eq "zip") {

            Install-ZipApp -Program $Program -TempFolder $Temp

        }
        else {
            throw "tipo de instalacao desconhecido: $($Program.type)"
        }

        Write-Host "OK: $($Program.name)" -ForegroundColor Green

    } catch {

        Write-Host "ERRO em $($Program.name): $($_.Exception.Message)" -ForegroundColor Red
        $FailedApps += $Program.name

    }
}

# ativação iluminati e updates
if ($HasInternet) {
    Activate-Windows
    Update-Windows
}
else {
    Write-Host "ativacao e win-update ignorados (sem internet)" -ForegroundColor Yellow
}

# Resultado final
Write-Host ""
Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"
Write-Host " INSTALACAO FINALIZADA"
Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"

if ($FailedApps.Count -gt 0) {
    Write-Host "falharam: $($FailedApps -join ', ')" -ForegroundColor Red
}
else {
    Write-Host "todos os programas foram instalados." -ForegroundColor Green
}

Write-Host "reiniciando auto em 20 segundos" -ForegroundColor Cyan
Start-Sleep -Seconds 20
Restart-Computer -Force
