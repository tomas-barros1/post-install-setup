<#
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
    [switch]$SkipUpgrade,
    [string]$GitUserName = 'tomas-barros1',
    [string]$GitUserEmail = 'tomasabbarros3@gmail.com',
    [string]$DotfilesPath = "$env:USERPROFILE\Desktop\dotfiles",
    [string]$DotfilesRepoUrl = 'https://github.com/tomas-barros1/dotfiles',
    [string[]]$PowerShellModules = @('PSReadLine', 'PSFzf'),
    [string]$NeovimConfigPath = "$env:USERPROFILE\Desktop\astro-nvim\.config\nvim"
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

function Ensure-Scoop {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Log "Scoop já instalado: $(scoop --version)"
        return
    }

    Log "Scoop não encontrado. Instalando..."

    try {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod -Uri "https://get.scoop.sh" -UseBasicParsing | Invoke-Expression

        Refresh-Env

        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Log "Scoop instalado com sucesso: $(scoop --version)"
        } else {
            Log "AVISO: scoop instalado mas não reconhecido nesta sessão."
            Add-Failure "scoop:indisponivel"
        }
    }
    catch {
        Log "ERRO ao instalar Scoop: $($_.Exception.Message)"
        Add-Failure "scoop:instalacao"
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

function Configure-Git {
    Log "Configurando o Git..."

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Log "AVISO: git não encontrado no PATH. Pulando configuração do Git."
        Add-Failure "git:nao-encontrado"
        return
    }

    try {
        git config --global core.pager delta
        git config --global interactive.diffFilter "delta --color-only"
        git config --global delta.navigate true
        git config --global delta.dark true
        git config --global merge.conflictStyle zdiff3
        git config --global user.name $GitUserName
        git config --global user.email $GitUserEmail

        Log "Git configurado (usuario: $GitUserName, email: $GitUserEmail)"
    }
    catch {
        Log "ERRO ao configurar Git: $($_.Exception.Message)"
        Add-Failure "git:config"
    }
}

function Configure-Dotfiles {
    Log "Configurando dotfiles ($DotfilesPath)..."

    if (-not (Test-Path $DotfilesPath)) {
        if ($DotfilesRepoUrl) {
            Log "Repositório não encontrado localmente. Clonando de $DotfilesRepoUrl..."
            try {
                git clone $DotfilesRepoUrl $DotfilesPath
                if ($LASTEXITCODE -ne 0) {
                    Log "FALHOU ao clonar dotfiles: código $LASTEXITCODE"
                    Add-Failure "dotfiles:clone"
                    return
                }
            }
            catch {
                Log "ERRO ao clonar dotfiles: $($_.Exception.Message)"
                Add-Failure "dotfiles:clone"
                return
            }
        } else {
            Log "AVISO: diretório de dotfiles não encontrado em $DotfilesPath e nenhuma URL de repo informada. Pulando."
            Add-Failure "dotfiles:nao-encontrado"
            return
        }
    }

    # --- PowerShell 7 profile ---
    $psProfileTarget = Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
    $psProfileSource = Get-ChildItem -Path $DotfilesPath -Filter 'Microsoft.PowerShell_profile.ps1' -Recurse | Select-Object -First 1

    if ($psProfileSource) {
        try {
            $dir = Split-Path $psProfileTarget
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            # Faz backup se já existir
            if (Test-Path $psProfileTarget) {
                Rename-Item -Path $psProfileTarget -NewName "$psProfileTarget.bak.$(Get-Date -Format 'yyyyMMddHHmmss')" -Force | Out-Null
            }
            Copy-Item -Path $psProfileSource.FullName -Destination $psProfileTarget -Force
            Log "Profile do PowerShell 7 aplicado: $psProfileTarget"
        }
        catch {
            Log "ERRO ao aplicar profile do PowerShell: $($_.Exception.Message)"
            Add-Failure "dotfiles:ps-profile"
        }
    } else {
        Log "AVISO: Microsoft.PowerShell_profile.ps1 não encontrado nos dotfiles. Pulando PowerShell profile."
        Add-Failure "dotfiles:ps-profile-nao-encontrado"
    }

    # --- Windows Terminal settings ---
    $wtLocalState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    $wtSettingsTarget = Join-Path $wtLocalState 'settings.json'
    $wtSettingsSource = Get-ChildItem -Path $DotfilesPath -Filter 'settings.json' -Recurse | Select-Object -First 1

    if ($wtSettingsSource) {
        try {
            if (-not (Test-Path $wtLocalState)) { New-Item -ItemType Directory -Path $wtLocalState -Force | Out-Null }
            if (Test-Path $wtSettingsTarget) {
                Rename-Item -Path $wtSettingsTarget -NewName "$wtSettingsTarget.bak.$(Get-Date -Format 'yyyyMMddHHmmss')" -Force | Out-Null
            }
            Copy-Item -Path $wtSettingsSource.FullName -Destination $wtSettingsTarget -Force
            Log "Configuração do Windows Terminal aplicada: $wtSettingsTarget"
        }
        catch {
            Log "ERRO ao aplicar configuração do Windows Terminal: $($_.Exception.Message)"
            Add-Failure "dotfiles:wt-settings"
        }
    } else {
        Log "AVISO: settings.json do Windows Terminal não encontrado nos dotfiles. Pulando."
        Add-Failure "dotfiles:wt-settings-nao-encontrado"
    }

    # --- Outros arquivos comuns (profiles.json, etc.) ---
    foreach ($file in @('profiles.json', 'defaults.json')) {
        $src = Get-ChildItem -Path $DotfilesPath -Filter $file -Recurse | Select-Object -First 1
        if ($src) {
            $dst = Join-Path $wtLocalState $file
            try {
                if (Test-Path $dst) {
                    Rename-Item -Path $dst -NewName "$dst.bak.$(Get-Date -Format 'yyyyMMddHHmmss')" -Force | Out-Null
                }
                Copy-Item -Path $src.FullName -Destination $dst -Force
                Log "Arquivo do Windows Terminal aplicado: $file"
            }
            catch {
                Log "ERRO ao aplicar $file: $($_.Exception.Message)"
                Add-Failure "dotfiles:$file"
            }
        }
    }
}

