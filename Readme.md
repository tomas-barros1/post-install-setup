# 🚀 Post-Install Setup (Arch Linux & Windows)

Scripts automatizados e modulares de pós-instalação para **Arch Linux** (Wayland / Desktop / WSL) e **Windows** (PowerShell).

---

## 🐧 Arch Linux (100% Interativo com `gum`)

No Arch Linux, o instalador é **totalmente interativo**. Não precisa passar flags nem decorar comandos complexos: basta rodar o script e escolher as opções na interface de terminal visual do **`gum`**.

### 💿 Guia do `archinstall` (Recomendações na Instalação Base)

Caso você instale o Arch Linux utilizando o instalador oficial **`archinstall`**, siga estas orientações para garantir uma base limpa:

- **Type / Profile:** Escolha **`Minimal`** (se for usar Hyprland, Sway ou Noctalia via este script) ou **`Desktop`** (se for usar GNOME).
- **Network Configuration (Rede) — ⚠️ MUITO IMPORTANTE:**
  - Selecione **`NetworkManager`**.
  - ❌ **NUNCA escolha *"Copy ISO configuration"***: essa opção copia as regras temporárias do `systemd-networkd` da ISO, causando conflitos crônicos de sysctl, DNS e disputa de interface com o NetworkManager.
- **Audio Server:** Selecione **`Pipewire`**.
- **Driver Gráfico:** Escolha o driver correspondente ao seu hardware (ex: `AMD / ATI (open-source)`, `Intel` ou `Nvidia`).
- **Additional Packages:** Adicione pelo menos **`git`** e **`curl`**.
- **User Account:** Crie seu usuário e adicione-o como **sudo / wheel**.

---

### 1. Clonar e Executar

```bash
git clone https://github.com/tomas-barros1/post-install-setup.git
cd post-install-setup
chmod +x install.sh
./install.sh
```

---

### 2. O que acontece durante a execução interativa?

Ao rodar `./install.sh`, o script:
1. Verifica os pré-requisitos (`git`, `curl`) e instala o `gum` automaticamente se necessário.
2. Abre um menu interativo para você selecionar o seu ambiente:
   - **Hyprland**: Hyprland + Waybar + Walker + Regreet + Catppuccin
   - **Hyprland (Noctalia)**: Hyprland integrado com a suíte Noctalia Shell
   - **GNOME**: GNOME Desktop com extensões, atalhos e Alacritty
   - **Sway**: Sway WM + Waybar + Walker + Regreet
   - **Arch WSL**: Ambiente Arch WSL focado em ferramentas de desenvolvimento CLI
3. Pergunta interativamente (com confirmação visual):
   - Se deseja habilitar o **Chaotic AUR** (binários pré-compilados do AUR).
   - Se deseja instalar o setup de **Jogos** (Steam nativo via Pacman + Multilib, Vulkan Radeon, Lutris, GameMode, LACT, GOverlay).
   - Se deseja configurar o seu **perfil do Git** (Nome, E-mail e Delta pager).
4. Mostra uma caixa de confirmação estilizada antes de iniciar o processo.

---

## 🪟 Windows (PowerShell)

O script para Windows instala automaticamente os gerenciadores **Winget** e **Chocolatey**, ferramentas de desenvolvimento, terminal moderno, runtimes do Visual C++ e utilitários essenciais.

### ⚠️ Requisitos

1. Abra o **PowerShell** como **Administrador** (botão direito no Menu Iniciar ou Terminal -> *Executar como Administrador*).
2. O Windows bloqueia por padrão scripts locais devido à `ExecutionPolicy`. Para rodar **sem bloqueios e sem frescura**, use a flag `-ExecutionPolicy Bypass`.

---

### ⚡ Como Executar no Windows (Sem Frescura)

#### Opção A — Executar direto em uma única linha (Recomendado):

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\windows\post-install.ps1
```

#### Opção B — Liberar a sessão atual do PowerShell e rodar:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\windows\post-install.ps1
```

> 💡 **Dica (Arquivo baixado da Web):** Se você baixou o repositório em arquivo `.zip` pela internet e o Windows bloqueou os scripts, desbloqueie com:
> ```powershell
> Unblock-File .\windows\post-install.ps1
> ```

---

### 📦 O que o script do Windows instala?

- **Gerenciadores de Pacotes:** `Winget` e `Chocolatey`.
- **Desenvolvimento:** Git, Visual Studio Community, Docker Desktop, Neovim, Python 3.14, FFmpeg, Yaak.
- **Terminal & Shell:** Windows Terminal, PowerShell 7, Starship prompt, fzf, zoxide, bat, Cascadia Code Nerd Font, JetBrains Mono Nerd Font.
- **Aplicações & Utilitários:** Brave Browser, Spotify, Steam, PCSX2, MSI Afterburner + RTSS, SumatraPDF, 7-Zip, VLC, Notepad++, Paint.NET, qBittorrent, Revo Uninstaller, f.lux.
- **Runtimes & Sistema:** Pacotes redistribuíveis Microsoft Visual C++ (2005 até 2015-2022 x86/x64) e restauração do clássico **Windows Photo Viewer**.

---

## 📁 Estrutura do Projeto

```
post-install-setup/
├── install.sh                     # Ponto de entrada interativo com gum
├── lib/                           # Módulos reutilizáveis (Core)
│   ├── log.sh                     # Cores ANSI, logging e sumário final
│   ├── checks.sh                  # Validação de Arch, root, dependências e gum
│   ├── packages.sh                # Pacman, Yay, Chaotic-AUR, AUR Helper
│   └── system.sh                  # Dotfiles (stow), Docker, Fish, Git, UFW, Greeter
├── profiles/                      # Definições de pacotes por ambiente
│   ├── base.env                   # Pacotes CLI universais
│   ├── desktop.env                # Pacotes GUI compartilhados
│   ├── hyprland.sh                # Perfil Hyprland padrão
│   ├── hyprland-noctalia.sh       # Perfil Hyprland com Noctalia
│   ├── gnome.sh                   # Perfil GNOME Desktop
│   ├── sway.sh                    # Perfil Sway WM
│   └── wsl.sh                     # Perfil Arch WSL
├── config/                        # Arquivos de configuração estáticos
│   ├── greeter/                   # Configs de login (Greetd / ReGreet)
│   └── gnome/                     # Scripts de atalhos e extensões do GNOME
└── windows/                       # Automação Windows PowerShell
    ├── post-install.ps1           # Script de pós-instalação do Windows
    └── Restore_Windows_...reg     # Tweaks do registro para o Photo Viewer
```
