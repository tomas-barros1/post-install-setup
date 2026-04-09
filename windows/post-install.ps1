# ================================
# POST INSTALL WINDOWS - TUNADO
# ================================
$ErrorActionPreference = "SilentlyContinue"
$logFile = "$env:USERPROFILE\postinstall_log.txt"

function Log {
    param($msg)
    $time = Get-Date -Format "HH:mm:ss"
    "$time - $msg" | Tee-Object -FilePath $logFile -Append
}

function Install-Winget {
    param($id)
    Log "Instalando (winget): $id"
    winget install --id $id -e --accept-source-agreements --accept-package-agreements
}

function Install-Choco {
    param($id)
    Log "Instalando (choco): $id"
    choco install $id -y
}

# ================================
# VERIFICA / INSTALA WINGET
# ================================
function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Log "winget já instalado: $(winget --version)"
        return
    }

    Log "winget não encontrado. Instalando..."

    $releases = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
    $latest   = Invoke-RestMethod -Uri $releases
    $msixUrl  = ($latest.assets | Where-Object { $_.name -like "*.msixbundle" }).browser_download_url
    $msixPath = "$env:TEMP\winget.msixbundle"

    Invoke-WebRequest -Uri $msixUrl -OutFile $msixPath -UseBasicParsing
    Add-AppxPackage -Path $msixPath

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Log "winget instalado com sucesso: $(winget --version)"
    } else {
        Log "ERRO: falha ao instalar winget. Abortando."
        exit 1
    }
}

# ================================
# VERIFICA / INSTALA CHOCOLATEY
# ================================
function Ensure-Choco {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Log "Chocolatey já instalado: $(choco --version)"
        return
    }

    Log "Chocolatey não encontrado. Instalando..."

    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Log "Chocolatey instalado com sucesso: $(choco --version)"
    } else {
        Log "ERRO: falha ao instalar Chocolatey. Pacotes choco serão ignorados."
    }
}

# ================================
# RESTAURA WINDOWS PHOTO VIEWER
# ================================
function Restore-PhotoViewer {
    Log "Restaurando Windows Photo Viewer..."

    $regContent = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations]
".tif"="PhotoViewer.FileAssoc.Tiff"
".tiff"="PhotoViewer.FileAssoc.Tiff"
".bmp"="PhotoViewer.FileAssoc.Bmp"
".dib"="PhotoViewer.FileAssoc.Bmp"
".gif"="PhotoViewer.FileAssoc.Gif"
".jfif"="PhotoViewer.FileAssoc.Jpeg"
".jpe"="PhotoViewer.FileAssoc.Jpeg"
".jpeg"="PhotoViewer.FileAssoc.Jpeg"
".jpg"="PhotoViewer.FileAssoc.Jpeg"
".jxr"="PhotoViewer.FileAssoc.Wdp"
".png"="PhotoViewer.FileAssoc.Png"
".wdp"="PhotoViewer.FileAssoc.Wdp"
"@

    $regFile = "$env:TEMP\restore_photo_viewer.reg"
    $regContent | Out-File -FilePath $regFile -Encoding ascii
    regedit.exe /s $regFile

    # Define como app padrão no registro
    $path = "HKCU:\Software\Classes\Applications\photoviewer.dll\shell\open"
    New-Item -Path "$path\command" -Force | Out-Null
    Set-ItemProperty -Path "$path\command" -Name "(Default)" -Value "%SystemRoot%\System32\rundll32.exe `"%ProgramFiles%\Windows Photo Viewer\PhotoViewer.dll`", ImageView_Fullscreen %1"
    New-Item -Path "$path\DropTarget" -Force | Out-Null
    Set-ItemProperty -Path "$path\DropTarget" -Name "Clsid" -Value "{FFE2A43C-56B9-4bf5-9A79-CC6D4285608A}"

    Log "Windows Photo Viewer restaurado. Associe as extensões em 'Aplicativos padrão' se necessário."
}

Log "=== INICIANDO SETUP ==="
Ensure-Winget
Ensure-Choco

# ================================
# DEV
# ================================
Install-Winget "Git.Git"
Install-Winget "Microsoft.VisualStudio.Community"
Install-Winget "JetBrains.IntelliJIDEA"
Install-Winget "Docker.DockerDesktop"
Install-Winget "HeidiSQL.HeidiSQL"
Install-Winget "Yaak.app"
Install-Winget "Neovim.Neovim"
Install-Winget "Microsoft.VisualStudioCode"
Install-Winget "ZedIndustries.Zed"
Install-Winget "Oracle.JDK.25"
Install-Winget "Python.Python.3.14"
Install-Winget "Python.Launcher"
Install-Winget "zig.zig"
Install-Winget "Gyan.FFmpeg"
Install-Winget "rjpcomputing.luaforwindows"
Install-Winget "Microsoft.WindowsSDK.10.0.26100"
Install-Winget "Microsoft.WSL"

# ================================
# TERMINAL / SHELL
# ================================
Install-Winget "Microsoft.WindowsTerminal"
Install-Winget "Microsoft.PowerShell"
Install-Winget "Starship.Starship"
Install-Winget "junegunn.fzf"
Install-Winget "ajeetdsouza.zoxide"
Install-Winget "sharkdp.bat"

# ================================
# UTIL
# ================================
Install-Winget "SumatraPDF.SumatraPDF"
Install-Winget "KeePassXCTeam.KeePassXC"
Install-Winget "dotPDN.PaintDotNet"
Install-Winget "qBittorrent.qBittorrent"
Install-Winget "7zip.7zip"
Install-Winget "VideoLAN.VLC"
Install-Winget "Notepad++.Notepad++"
Install-Winget "SublimeHQ.SublimeText.4"
Install-Winget "RevoUninstaller.RevoUninstaller"
Install-Winget "flux.flux"

# ================================
# APPS
# ================================
Install-Winget "Spotify.Spotify"
Install-Winget "Valve.Steam"
Install-Winget "Guru3D.Afterburner"
Install-Winget "Guru3D.RTSS"
Install-Winget "PCSX2Team.PCSX2"
Install-Winget "Brave.Brave"

# ================================
# VISUAL C++ REDISTRIBUTABLES
# ================================
Install-Winget "Microsoft.VCRedist.2005.x86"
Install-Winget "Microsoft.VCRedist.2010.x86"
Install-Winget "Microsoft.VCRedist.2010.x64"
Install-Winget "Microsoft.VCRedist.2015+.x86"
Install-Winget "Microsoft.VCRedist.2015+.x64"
Install-Winget "Microsoft.VCLibs.14"
Install-Winget "Microsoft.VCLibs.Desktop.14"

# ================================
# CHOCOLATEY (EXTRAS)
# ================================
Install-Choco "nerd-fonts-CascadiaCode"
Install-Choco "nerd-fonts-JetBrainsMono"

# ================================
# TWEAKS DO SISTEMA
# ================================
Restore-PhotoViewer

# ================================
# FINAL
# ================================
Log "Atualizando tudo..."
winget upgrade --all --accept-source-agreements --accept-package-agreements
Log "=== FINALIZADO ==="
Write-Host "Acabou! Log em: $logFile"