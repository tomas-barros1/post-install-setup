\xef\xbb\xbf<#
.SYNOPSIS
    Pós-instalação do Windows (winget + Chocolatey + tweaks).

.PARAMETER InstallWsl
    Habilita o WSL2 e instala o Arch Linux (wsl --install archlinux).
    Depois, dentro do Arch: ./install.sh --profile wsl

.PARAMETER SkipTweaks
    Não aplica os ajustes de sistema (extensões, tema escuro, busca, Photo Viewer).

.PARAMETER SkipUpgrade
    Não roda 'winget upgrade --all' no final.

.EXAMPLE
    .\post-install.ps1 -InstallWsl
#>
[CmdletBinding()]
param(
    [switch]$InstallWsl,
    [switch]$SkipTweaks,
    [switch]$SkipUpgrade
)

$logFile = "$env:USERPROFILE\postinstall_log.txt"
$script:Failed = New-Object System.Collections.Generic.List[string]

# Códigos do winget que significam "nada a fazer" (já instalado / sem atualização)
$WingetOkCodes = @(0, -1978335189, -1978335135)
# Códigos do choco: 0 = ok; 1641 e 3010 = ok, mas pede reinício
$ChocoOkCodes = @(0, 1641, 3010)

function Log {
    param([string]$msg)
    $time = Get-Date -Format "HH:mm:ss"
    "$time - $msg" | Tee-Object -FilePath $logFile -Append
}

function Add-Failure {
    param([string]$item)
    $script:Failed.Add($item)
}

function Install-Winget {
    param([Parameter(Mandatory)][string]$Id)
    Log "Instalando (winget): $Id"
    winget install --id $Id -e --accept-source-agreements --accept-package-agreements
    if ($WingetOkCodes -notcontains $LASTEXITCODE) {
        Log "FALHOU (winget $Id): código $LASTEXITCODE"
        Add-Failure "winget:$Id"
    }
}

function Install-Choco {
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Log "FALHOU (choco $Id): Chocolatey indisponível"
        Add-Failure "choco:$Id"
        return
    }
    Log "Instalando (choco): $Id"
    choco install $Id -y
    if ($ChocoOkCodes -notcontains $LASTEXITCODE) {
        Log "FALHOU (choco $Id): código $LASTEXITCODE"
        Add-Failure "choco:$Id"
    }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
            Log "AVISO: winget instalado mas não reconhecido nesta sessão. Reabra o PowerShell e rode de novo."
            exit 1
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
            Log "AVISO: choco instalado mas não reconhecido nesta sessão."
            Add-Failure "choco:indisponivel"
        }
    }
    catch {
        Log "ERRO ao instalar Chocolatey: $($_.Exception.Message)"
        Add-Failure "choco:instalacao"
    }
}

function Set-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = 'DWord'
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
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

function Set-SystemTweaks {
    Log "Aplicando ajustes do sistema (usuário atual)..."
    try {
        $advanced = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-RegValue $advanced "HideFileExt" 0      # mostrar extensões
        Set-RegValue $advanced "Hidden" 1           # mostrar arquivos ocultos

        $theme = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        Set-RegValue $theme "AppsUseLightTheme" 0   # tema escuro (apps)
        Set-RegValue $theme "SystemUsesLightTheme" 0 # tema escuro (sistema)

        # Sem sugestões da web (Bing) na busca do menu Iniciar
        Set-RegValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1

        Log "Ajustes aplicados. Faça logoff/login (ou reinicie o Explorer) para ver tudo."
    }
    catch {
        Log "ERRO nos ajustes do sistema: $($_.Exception.Message)"
        Add-Failure "tweaks"
    }

    Restore-PhotoViewer
}

# Starship e zoxide são instalados, mas só funcionam se o $PROFILE os inicializar.
function Add-ShellProfile {
    Log "Configurando o profile do PowerShell (starship + zoxide)..."

    $docs = [Environment]::GetFolderPath('MyDocuments')
    $targets = @(
        (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
    )
    $marker = '# >>> post-install-setup >>>'
    $block = @'
# >>> post-install-setup >>>
if (Get-Command starship -ErrorAction SilentlyContinue) { Invoke-Expression (&starship init powershell) }
if (Get-Command zoxide -ErrorAction SilentlyContinue) { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }
# <<< post-install-setup <<<
'@

    foreach ($target in $targets) {
        try {
            $dir = Split-Path $target
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

            if ((Test-Path $target) -and (Select-String -Path $target -SimpleMatch $marker -Quiet)) {
                Log "  profile já configurado: $target"
                continue
            }
            Add-Content -Path $target -Value "`n$block"
            Log "  profile atualizado: $target"
        }
        catch {
            Log "ERRO ao atualizar $target : $($_.Exception.Message)"
            Add-Failure "profile:$target"
        }
    }
}

function Install-WslArch {
    Log "Habilitando WSL2..."
    wsl --install --no-distribution
    if ($LASTEXITCODE -ne 0) {
        Log "AVISO: wsl --install retornou $LASTEXITCODE (pode exigir reinício do Windows)."
        Add-Failure "wsl:install"
    }

    Log "Instalando Arch Linux no WSL..."
    wsl --install archlinux
    if ($LASTEXITCODE -ne 0) {
        Log "AVISO: wsl --install archlinux retornou $LASTEXITCODE. Reinicie o Windows e rode de novo com -InstallWsl."
        Add-Failure "wsl:archlinux"
    } else {
        Log "Arch WSL pronto. Dentro dele: clone o repositório e rode ./install.sh --profile wsl"
    }
}

# ================================
# INÍCIO
# ================================
if (-not (Test-Admin)) {
    Write-Host "Rode este script como Administrador (winget/choco precisam de elevação)." -ForegroundColor Red
    exit 1
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
# VISUAL C++ REDISTRIBUTABLES (2005 até 2015-2022)
# ================================
Install-Winget "Microsoft.VCRedist.2005.x86"
Install-Winget "Microsoft.VCRedist.2005.x64"
Install-Winget "Microsoft.VCRedist.2008.x86"
Install-Winget "Microsoft.VCRedist.2008.x64"
Install-Winget "Microsoft.VCRedist.2010.x86"
Install-Winget "Microsoft.VCRedist.2010.x64"
Install-Winget "Microsoft.VCRedist.2012.x86"
Install-Winget "Microsoft.VCRedist.2012.x64"
Install-Winget "Microsoft.VCRedist.2013.x86"
Install-Winget "Microsoft.VCRedist.2013.x64"
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
# CONFIGURAÇÃO
# ================================
Refresh-Env
Add-ShellProfile

if (-not $SkipTweaks) {
    Set-SystemTweaks
}

if ($InstallWsl) {
    Install-WslArch
}

# ================================
# FINAL
# ================================
if (-not $SkipUpgrade) {
    Log "Atualizando tudo..."
    winget upgrade --all --accept-source-agreements --accept-package-agreements
}

if ($script:Failed.Count -gt 0) {
    Log "=== FINALIZADO COM FALHAS ($($script:Failed.Count)) ==="
    foreach ($item in $script:Failed) { Log "  - $item" }
} else {
    Log "=== FINALIZADO SEM FALHAS ==="
}
Write-Host "Acabou! Log em: $logFile"
