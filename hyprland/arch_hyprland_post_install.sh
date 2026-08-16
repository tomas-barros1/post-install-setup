#!/bin/bash

set -euo pipefail

VERSION="2.1.0"
LOGFILE="$HOME/post-install-$(date +%Y%m%d-%H%M%S).log"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
FAILED_PACKAGES=()
FAILED_STEPS=()

# =============================
# Cores para output
# =============================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✔${NC} $1" | tee -a "$LOGFILE"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"; }
log_error() { echo -e "${RED}✖${NC} $1" | tee -a "$LOGFILE"; }
log_step() { echo -e "${BLUE}➜${NC} $1" | tee -a "$LOGFILE"; }

# =============================
# Arrays de pacotes
# =============================

PACMAN_PACKAGES=(
  # Desenvolvimento
  "git"
  "neovim"
  "python-pip"
  "docker"
  "docker-compose"
  "opencode"

  # Tema de ícones
  "tela-circle-icon-theme-purple"

  # Tema QT
  "breeze"
  "breeze-icons"

  # Input method
  "fcitx5"

  # Terminal & CLI Tools
  "fish"
  "less"
  "mise"
  "usage"
  "foot"
  "tmux"
  "networkmanager"
  "stow"
  "fzf"
  "bat"
  "eza"
  "ripgrep"
  "fd"
  "btop"
  "zoxide"
  "starship"
  "lazygit"
  "lazydocker"
  "github-cli"
  "git-delta"
  "fastfetch"
  "reflector"
  "yazi"
  "tldr"
  "yt-dlp"
  "unrar"
  "gum"

  # Fontes
  "ttf-cascadia-code-nerd"
  "ttf-jetbrains-mono-nerd"
  "inter-font"
  "noto-fonts"
  "noto-fonts-emoji"

  # Aplicações
  "gimp"
  "libreoffice-fresh"
  "qbittorrent"
  "flatpak"
  "nautilus"
  "pavucontrol"
  "seahorse"
  "gnome-text-editor"
  "gnome-calculator"
  "gnome-system-monitor"
  "gnome-software"
  "gnome-font-viewer"
  "gnome-calendar"
  "gnome-disk-utility"
  "papers"
  "loupe"
  "obs-studio"

  # Hyprland e Wayland
  "hyprland"
  "uwsm"
  "xdg-desktop-portal"
  "xdg-desktop-portal-hyprland"
  "wl-clipboard"
  "swaybg"
  "flameshot"
  "hyprshot"
  "hyprsunset"
  "swaync"
  "waybar"
  "qt5-wayland"
  "qt6-wayland"
  "nwg-look"
  "wdisplays"
  "wlr-randr"
  "network-manager-applet"
  "playerctl"
  "greetd-regreet"

  # Utilitários
  "wget"
  "imv"
  "aria2"
  "curl"
  "unzip"
  "zip"
  "ufw"
  "ddcutil"
  "lxappearance"
  "xdg-utils"
  "grim"
  "slurp"
  "ntfs-3g"
  "ntfsprogs"
  "tesseract"
  "tesseract-data-por"
  "bluez"
  "bluez-utils"
  "blueman"
  "openbsd-netcat"
)

AUR_PACKAGES=(
  "helium-browser-bin"
  "catppuccin-gtk-theme-mocha"
  "obsidian"
  "visual-studio-code-bin"
  "walker-bin"
  "elephant-bin"
  "elephant-clipboard-bin"
  "elephant-desktopapplications-bin"
  "elephant-providerlist-bin"
  "elephant-runner-bin"
  "elephant-archlinuxpkgs-bin"
  "elephant-calc-bin"
  "elephant-symbols-bin"
  "elephant-todo-bin"
  "elephant-websearch-bin"
  "qt5ct-kde"
  "qt6ct-kde"
  "polkit-gnome-git"
  "sunsetr-bin"
  "waybar-weather"
  "nautilus-open-any-terminal-git"
  "peazip"
  "spotify"
  "ttf-ms-fonts"
)

DOTFILES_DIRS=(
  "foot"
  "fish"
  "zed"
  "hypr"
  "swaync"
  "waybar-hyprland"
  "walker"
  "lazy-nvim"
  "tmux"
)

# =============================
# Verificações iniciais
# =============================

check_arch_linux() {
  if [[ ! -f /etc/arch-release ]]; then
    log_error "Este script é apenas para Arch Linux!"
    exit 1
  fi
}

check_not_root() {
  if [[ $EUID -eq 0 ]]; then
    log_error "Não execute este script como root. Use um usuário normal."
    exit 1
  fi
}

