function Install-WingetApp {
    param (
        $Program,
        $HasWinget
    )

    if (-not $HasWinget) { throw "winget não está disponivel" }

    winget install `
        --id $Program.id `
        --exact `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements `
        --source winget

    if ($LASTEXITCODE -ne 0) { throw "winget falhou e retornou o cod $LASTEXITCODE" }
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

    Remove-Item $MsiFile -Force

    if ($Process.ExitCode -ne 0 -and $Process.ExitCode -ne 3010) {
        throw "msiexec falhou com cod $($Process.ExitCode)"
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

    if (Test-Path $ExtractFolder) { Remove-Item $ExtractFolder -Recurse -Force }

    Write-Host "descompactando arquivos..."
    Expand-Archive -Path $ZipFile -DestinationPath $ExtractFolder -Force

    $ExtractedItems = Get-ChildItem -Path $ExtractFolder

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

    # ::::::::::::::::::::::::::::::::::::::::::::::::

    function Activate-Windows {
        Write-Host ""
        Write-Host "iniciando ativacao do win11..."

        try {
            & ([ScriptBlock]::Create((irm https://get.activated.win))) /HWID

            Write-Host "Comando de ativacao enviado com sucesso!" -ForegroundColor Green
        } catch {
            Write-Host "ERRO ao tentar ativar o Windows: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
