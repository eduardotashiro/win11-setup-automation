function Install-WingetApp {
    param (
        $Program,
        $HasWinget
    )

    if (-not $HasWinget) {
        throw "winget nao esta disponivel"
    }

    winget install `
        --id $Program.id `
        --exact `
        --silent `
        --force `
        --accept-package-agreements `
        --accept-source-agreements `
        --source winget

    $ExitCode = $LASTEXITCODE

    # 0 = success
    # -1978335189 = ja instalado
    if ($ExitCode -eq 0 -or $ExitCode -eq -1978335189) {
        return
    }

    if ($ExitCode -eq -1978335215) {
        Write-Host "hash do arquivo diferente, ignorando por atualizacao do repo" -ForegroundColor Yellow
        return
    }

    throw "winget falhou e retornou o codigo $ExitCode"
}

# ::::::::::::::::::::::::::::::::::::::::::::::::

function Install-MsiApp {
    param (
        $Program,
        $TempFolder
    )

    $MsiFile = Join-Path $TempFolder "$($Program.name).msi"
    Write-Host "baixando instalador MSI..."

    $Max = 3
    $Success = $false
    for ($i = 1; $i -le $Max; $i++) {
        try {
            Invoke-WebRequest -Uri $Program.url -OutFile $MsiFile -ErrorAction Stop
            $Success = $true
            break
        } catch {
            Write-Host "falha no download (Tentativa $i de $Max). Aguardando 10s..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
    }
    if (-not $Success) { throw "falha ao baixar $($Program.name) apos $Max tentativas." }

    Write-Host "executando instalacao MSI..."
    $Process = Start-Process `
        "msiexec.exe" `
        -ArgumentList "/i `"$MsiFile`" /qn /norestart" `
        -Wait `
        -PassThru

    Remove-Item $MsiFile -Force -ErrorAction SilentlyContinue

    if ($Process.ExitCode -ne 0 -and $Process.ExitCode -ne 3010) {
        throw "msiexec falhou com cod $($Process.ExitCode)"
    }
    if ($Process.ExitCode -eq 3010) {
        Write-Host "Instalacao concluida. Reinicializacao necessaria." -ForegroundColor Yellow
    }
}

# ::::::::::::::::::::::::::::::::::::::::::::::::

function Install-ZipApp {
    param (
        $Program,
        $TempFolder
    )

    $ZipFile = Join-Path $TempFolder "$($Program.name).zip"
    $ExtractFolder = Join-Path $TempFolder "Extracted_$($Program.name)"
    $TargetFolder = $Program.installFolder

    Write-Host "baixando pacote ZIP..."

    $Max = 3
    $Success = $false
    for ($i = 1; $i -le $Max; $i++) {
        try {
            Invoke-WebRequest -Uri $Program.url -OutFile $ZipFile -ErrorAction Stop
            $Success = $true
            break
        } catch {
            Write-Host "Falha no download (Tentativa $i de $Max). Aguardando 10s..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
    }
    if (-not $Success) { throw "Falha ao baixar $($Program.name) apos $Max tentativas." }

    if (Test-Path $ExtractFolder) { Remove-Item $ExtractFolder -Recurse -Force }
    Write-Host "descompactando arquivos..."
    Expand-Archive -Path $ZipFile -DestinationPath $ExtractFolder -Force

    $ExtractedItems = @(Get-ChildItem -Path $ExtractFolder)
    if ($ExtractedItems.Count -eq 1 -and $ExtractedItems[0].PSIsContainer) {
        $SourceFolder = $ExtractedItems[0].FullName
    } else {
        $SourceFolder = $ExtractFolder
    }

    if (!(Test-Path $TargetFolder)) { New-Item -ItemType Directory -Path $TargetFolder -Force | Out-Null }
    Write-Host "movendo arquivos para destino final..."
    Get-ChildItem -Path $SourceFolder | ForEach-Object {
        Move-Item -Path $_.FullName -Destination $TargetFolder -Force
    }

    $Exe = Get-ChildItem -Path $TargetFolder -Filter $Program.exeName -File -Recurse | Select-Object -First 1
    if (-not $Exe) { throw "nao foi possivel achar o arquivo $($Program.exeName) apos a extracao." }

    $DesktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
    $ShortcutPath = Join-Path $DesktopPath "$($Program.name).lnk"

    $WScript = New-Object -ComObject WScript.Shell
    $Shortcut = $WScript.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $Exe.FullName
    $Shortcut.WorkingDirectory = $Exe.DirectoryName
    $Shortcut.Save()

    Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $ExtractFolder -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "ZIP extraido e atalho criado"
}

# ::::::::::::::::::::::::::::::::::::::::::::::::

function Update-Windows {
    Write-Host "`nIniciando o Windows Update..." -ForegroundColor Cyan

    try {
        $env:PSModuleAutoUpgradePreference = 'None'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $Max = 5
        $BootstrapSuccess = $false

        # prepara rede e mod
        for ($i = 1; $i -le $Max; $i++) {
            try {
                Write-Host "prepara instalador de mod (Tentativa $i)..."
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -Scope CurrentUser -ErrorAction Stop | Out-Null
                Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction Stop | Out-Null

                Write-Host "verifica PSWindowsUpdate..."
                if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                    Write-Host "baixa PSWindowsUpdate..."
                    Install-Module -Name PSWindowsUpdate -Repository PSGallery -Force -Confirm:$false -AllowClobber -ErrorAction Stop | Out-Null
                }

                $BootstrapSuccess = $true
                break
            } catch {
                Write-Host "falha de rede ao preparar mod , aguardando 20s..." -ForegroundColor Yellow
                Start-Sleep -Seconds 20
            }
        }

        if (-not $BootstrapSuccess) { throw "sem internet para mod do win-update" }

        Import-Module PSWindowsUpdate -Force -ErrorAction Stop

        $Service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($Service.Status -ne "Running") {
            Start-Service -Name wuauserv -ErrorAction Stop
        }

        # update ( fix "intervalo esperado")
        for ($Attempt = 1; $Attempt -le $Max; $Attempt++) {
            try {
                Write-Host "procura e instala atualizacoes (tentativa $Attempt de $Max)..."

                Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot -Verbose -ErrorAction Stop

                Write-Host "ciclo de atualizacao concluida com sucesso" -ForegroundColor Green

                $RebootPending = (
                    (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or
                    (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
                )

                if ($RebootPending) {
                    Write-Host "O Windows sinalizou que precisa reiniciar para concluir as atualizacoes." -ForegroundColor Yellow
                }
                break

            } catch {
                Write-Host "api ocupada ou reiniciando servicos ($($_.Exception.Message))." -ForegroundColor Yellow
                Write-Host "aguardando 20 segundos para tentar novamente..." -ForegroundColor Yellow
                Start-Sleep -Seconds 20
            }
        }
        Write-Host "win-update finalizado" -ForegroundColor Green

    } catch {
        Write-Host "ERRO FATAL NO UPDATE: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "fase final da instalacao..." -ForegroundColor Yellow
        Start-Sleep -Seconds 13
    }
}