function Install-PowerShellModule {
    param([string[]]$Modules)

    if ($Modules.Count -eq 0) {
        Log "Nenhum módulo do PowerShell informado. Pulando."
        return
    }

    Log "Instalando módulos do PowerShell 7..."

    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop | Out-Null
    }
    catch {
        Log "AVISO: não foi possível confiar na PSGallery. Pulando instalação de módulos."
        Add-Failure "psmodule:gallery"
        return
    }

    foreach ($mod in $Modules) {
        try {
            Log "  Instalando módulo: $mod"
            Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop | Out-Null
            Log "  OK: $mod"
        }
        catch {
            Log "  FALHOU ao instalar $mod: $($_.Exception.Message)"
            Add-Failure "psmodule:$mod"
        }
    }
}

function Configure-Neovim {
    Log "Configurando o Neovim (astro-nvim)..."

    if (-not (Test-Path $NeovimConfigPath)) {
        Log "AVISO: caminho do astro-nvim não encontrado em $NeovimConfigPath. Pulando configuração do Neovim."
        Add-Failure "neovim:nao-encontrado"
        return
    }

    $nvimTarget = Join-Path $env:LOCALAPPDATA 'nvim'

    try {
        if (Test-Path $nvimTarget) {
            $backup = "$nvimTarget.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Move-Item -Path $nvimTarget -Destination $backup -Force
            Log "  Backup do nvim existente: $backup"
        }

        Copy-Item -Path $NeovimConfigPath -Destination $nvimTarget -Recurse -Force
        Log "Configuração do Neovim aplicada: $nvimTarget"
    }
    catch {
        Log "ERRO ao configurar Neovim: $($_.Exception.Message)"
        Add-Failure "neovim:config"
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
Install-Winget "OpenJS.NodeJS.LTS"
Install-Winget "GoLang.Go"
Install-Winget "Rustlang.Rustup"
Install-Winget "Python.Python"
Install-Winget "Python.Launcher"
Install-Winget "Gyan.FFmpeg"
Install-Winget "Microsoft.PowerToys"

# ================================
# TERMINAL / SHELL
# ================================
Install-Winget "Microsoft.WindowsTerminal"
Install-Winget "Microsoft.PowerShell"
Install-Winget "Starship.Starship"
Install-Winget "junegunn.fzf"
Install-Winget "ajeetdsouza.zoxide"
Install-Winget "sharkdp.bat"
Install-Winget "dandavison.delta"
Install-Winget "BurntSushi.ripgrep.MSVC"
Install-Winget "sharkdp.fd"
Install-Winget "eza-community.eza"
Install-Winget "JesseDuffield.lazygit"
Install-Winget "JesseDuffield.Lazydocker"

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
Install-Winget "cjpais.Handy"
Install-Winget "yt-dlp.yt-dlp"

# ================================
# APPS
# ================================
Install-Winget "Spotify.Spotify"
Install-Winget "Valve.Steam"
Install-Winget "Guru3D.Afterburner"
Install-Winget "Guru3D.RTSS"
Install-Winget "InputNet.Helium"

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
Ensure-Scoop
Configure-Git
Configure-Dotfiles
Install-PowerShellModule -Modules $PowerShellModules
Configure-Neovim

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
