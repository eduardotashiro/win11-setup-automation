$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "********************"
Write-Host "Installer-Automation"
Write-Host "********************"
Write-Host ""

$Root = Split-Path -Parent $PSScriptRoot
$Config = Join-Path $Root "config\programs.json"

$Temp = Join-Path $env:TEMP "WindowsSetup"

if (!(Test-Path $Temp)) {
    New-Item -ItemType Directory -Path $Temp | Out-Null
}

function Wait-Internet {
    param([int]$TimeoutSeconds = 900)

    Write-Host "Aguardando conexao com a internet..."
    $Limite = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $Limite) {
        try {
            Invoke-WebRequest -Uri "http://www.msftconnecttest.com/connecttest.txt" -UseBasicParsing -TimeoutSec 5 | Out-Null
            Write-Host "Internet OK."
            return $true
        }
        catch {
            Start-Sleep -Seconds 30
        }
    }

    Write-Host "Sem internet apos $TimeoutSeconds segundos." -ForegroundColor Red
    return $false
}

function Wait-Winget {
    param([int]$TimeoutSeconds = 600)

    Write-Host "Aguardando winget ficar disponivel..."
    $Limite = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $Limite) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "winget OK."
            return $true
        }

        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
        }
        catch { }

        Start-Sleep -Seconds 10
    }

    Write-Host "winget nao ficou disponivel." -ForegroundColor Red
    return $false
}

$Programs = Get-Content $Config -Raw | ConvertFrom-Json
$Falhas = @()

$TemInternet = Wait-Internet
$TemWinget = $false

if ($TemInternet) {
    $TemWinget = Wait-Winget
}

foreach ($Program in $Programs.programs) {

    Write-Host ""
   Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"
    Write-Host "Instalando: $($Programa.name)"
    Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"

    try {

        if (-not $TemInternet) {
            throw "Sem conexao com a internet."
        }

        if ($Programa.type -eq "winget") {

            if (-not $TemWinget) {
                throw "winget indisponivel."
            }

            winget install `
                --id $Programa.id `
                --exact `
                --silent `
                --accept-package-agreements `
                --accept-source-agreements `
                --source winget

            if ($LASTEXITCODE -ne 0) {
                throw "winget retornou codigo $LASTEXITCODE"
            }
        }

        elseif ($Programa.type -eq "msi") {

            $Arquivo = Join-Path $Temp "$($Programa.name).msi"

            Write-Host "Baixando instalador..."

            Invoke-WebRequest `
                -Uri $Programa.url `
                -OutFile $Arquivo

            Write-Host "Instalando..."

            $Proc = Start-Process `
                "msiexec.exe" `
                -ArgumentList "/i `"$Arquivo`" /qn /norestart" `
                -Wait `
                -PassThru

            Remove-Item $Arquivo -Force

            if ($Proc.ExitCode -ne 0 -and $Proc.ExitCode -ne 3010) {
                throw "msiexec retornou codigo $($Proc.ExitCode)"
            }
        }

        elseif ($Programa.type -eq "zip") {

            $ZipFile = Join-Path $Temp "$($Programa.name).zip"
            $ExtractPath = $Programa.installFolder

            Write-Host "Baixando ZIP do GitHub..."
            Invoke-WebRequest -Uri $Programa.url -OutFile $ZipFile

            if (!(Test-Path $ExtractPath)) {
                New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null
            }

            Write-Host "Extraindo para $ExtractPath..."
            Expand-Archive -Path $ZipFile -DestinationPath $ExtractPath -Force

            $ExePath = Join-Path $ExtractPath $Programa.exeName
            $DesktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
            $ShortcutPath = Join-Path $DesktopPath "$($Programa.name).lnk"

            $WScriptObj = New-Object -ComObject WScript.Shell

            $Shortcut = $WScriptObj.CreateShortcut($ShortcutPath)

            $Shortcut.TargetPath = $ExePath

            $Shortcut.Save()

            Write-Host "Atalho criado na Area de Trabalho com sucesso!"
            Remove-Item $ZipFile -Force
        }

        Write-Host "OK: $($Programa.name)" -ForegroundColor Green
    }
    catch {
        Write-Host "ERRO em $($Programa.name): $($_.Exception.Message)" -ForegroundColor Red
        $Falhas += $Programa.name
    }
}

Write-Host ""
Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"
Write-Host " INSTALACAO FINALIZADA"
Write-Host "-*-*-*-*-*-*-*-*-*-*-*-*"

if ($Falhas.Count -gt 0) {
    Write-Host "Falharam: $($Falhas -join ', ')" -ForegroundColor Red
}
else {
    Write-Host "Todos os programas foram instalados." -ForegroundColor Green
}

Start-Sleep -Seconds 10
