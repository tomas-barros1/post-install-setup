# 🚀 Post-Install Setup (Arch Linux & Windows)

Scripts automatizados e modulares de pós-instalação para **Arch Linux** (Wayland / WSL) e **Windows** (PowerShell).

---

## 🐧 Arch Linux (interativo com `gum` ou não interativo)

Por padrão o instalador é **interativo**: basta rodar o script e escolher as opções na interface do **`gum`**. Para automação (VM, testes, reinstalações) há flags — veja [Flags e variáveis](#flags-e-variáveis).

### 💿 Guia do `archinstall` (Recomendações na Instalação Base)

Caso você instale o Arch Linux utilizando o instalador oficial **`archinstall`**, siga estas orientações para garantir uma base limpa:

- **Type / Profile:** Escolha **`Minimal`** (Hyprland, Sway ou Noctalia via este script).
- **Network Configuration (Rede) — ⚠️ MUITO IMPORTANTE:**
  - Escolha uma instalação **minimalista** de rede. O script usa **`iwd` + `impala`** para Wi‑Fi (o próprio `iwd` faz o DHCP) e **`systemd-resolved`** só para DNS, e desativa o `NetworkManager` e o `systemd-networkd`.
  - ❌ **NUNCA escolha _"Copy ISO configuration"_**: essa opção copia as regras temporárias do `systemd-networkd` da ISO, causando conflitos crônicos de sysctl, DNS e disputa de interface.
- **Audio Server:** Pode deixar em branco; o script instala e habilita **PipeWire + WirePlumber** de forma explícita.
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

Simular sem alterar nada (mostra perfil e lista de pacotes):

```bash
./install.sh --profile hyprland --dry-run
```

---

### Flags e variáveis

| Flag | Efeito |
| --- | --- |
| `-p, --profile NOME` | `hyprland`, `hyprland-noctalia`, `sway` ou `wsl` |
| `-y, --yes` | Não pergunta nada, aceita os padrões (exige `--profile`) |
| `--dry-run` | Mostra o plano e sai |
| `--[no-]chaotic` | Chaotic AUR |
| `--[no-]gaming` | Setup de jogos (a GPU é detectada: AMD, Intel ou NVIDIA) |
| `--[no-]mirrors` | Otimizar mirrors com `reflector` |
| `--[no-]autologin` | Greeter com/sem login automático |
| `--[no-]git` | Configuração do Git |

Exemplo não interativo: `GIT_USER_NAME="Fulano" GIT_USER_EMAIL=f@x.com ./install.sh -y -p hyprland --no-gaming`

Variáveis de ambiente opcionais: `DOTFILES_REPO`, `DOTFILES_DIR`, `POST_INSTALL_LOCALE` (padrão `pt_BR.UTF-8`), `POST_INSTALL_TIMEZONE` (padrão `America/Sao_Paulo`), `POST_INSTALL_REGDOM` (padrão `BR`), `POST_INSTALL_MIRROR_COUNTRIES`, `POST_INSTALL_WIRED_NETWORKD`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, `POST_INSTALL_LOGFILE`.

---

### 2. O que acontece durante a execução interativa?

Ao rodar `./install.sh`, o script:

1. Verifica os pré-requisitos (`git`, `curl`) e instala o `gum` automaticamente se necessário.
2. Abre um menu interativo para você selecionar o seu ambiente:
   - **Hyprland**: Hyprland + Waybar + Walker + Regreet + Catppuccin
   - **Hyprland (Noctalia)**: Hyprland integrado com a suíte Noctalia Shell
   - **Sway**: Sway WM + Waybar + Walker + Regreet
   - **Arch WSL**: Ambiente Arch WSL focado em ferramentas de desenvolvimento CLI
3. Nos perfis **window manager** (`Hyprland`, `Hyprland (Noctalia)` e `Sway`), o script:
   - Instala **`iwd`**, **`impala`** e `wireless-regdb` (e define o regdomain, padrão `BR`).
   - Masca o **`NetworkManager`** e habilita `iwd` (puro) e `systemd-resolved` (DNS, que o `iwd` usa por padrão). Cabo **não** é gerenciado; para DHCP em ethernet rode com `POST_INSTALL_WIRED_NETWORKD=true`. **A troca de rede só vale a partir do próximo boot**, e é feita por último para não interromper downloads.
   - Aplica ajustes para tentar desativar o **power save do Wi‑Fi** (o tweak do `iwlwifi` só se houver placa Intel).
   - Configura o **UFW** (`deny incoming` / `allow outgoing`, SSH só se o `sshd` estiver habilitado) e habilita o `ufw.service` para persistir no boot.
   - Habilita o **Bluetooth** (`bluetooth.service`) sem iniciar o applet do Blueman junto com a sessão.
   - Habilita o **PipeWire/WirePlumber** para áudio.
4. Pergunta interativamente (com confirmação visual):

   - Se deseja habilitar o **Chaotic AUR** (binários pré-compilados do AUR).
   - Se deseja instalar o setup de **Jogos** (Steam nativo via Pacman + Multilib, Vulkan Radeon, Lutris, GameMode, LACT, GOverlay).
   - Se deseja configurar o seu **perfil do Git** (Nome, E-mail e Delta pager).
   - Se deseja otimizar os **mirrors** com `reflector` e (nos perfis com greeter) o **login automático**.

5. Mostra uma caixa de confirmação estilizada antes de iniciar o processo.
6. Cria os diretórios XDG `~/Downloads`, `~/Documentos`, `~/Imagens`, `~/Músicas`, `~/Vídeos` e `~/Projetos` e os adiciona como bookmarks do **Nautilus** (em todos os perfis).
7. Configura os agentes de IA instalados com **ai-memory** (memória de longo prazo) e **RTK** (otimização de comandos), incluindo Codex, OpenCode, Cursor, Copilot CLI, Antigravity CLI, Gemini CLI e Claude Code quando presentes.
8. Instala o hook `/etc/pacman.d/hooks/ai-agents-refresh.hook` e o script `/usr/local/bin/ai-agents-refresh`. Após atualizações de `ai-memory-bin`, `rtk-bin` ou dos CLIs dos agentes, as integrações são regeneradas automaticamente. O refresh é agendado alguns segundos depois da transação (via `systemd-run`) para não competir com o reload do user manager; o log fica em `/var/log/ai-agents-refresh.log`.
9. Aplica higiene/manutenção do sistema: limita o cache do pacman (`paccache`), limita o journal a 500 MB. Não configura swap/zram nem `fstrim.timer`.
10. Ajusta o `pacman.conf` (`Color`, `ILoveCandy`, `ParallelDownloads = 10`) e o `makepkg.conf` (`MAKEFLAGS=-j$(nproc)`).

### Comportamento e segurança

- **Etapas não-críticas não derrubam o script**: se uma falhar, ela vai para a lista de falhas do resumo final e as demais continuam. Só a atualização/instalação dos pacotes oficiais aborta tudo.
- **Pode rodar de novo**: arquivos de `/etc` só são reescritos se o conteúdo mudou, sempre com backup `*.bak.<data>`.
- **Dotfiles**: o `stow` **nunca usa `--adopt`**. Se um arquivo existente conflita, ele é movido para `*.bak.<data>` e o link é criado; o repositório de dotfiles não é modificado.
- **AUR**: os pacotes são instalados com `--noconfirm` (PKGBUILDs não são revisados) e pacotes `-git` compilam o HEAD do upstream.
- **Autologin**: o `initial_session` do greetd entra sem senha — só recomendado com disco criptografado. Nele o `gnome-keyring` não é destravado (só no login pelo regreet). Use `--no-autologin` para desativar.
- **Log**: `~/post-install-*.log` contém as mensagens do script **e** a saída do pacman/yay.

### Se o Wi‑Fi não conectar depois do reboot

```bash
impala                 # TUI do iwd
iwctl station wlan0 connect "NOME_DA_REDE"
systemctl status iwd systemd-resolved
```

Para voltar ao NetworkManager: `sudo systemctl unmask NetworkManager && sudo systemctl enable --now NetworkManager` (e desabilite o `iwd`).

> 💡 **ai-memory + RTK:** os pacotes `ai-memory-bin` e `rtk-bin` vêm do AUR. O `ai-memory` roda como serviço de usuário (`ai-memory.service`) em `127.0.0.1:49374`; o `rtk` é configurado globalmente para cada agente detectado. Depois de instalar um novo agente, rode `ai-memory setup --yes --agent <agente>` e o comando RTK correspondente (`rtk init -g --codex`, `rtk init -g --opencode`, `rtk init -g --agent cursor`, etc.) ou simplesmente execute `sudo /usr/local/bin/ai-agents-refresh`.

---

## 🪟 Windows (PowerShell)

O script para Windows instala automaticamente os gerenciadores **Winget** e **Chocolatey**, ferramentas de desenvolvimento, terminal moderno, runtimes do Visual C++ e utilitários essenciais.

### ⚠️ Requisitos

1. Abra o **PowerShell** como **Administrador** (botão direito no Menu Iniciar ou Terminal -> _Executar como Administrador_).
2. O Windows bloqueia por padrão scripts locais devido à `ExecutionPolicy`. Para rodar **sem bloqueios e sem frescura**, use a flag `-ExecutionPolicy Bypass`.

---

### ⚡ Como Executar no Windows (Sem Frescura)

Parâmetros opcionais: `-InstallWsl` (habilita o WSL2 e instala o Arch — depois rode `./install.sh --profile wsl` dentro dele), `-SkipTweaks` (não altera extensões/tema/busca/Photo Viewer) e `-SkipUpgrade` (não roda `winget upgrade --all`). Ao final o script lista os itens que falharam.

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
>
> ```powershell
> Unblock-File .\windows\post-install.ps1
> ```

---

### 📦 O que o script do Windows instala?

- **Gerenciadores de Pacotes:** `Winget` e `Chocolatey`.
- **Desenvolvimento:** Git, Visual Studio Community, Docker Desktop, Neovim, Python 3.14, FFmpeg, Yaak.
- **Terminal & Shell:** Windows Terminal, PowerShell 7, Starship prompt, fzf, zoxide, bat, Cascadia Code Nerd Font, JetBrains Mono Nerd Font.
- **Aplicações & Utilitários:** Brave Browser, Spotify, Steam, PCSX2, MSI Afterburner + RTSS, SumatraPDF, 7-Zip, VLC, Notepad++, Paint.NET, qBittorrent, Revo Uninstaller, f.lux.
- **Runtimes & Sistema:** Pacotes redistribuíveis Microsoft Visual C++ (2005, 2008, 2010, 2012, 2013 e 2015-2022, x86/x64).
- **Ajustes:** profile do PowerShell inicializando **starship** e **zoxide**, extensões e arquivos ocultos visíveis, tema escuro, busca sem sugestões do Bing e restauração do clássico **Windows Photo Viewer**.

---

## 📁 Estrutura do Projeto

```
post-install-setup/
├── install.sh                     # Ponto de entrada (interativo com gum ou via flags)
├── .github/workflows/lint.yml     # CI: ShellCheck, shfmt, PSScriptAnalyzer e validação dos perfis
├── .gitignore                     # Logs, backups e arquivos de agentes
├── tests/
│   └── check-packages.sh          # Valida perfis e existência dos pacotes (rodado num container Arch)
├── .shellcheckrc                  # Exceções para arquivos carregados via source
├── .editorconfig                  # Padronização de indentação/fim de linha
├── LICENSE                        # Licença MIT
├── lib/                           # Módulos reutilizáveis (Core)
│   ├── log.sh                     # Cores ANSI, logging e sumário final
│   ├── checks.sh                  # Validação de Arch, root, rede, disco, dependências, gum e sudo keepalive
│   ├── packages.sh                # Pacman, Yay, Chaotic-AUR, mirrors, pacman.conf/makepkg.conf
│   ├── network.sh                 # iwd, systemd-resolved, regdomain, power save do Wi‑Fi e UFW
│   ├── system.sh                  # Locale, dotfiles (stow), Docker, Fish, Git, Bluetooth, áudio, manutenção, agentes de IA, Greeter, Gaming, XDG/Bookmarks
│   ├── ai-agents-refresh.sh       # Template do script que atualiza ai-memory/RTK após upgrades
│   └── ai-agents-refresh.hook     # Template do hook do pacman para agentes de IA
├── profiles/                      # Definições de pacotes por ambiente
│   ├── base.env                   # Pacotes CLI universais
│   ├── desktop.env                # Pacotes GUI compartilhados
│   ├── wayland-wm.env             # Stack compartilhado de WMs Wayland (Fcitx, Foot, Walker, etc.)
│   ├── hyprland.sh                # Perfil Hyprland padrão
│   ├── hyprland-noctalia.sh       # Perfil Hyprland com Noctalia
│   ├── sway.sh                    # Perfil Sway WM
│   └── wsl.sh                     # Perfil Arch WSL
├── config/                        # Arquivos de configuração estáticos
│   └── greeter/                   # Configs de login (Greetd / ReGreet); @USER@ é substituído pelo seu usuário
└── windows/                       # Automação Windows PowerShell
    ├── post-install.ps1           # Script de pós-instalação do Windows
    └── Restore_Windows_...reg     # Tweaks do registro para o Photo Viewer
```