check_pre_dependencies() {
  local missing=()
  local required=("git" "curl")

  for cmd in "${required[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Dependências ausentes: ${missing[*]}"
    echo ""
    echo "  Instale com:"
    echo "  sudo pacman -S ${missing[*]}"
    echo ""
    exit 1
  fi

  log_info "Dependências pré-instalação verificadas: git, curl"
}

# =============================
# Funções de instalação
# =============================

install_pacman_packages() {
  log_step "Instalando pacotes oficiais (${#PACMAN_PACKAGES[@]} pacotes)..."

  sudo pacman -Syu --noconfirm

  if ! sudo pacman -S --noconfirm --needed "${PACMAN_PACKAGES[@]}"; then
    log_warn "Falha na instalação em lote. Tentando pacote por pacote..."
    for pkg in "${PACMAN_PACKAGES[@]}"; do
      if ! sudo pacman -S --noconfirm --needed "$pkg"; then
        log_warn "Falha ao instalar: $pkg"
        FAILED_PACKAGES+=("$pkg (pacman)")
      fi
    done
  fi

  log_info "Pacotes oficiais processados!"
}

install_yay() {
  if command -v yay &>/dev/null; then
    log_info "yay já instalado"
    return 0
  fi

  log_step "Instalando yay (AUR helper)..."
  local tmp_dir
  tmp_dir=$(mktemp -d)

  if ! sudo pacman -S --needed --noconfirm git base-devel; then
    log_warn "Falha ao instalar dependências de build do yay"
    FAILED_STEPS+=("yay:base-devel")
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! git clone https://aur.archlinux.org/yay.git "$tmp_dir/yay"; then
    log_warn "Falha ao clonar repositório do yay"
    FAILED_STEPS+=("yay:clone")
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! (cd "$tmp_dir/yay" && makepkg -si --noconfirm); then
    log_warn "Falha ao compilar/instalar yay"
    FAILED_STEPS+=("yay:makepkg")
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
  log_info "yay instalado!"
}

setup_chaotic_aur() {
  if grep -q "chaotic-aur" /etc/pacman.conf 2>/dev/null; then
    log_info "Chaotic AUR já configurado"
    return 0
  fi

  log_step "Configurando Chaotic AUR..."

  if ! sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com; then
    log_warn "Falha ao receber chave do Chaotic AUR"
    FAILED_STEPS+=("chaotic-aur:recv-key")
    return 1
  fi

  if ! sudo pacman-key --lsign-key 3056513887B78AEB; then
    log_warn "Falha ao assinar chave do Chaotic AUR"
    FAILED_STEPS+=("chaotic-aur:lsign-key")
    return 1
  fi

  if ! sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' ||
     ! sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'; then
    log_warn "Falha ao instalar keyring/mirrorlist do Chaotic AUR"
    FAILED_STEPS+=("chaotic-aur:packages")
    return 1
  fi

  if ! grep -q "chaotic-aur" /etc/pacman.conf; then
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
  fi

  if ! sudo pacman -Syu --noconfirm; then
    log_warn "Falha ao sincronizar pacman após adicionar Chaotic AUR"
    FAILED_STEPS+=("chaotic-aur:sync")
    return 1
  fi

  log_info "Chaotic AUR configurado!"
}

install_aur_packages() {
  log_step "Instalando pacotes do AUR (${#AUR_PACKAGES[@]} pacotes)..."

  if ! yay -S --noconfirm --needed "${AUR_PACKAGES[@]}"; then
    log_warn "Falha na instalação em lote. Tentando pacote por pacote..."
    for pkg in "${AUR_PACKAGES[@]}"; do
      if ! yay -S --noconfirm --needed "$pkg"; then
        log_warn "Falha ao instalar: $pkg"
        FAILED_PACKAGES+=("$pkg (aur)")
      fi
    done
  fi

  log_info "Pacotes AUR processados!"
}

