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

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "Rode este script como Administrador (winget/choco precisam de elevação)." -ForegroundColor Red
    exit 1
}

function Refresh-Env {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Log "winget já instalado: $(winget --version)"
        return
    }

    Log "winget não encontrado. Instalando dependências e o pacote..."

    try {
        $tmp = "$env:TEMP\winget-install"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null

        $vclibsUrl   = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $xamlAppxUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"

        Invoke-WebRequest -Uri $vclibsUrl -OutFile "$tmp\vclibs.appx" -UseBasicParsing -ErrorAction Stop
        Invoke-WebRequest -Uri $xamlAppxUrl -OutFile "$tmp\xaml.appx" -UseBasicParsing -ErrorAction Stop

        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -ErrorAction Stop
        $msixUrl  = ($releases.assets | Where-Object { $_.name -like "*.msixbundle" }).browser_download_url
        if (-not $msixUrl) { throw "Não encontrei o .msixbundle no release do winget." }

        $msixPath = "$tmp\winget.msixbundle"
        Invoke-WebRequest -Uri $msixUrl -OutFile $msixPath -UseBasicParsing -ErrorAction Stop

        Add-AppxPackage -Path "$tmp\vclibs.appx" -ErrorAction Stop
        Add-AppxPackage -Path "$tmp\xaml.appx" -ErrorAction Stop
        Add-AppxPackage -Path $msixPath -ErrorAction Stop

        Refresh-Env

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Log "winget instalado com sucesso: $(winget --version)"
        } else {
            Log "AVISO: winget instalado mas não reconhecido nesta sessão. Talvez precise reabrir o PowerShell."
        }
    }
    catch {
        Log "ERRO ao instalar winget: $($_.Exception.Message)"
        exit 1
    }
}

function Ensure-Choco {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Log "Chocolatey já instalado: $(choco --version)"
        return
    }

    Log "Chocolatey não encontrado. Instalando..."

    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        Refresh-Env

        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Log "Chocolatey instalado com sucesso: $(choco --version)"
        } else {
            Log "AVISO: choco instalado mas não reconhecido nesta sessão. Talvez precise reabrir o PowerShell."
        }
    }
    catch {
        Log "ERRO ao instalar Chocolatey: $($_.Exception.Message)"
    }
}

function Restore-PhotoViewer {
    Log "Restaurando Windows Photo Viewer..."

    $regFile = Join-Path $PSScriptRoot "Restore_Windows_Photo_Viewer_CURRENT_USER.reg"

    if (Test-Path $regFile) {
        regedit.exe /s $regFile
        Log "Windows Photo Viewer restaurado. Associe as extensões em 'Aplicativos padrão' se necessário."
    } else {
        Log "AVISO: arquivo .reg não encontrado em $regFile. Pulando restauração do Photo Viewer."
    }
}

Log "=== INICIANDO SETUP ==="
Ensure-Winget
Ensure-Choco

# ================================
# DEV
# ================================
Install-Winget "Git.Git"
Install-Winget "Microsoft.VisualStudio.Community"
Install-Winget "Docker.DockerDesktop"
Install-Winget "Yaak.app"
Install-Winget "Neovim.Neovim"
Install-Winget "Python.Python.3.14"
Install-Winget "Python.Launcher"
Install-Winget "Gyan.FFmpeg"

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
Install-Winget "dotPDN.PaintDotNet"
Install-Winget "qBittorrent.qBittorrent"
Install-Winget "7zip.7zip"
Install-Winget "VideoLAN.VLC"
Install-Winget "Notepad++.Notepad++"
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
