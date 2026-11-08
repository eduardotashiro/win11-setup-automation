$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"
Write-Host "Installer-Automation"
Write-Host " ________  __    __  __    __   ______
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
$$/      $$/ $$$$$$/ $$/   $$/       $$$$$$/ $$$$$$/ "
Write-Host ""
Write-Host ""

$Root = Split-Path -Parent $PSScriptRoot
$Config = Join-Path $Root "config\programs.json"

$Temp = Join-Path $env:TEMP "WindowsSetup"
if (!(Test-Path $Temp)) { New-Item -ItemType Directory -Path $Temp | Out-Null }

. "$PSScriptRoot\installers.ps1"

function Wait-Internet {
    param([int]$TimeoutSeconds = 900)
    Write-Host "Aguardando conexao com a internet..."
    $TimeLimit = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $TimeLimit) {
        try {
            Invoke-WebRequest -Uri "http://www.msftconnecttest.com/connecttest.txt" -UseBasicParsing -TimeoutSec 5 | Out-Null
            Write-Host "Internet OK."
            return $true
        } catch { Start-Sleep -Seconds 30 }
    }
    Write-Host "Sem internet apos $TimeoutSeconds segundos." -ForegroundColor Red
    return $false
}

function Wait-Winget {
    param([int]$TimeoutSeconds = 600)
    Write-Host "Aguardando winget ficar disponivel..."
    $TimeLimit = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $TimeLimit) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "winget OK."
            return $true
        }
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe } catch { }
        Start-Sleep -Seconds 10
    }
    Write-Host "winget nao ficou disponivel." -ForegroundColor Red
    return $false
}

$Programs = Get-Content $Config -Raw | ConvertFrom-Json
$FailedApps = @()

$SystemArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
switch ($SystemArch.ToUpper()) {
    "X64"   { $SystemArch = "x86_64" }
    "ARM64" { $SystemArch = "ARM64" }
    default { throw "Arquitetura nao suportada: $SystemArch" }
}

$HasInternet = Wait-Internet
$HasWinget = $false
if ($HasInternet) {
    $HasWinget = Wait-Winget
}

foreach ($Program in $Programs.programs) {

    if ($Program.architecture -and $Program.architecture -ne $SystemArch) { continue }

    Write-Host ""
    Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"
    Write-Host "Instalando: $($Program.name)"
    Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"

    try {
        if (-not $HasInternet) { throw "Sem conexao com a internet." }

        if ($Program.type -eq "winget") {
            Install-WingetApp -Program $Program -HasWinget $HasWinget
        }
        elseif ($Program.type -eq "msi") {
            Install-MsiApp -Program $Program -TempFolder $Temp
        }
        elseif ($Program.type -eq "zip") {
            Install-ZipApp -Program $Program -TempFolder $Temp
        }

        Write-Host "OK: $($Program.name)" -ForegroundColor Green

    } catch {
        Write-Host "ERRO em $($Program.name): $($_.Exception.Message)" -ForegroundColor Red
        $FailedApps += $Program.name
    }
}

if ($HasInternet) {
    Activate-Windows
} else {
    Write-Host "ativacao do win11 ignorada (sem internet)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"
Write-Host " INSTALACAO FINALIZADA"
Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"

if ($FailedApps.Count -gt 0) {
    Write-Host "Falharam: $($FailedApps -join ', ')" -ForegroundColor Red
} else {
    Write-Host "Todos os programas foram instalados." -ForegroundColor Green
}

Start-Sleep -Seconds 10
