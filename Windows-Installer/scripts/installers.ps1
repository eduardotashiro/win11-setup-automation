
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
        --accept-package-agreements `
        --accept-source-agreements `
        --source winget

    $ExitCode = $LASTEXITCODE

    if ($ExitCode -eq 0) {
        return
    }

    if ($ExitCode -eq -1978335189) {
        Write-Host "Programa ja instalado e sem atualizacao disponivel." -ForegroundColor Yellow
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

    Invoke-WebRequest -Uri $Program.url -OutFile $MsiFile

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

    Invoke-WebRequest -Uri $Program.url -OutFile $ZipFile

    if (Test-Path $ExtractFolder) {
        Remove-Item $ExtractFolder -Recurse -Force
    }

    Write-Host "descompactando arquivos..."

    Expand-Archive -Path $ZipFile -DestinationPath $ExtractFolder -Force

    $ExtractedItems = @(Get-ChildItem -Path $ExtractFolder)

    if ($ExtractedItems.Count -eq 1 -and $ExtractedItems[0].PSIsContainer) {
        $SourceFolder = $ExtractedItems[0].FullName
    }
    else {
        $SourceFolder = $ExtractFolder
    }

    if (!(Test-Path $TargetFolder)) {
        New-Item -ItemType Directory -Path $TargetFolder -Force | Out-Null
    }

    Write-Host "movendo arquivos para destino final..."

    Get-ChildItem -Path $SourceFolder | ForEach-Object {
        Move-Item -Path $_.FullName -Destination $TargetFolder -Force
    }

    $Exe = Get-ChildItem `
        -Path $TargetFolder `
        -Filter $Program.exeName `
        -File `
        -Recurse |
        Select-Object -First 1

    if (-not $Exe) {
        throw "nao foi possivel achar o arquivo $($Program.exeName) apos a extracao."
    }

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
    Write-Host ""
    Write-Host "Iniciando o Windows Update..." -ForegroundColor Cyan

    try {
        # provedor nuget
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null

        # modulo pswindowsupdate
        Install-Module -Name PSWindowsUpdate -Force -AcceptLicense -ErrorAction Stop | Out-Null
        Import-Module PSWindowsUpdate -ErrorAction Stop

        Write-Host "procurando e instalando atualizacoes, paciencia..."

        # baixa e reinicia automatico
        Get-WindowsUpdate -Install -AcceptAll -AutoReboot
    } catch {
        Write-Host "erro no update: $($_.Exception.Message)" -ForegroundColor Red
    }
}