setup_dotfiles() {
  local dotfiles_dir="$HOME/dotfiles"

  if [[ ! -d "$dotfiles_dir" ]]; then
    log_step "Clonando dotfiles..."
    if ! git clone https://github.com/tomas-barros1/dotfiles "$dotfiles_dir"; then
      log_warn "Falha ao clonar dotfiles"
      FAILED_STEPS+=("dotfiles:clone")
      return 1
    fi
  else
    log_step "Atualizando dotfiles..."
    if ! git -C "$dotfiles_dir" pull; then
      log_warn "Falha ao atualizar dotfiles"
      FAILED_STEPS+=("dotfiles:pull")
    fi
  fi

  # Cria ~/.local como diretório real (não symlink), pois dentro de dotfiles
  # existe a pasta scripts/ com alguns scripts que preciso manter linkados.
  mkdir -p "$HOME/.local"

  log_step "Aplicando stow nos dotfiles..."
  cd "$dotfiles_dir"

  for dir in "${DOTFILES_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
      if stow -R "$dir" 2>/dev/null; then
        log_info "  ✓ $dir"
      else
        log_warn "  ✗ $dir (conflito ou erro)"
        FAILED_STEPS+=("stow:$dir")
      fi
    else
      log_warn "  Diretório $dir não encontrado em dotfiles"
    fi
  done

  # --adopt: diferente do loop acima (-R), aqui os arquivos locais existentes
  # em scripts/ "vencem" e são absorvidos para dentro do repo de dotfiles.
  if [[ -d "scripts" ]]; then
    if ! stow --adopt scripts/; then
      log_warn "  ✗ scripts (falha no stow --adopt)"
      FAILED_STEPS+=("stow:scripts")
    fi
  else
    log_warn "  Diretório scripts não encontrado em dotfiles"
  fi

  cd - >/dev/null
}

setup_docker() {
  log_step "Configurando Docker..."

  if ! sudo systemctl enable docker.service; then
    log_warn "Falha ao habilitar docker.service"
    FAILED_STEPS+=("docker:enable")
  fi

  if ! groups "$USER" | grep -q docker; then
    if sudo usermod -aG docker "$USER"; then
      log_warn "Grupo docker adicionado. FAÇA LOGOUT/LOGIN para aplicar!"
    else
      log_warn "Falha ao adicionar usuário ao grupo docker"
      FAILED_STEPS+=("docker:usermod")
    fi
  else
    log_info "Usuário já no grupo docker"
  fi
}

setup_firewall() {
  log_step "Configurando firewall (UFW)..."

  # Libera SSH antes de ativar o firewall para evitar lockout em máquinas
  # acessadas remotamente. Se o serviço ssh não estiver em uso, é inofensivo.
  if ! sudo ufw allow ssh; then
    log_warn "Falha ao liberar SSH no UFW"
    FAILED_STEPS+=("ufw:allow-ssh")
  fi

  if sudo ufw status | grep -qw "active"; then
    log_info "UFW já estava ativo"
  elif sudo ufw --force enable; then
    log_info "UFW configurado e ativado!"
  else
    log_warn "Falha ao ativar UFW"
    FAILED_STEPS+=("ufw:enable")
  fi
}

setup_fish_shell() {
  log_step "Configurando shell padrão para o Fish"

  if ! grep -qx "/usr/bin/fish" /etc/shells; then
    echo "/usr/bin/fish" | sudo tee -a /etc/shells >/dev/null
  fi

  if sudo chsh -s /usr/bin/fish "$USER"; then
    log_info "Shell alterado com sucesso!"
  else
    log_warn "Falha ao alterar o shell padrão"
    FAILED_STEPS+=("chsh:fish")
  fi

  log_step "Instalando Fisher (plugin manager do Fish)..."

  # 'fisher' é uma função fish, então roda-se via fish -c, não diretamente em bash.
  # curl -sL ... | source só existe dentro de uma sessão fish.
  if fish -c 'functions -q fisher' 2>/dev/null; then
    log_info "Fisher já instalado"
  else
    if fish -c '
      curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
      fisher install jorgebucaran/fisher
    '; then
      log_info "Fisher instalado!"
    else
      log_warn "Falha ao instalar Fisher"
      FAILED_STEPS+=("fisher:install")
    fi
  fi
}

setup_tpm() {
  log_step "Configurando TPM (TMUX plugin manager)"

  if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then
    log_info "TPM já instalado"
    return 0
  fi

  if git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"; then
    log_info "TPM configurado!"
  else
    log_warn "Falha ao clonar TPM"
    FAILED_STEPS+=("tpm:clone")
  fi
}

setup_gsettings() {
  log_step "Configurando Gsettings"

  if ! command -v gsettings &>/dev/null; then
    log_warn "gsettings não encontrado, pulando"
    FAILED_STEPS+=("gsettings:missing-cmd")
    return 1
  fi

  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || FAILED_STEPS+=("gsettings:color-scheme")
  gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal footclient || FAILED_STEPS+=("gsettings:nautilus-terminal")
  gsettings set org.gnome.desktop.wm.preferences button-layout ':' || FAILED_STEPS+=("gsettings:button-layout")

  log_info "Gsettings configurado!"
}

setup_mime_associations() {
  log_step "Configurando associações MIME..."

  local browser_desktop="helium.desktop"
  local editor_desktop="org.gnome.TextEditor.desktop"
  local image_viewer_desktop="org.gnome.Loupe.desktop"

  local browser_mimes=(
    "text/html"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "x-scheme-handler/ftp"
    "application/xhtml+xml"
    "application/x-extension-htm"
    "application/x-extension-html"
    "application/x-extension-xhtml"
  )

  local image_mimes=(
    "image/png"
    "image/jpeg"
    "image/webp"
    "image/gif"
  )

  log_step "  Definindo Helium como browser padrão..."
  for mime in "${browser_mimes[@]}"; do
    if xdg-mime default "$browser_desktop" "$mime"; then
      log_info "  ✓ $mime -> helium"
    else
      log_warn "  ✗ $mime (falhou)"
      FAILED_STEPS+=("mime:$mime")
    fi
  done

  if xdg-settings set default-web-browser "$browser_desktop"; then
    log_info "  ✓ Browser padrão do sistema -> Helium"
  else
    log_warn "  ✗ Falha ao definir browser padrão via xdg-settings"
    FAILED_STEPS+=("mime:default-web-browser")
  fi

  log_step "  Definindo Nautilus como gerenciador de arquivos padrão..."
  xdg-mime default org.gnome.Nautilus.desktop inode/directory
  if xdg-mime query default inode/directory | grep -q nautilus; then
    log_info "  ✓ inode/directory -> nautilus"
  else
    log_warn "  ✗ inode/directory (falhou)"
    FAILED_STEPS+=("mime:inode/directory")
  fi

  log_step "  Definindo GNOME Text Editor como editor de texto padrão..."
  if xdg-mime default "$editor_desktop" "text/plain"; then
    log_info "  ✓ text/plain -> gnome-text-editor"
  else
    log_warn "  ✗ text/plain (falhou)"
    FAILED_STEPS+=("mime:text/plain")
  fi

  log_step "  Definindo Papers como visualizador de PDF padrão..."
  local pdf_mimes=(
    "application/pdf"
    "application/x-bzpdf"
    "application/x-gzpdf"
    "application/x-xzpdf"
    "application/x-ext-pdf"
    "application/postscript"
    "application/x-bzpostscript"
    "application/x-gzpostscript"
    "image/x-eps"
    "image/x-bzeps"
    "image/x-gzeps"
    "application/x-dvi"
    "application/x-bzdvi"
    "application/x-gzdvi"
    "image/vnd.djvu"
    "application/vnd.comicbook-rar"
    "application/vnd.comicbook+zip"
    "application/x-cbr"
    "application/x-cbz"
    "application/x-cb7"
    "application/x-cbt"
  )
  for mime in "${pdf_mimes[@]}"; do
    if xdg-mime default org.gnome.Papers.desktop "$mime"; then
      log_info "  ✓ $mime -> papers"
    else
      log_warn "  ✗ $mime (falhou)"
      FAILED_STEPS+=("mime:$mime")
    fi
  done

  log_step "  Definindo Loupe como visualizador de imagens padrão..."
  for mime in "${image_mimes[@]}"; do
    if xdg-mime default "$image_viewer_desktop" "$mime"; then
      log_info "  ✓ $mime -> loupe"
    else
      log_warn "  ✗ $mime (falhou)"
      FAILED_STEPS+=("mime:$mime")
    fi
  done
}

setup_git() {
  log_step "Verificando configuração do Git..."

  read -r -p "Digite o seu nome do git: " gitUsername
  read -r -p "Digite o seu email do git: " gitEmail

  git config --global user.name "$gitUsername"
  git config --global user.email "$gitEmail"

  git config --global core.autocrlf input
  git config --global init.defaultBranch main
  git config --global pull.rebase false

  git config --global core.pager delta
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate true
  git config --global delta.light false
  git config --global merge.conflictstyle zdiff3
}

setup_gaming() {
  read -r -p "Deseja configurar o setup de gaming? [s/N] " response
  case "$response" in
  [sS][iI][mM] | [sS])
    log_step "Configurando setup de gaming..."

    if ! sudo pacman -S --noconfirm --needed gamemode lact; then
      log_warn "Falha ao instalar gamemode/lact"
      FAILED_STEPS+=("gaming:gamemode-lact")
    fi

    if ! yay -S --noconfirm --needed steam-devices-git; then
      log_warn "Falha ao instalar steam-devices-git"
      FAILED_STEPS+=("gaming:steam-devices")
    fi

    flatpak install -y flathub com.valvesoftware.Steam || FAILED_STEPS+=("gaming:steam-flatpak")
    flatpak install -y flathub io.github.benjamimgois.goverlay || FAILED_STEPS+=("gaming:goverlay")
    flatpak install -y flathub net.lutris.Lutris || FAILED_STEPS+=("gaming:lutris")
    flatpak install -y flathub net.davidotek.pupgui2 || FAILED_STEPS+=("gaming:pupgui2")

    log_info "Setup de gaming instalado!"
    ;;
  *)
    log_info "Setup de gaming pulado."
    ;;
  esac
}

cleanup_yay() {
  log_step "Limpando dependências de build do yay..."
  if yay -Ycc --noconfirm 2>/dev/null; then
    log_info "Dependências de build removidas!"
  else
    log_warn "Falha ao limpar pacotes de build (pode já estar limpo)"
  fi
}

setup_greeter() {
  log_step "Configurando greetd greeter..."

  local greeter_dir="$SCRIPT_DIR/greeter"
  [[ -d "$greeter_dir" ]] || greeter_dir="$HOME/post-install-setup/hyprland/greeter"
  local dest_dir="/etc/greetd"

  if [[ ! -d "$greeter_dir" ]]; then
    log_warn "  ✗ Diretório greeter/ não encontrado"
    FAILED_STEPS+=("greeter:missing-dir")
    return 1
  fi

  if sudo systemctl enable greetd.service; then
    log_info "  ✓ greetd.service habilitado"
  else
    log_warn "  ✗ Falha ao habilitar greetd.service"
    FAILED_STEPS+=("greeter:enable-service")
  fi

  sudo mkdir -p "$dest_dir"

  for file in config.toml hyprland.lua regreet.toml; do
    if [[ -f "$greeter_dir/$file" ]]; then
      if [[ ! -f "$dest_dir/$file" ]] || ! diff -q "$greeter_dir/$file" "$dest_dir/$file" &>/dev/null; then
        if sudo cp "$greeter_dir/$file" "$dest_dir/$file"; then
          log_info "  ✓ $file -> $dest_dir/$file"
        else
          log_warn "  ✗ Falha ao copiar $file"
          FAILED_STEPS+=("greeter:copy-$file")
        fi
      else
        log_info "  ✓ $file (já atualizado)"
      fi
    else
      log_warn "  ✗ $file não encontrado em greeter/"
      FAILED_STEPS+=("greeter:$file")
    fi
  done
  log_info "Greeter configurado!"
}

# =============================
# Resumo final
# =============================

print_summary() {
  echo ""
  log_info "========================================="

  if [[ ${#FAILED_PACKAGES[@]} -gt 0 || ${#FAILED_STEPS[@]} -gt 0 ]]; then
    log_warn "Instalação concluída com avisos."
  else
    log_info "✨ Instalação concluída com sucesso! ✨"
  fi

  log_info "========================================="

  if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    echo ""
    log_warn "Pacotes que falharam (${#FAILED_PACKAGES[@]}):"
    for pkg in "${FAILED_PACKAGES[@]}"; do
      echo "  • $pkg"
    done
  fi

  if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
    echo ""
    log_warn "Etapas que falharam (${#FAILED_STEPS[@]}):"
    for step in "${FAILED_STEPS[@]}"; do
      echo "  • $step"
    done
  fi

  echo ""
  log_warn "Próximos passos:"
  echo "  1. Faça LOGOUT e LOGIN para aplicar o grupo docker"
  echo "  2. Reinicie o terminal para ativar Fish e Mise"
  echo "  3. Execute 'mise doctor' para verificar runtimes"
  echo "  4. No tmux, pressione <prefix> + I para instalar plugins via TPM"
  echo ""
  log_info "Log salvo em: $LOGFILE"
  echo ""
}

# =============================
# Execução principal
# =============================

main() {
  mkdir -p "$(dirname "$LOGFILE")"
  echo "Post-Install Arch Linux v$VERSION - $(date)" >"$LOGFILE"

  echo ""
  log_info "========================================="
  log_info "Post-Install Arch Linux v$VERSION"
  log_info "Usuário: $USER | Data: $(date '+%d/%m/%Y %H:%M')"
  log_info "Diretório do script: $SCRIPT_DIR"
  log_info "========================================="
  echo ""

  check_arch_linux
  check_not_root
  check_pre_dependencies

  install_pacman_packages
  install_yay
  setup_chaotic_aur
  install_aur_packages
  setup_dotfiles
  setup_docker
  setup_firewall
  setup_fish_shell
  setup_tpm
  setup_gsettings
  setup_mime_associations
  setup_git
  setup_greeter
  setup_gaming
  cleanup_yay

  print_summary
}

main "$@"