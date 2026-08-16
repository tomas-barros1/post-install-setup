#!/bin/bash
# ==============================================================================
# lib/system.sh - Módulos de Configuração do Sistema e Ferramentas
# ==============================================================================

setup_dotfiles() {
  local dotfiles_dirs=("$@")
  local dotfiles_repo="https://github.com/tomas-barros1/dotfiles"
  local dotfiles_dir="$HOME/dotfiles"

  if [[ ! -d "$dotfiles_dir" ]]; then
    log_step "Clonando repositório de dotfiles..."
    if ! git clone "$dotfiles_repo" "$dotfiles_dir"; then
      log_warn "Falha ao clonar dotfiles de $dotfiles_repo"
      FAILED_STEPS+=("dotfiles:clone")
      return 1
    fi
  else
    log_step "Atualizando repositório de dotfiles existente..."
    if ! git -C "$dotfiles_dir" pull; then
      log_warn "Falha ao atualizar dotfiles (git pull)"
      FAILED_STEPS+=("dotfiles:pull")
    fi
  fi

  # Cria ~/.local como diretório real
  mkdir -p "$HOME/.local"

  log_step "Aplicando stow nos dotfiles selecionados..."
  cd "$dotfiles_dir" || return 1

  for dir in "${dotfiles_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      if stow -R "$dir" 2>/dev/null; then
        log_info "  ✓ $dir"
      else
        log_warn "  ✗ $dir (conflito ou erro de stow)"
        FAILED_STEPS+=("stow:$dir")
      fi
    else
      log_warn "  Diretório '$dir' não encontrado em dotfiles"
    fi
  done

  # Processar scripts/ com --adopt se existir
  if [[ -d "scripts" ]]; then
    if ! stow --adopt scripts/ 2>/dev/null; then
      log_warn "  ✗ scripts (falha no stow --adopt)"
      FAILED_STEPS+=("stow:scripts")
    else
      log_info "  ✓ scripts (adotado com sucesso)"
    fi
  fi

  cd - >/dev/null || true
}

setup_docker() {
  log_step "Configurando serviço do Docker..."

  if ! sudo systemctl enable docker.service 2>/dev/null; then
    log_warn "Falha ao habilitar docker.service"
    FAILED_STEPS+=("docker:enable")
  fi

  if ! groups "$USER" | grep -q docker; then
    if sudo usermod -aG docker "$USER"; then
      log_info "Usuário adicionado ao grupo 'docker'."
      log_warn "ATENÇÃO: Faça LOGOUT e LOGIN para aplicar as permissões do grupo Docker!"
    else
      log_warn "Falha ao adicionar usuário ao grupo docker"
      FAILED_STEPS+=("docker:usermod")
    fi
  else
    log_info "Usuário já pertence ao grupo docker"
  fi
}

setup_firewall() {
  log_step "Configurando firewall (UFW)..."

  if ! sudo ufw allow ssh; then
    log_warn "Falha ao liberar porta SSH no UFW"
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
  log_step "Configurando Fish como shell padrão..."

  if ! grep -qx "/usr/bin/fish" /etc/shells 2>/dev/null; then
    echo "/usr/bin/fish" | sudo tee -a /etc/shells >/dev/null
  fi

  if sudo chsh -s /usr/bin/fish "$USER"; then
    log_info "Shell padrão alterado para Fish com sucesso!"
  else
    log_warn "Falha ao alterar o shell padrão para Fish"
    FAILED_STEPS+=("chsh:fish")
  fi

  log_step "Instalando Fisher (gerenciador de plugins do Fish)..."

  if fish -c 'functions -q fisher' 2>/dev/null; then
    log_info "Fisher já está instalado"
  else
    if fish -c '
      curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
      fisher install jorgebucaran/fisher
    ' 2>/dev/null; then
      log_info "Fisher instalado com sucesso!"
    else
      log_warn "Falha ao instalar Fisher"
      FAILED_STEPS+=("fisher:install")
    fi
  fi
}

setup_tpm() {
  log_step "Configurando TPM (Tmux Plugin Manager)..."

  if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then
    log_info "TPM já instalado"
    return 0
  fi

  if git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" 2>/dev/null; then
    log_info "TPM configurado com sucesso!"
  else
    log_warn "Falha ao clonar TPM"
    FAILED_STEPS+=("tpm:clone")
  fi
}

setup_git() {
  log_step "Configurando perfil do Git..."

  local current_user
  local current_email
  current_user="$(git config --global user.name || true)"
  current_email="$(git config --global user.email || true)"

  local git_name=""
  local git_email=""

  if command -v gum &>/dev/null; then
    git_name=$(gum input --placeholder "Digite o seu nome para o Git" --value "$current_user" --header "Git User Name:")
    git_email=$(gum input --placeholder "Digite o seu email para o Git" --value "$current_email" --header "Git User Email:")
  else
    read -r -p "Digite o seu nome para o Git [atual: $current_user]: " input_name
    git_name="${input_name:-$current_user}"
    read -r -p "Digite o seu email para o Git [atual: $current_email]: " input_email
    git_email="${input_email:-$current_email}"
  fi

  if [[ -n "$git_name" ]]; then
    git config --global user.name "$git_name"
  fi
  if [[ -n "$git_email" ]]; then
    git config --global user.email "$git_email"
  fi

  # Configurações globais recomendadas
  git config --global core.autocrlf input
  git config --global init.defaultBranch main
  git config --global pull.rebase false

  # Delta pager
  if command -v delta &>/dev/null; then
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
    git config --global delta.navigate true
    git config --global delta.light false
    git config --global merge.conflictstyle zdiff3
  fi

  log_info "Configurações do Git aplicadas!"
}

setup_gsettings() {
  local term_app="${1:-footclient}"
  log_step "Configurando Gsettings padrão..."

  if ! command -v gsettings &>/dev/null; then
    log_warn "gsettings não encontrado no sistema, pulando etapa."
    return 0
  fi

  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
  gsettings set org.gnome.desktop.wm.preferences button-layout ':' 2>/dev/null || true
  gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal "$term_app" 2>/dev/null || true

  log_info "Gsettings configurado!"
}

setup_mime_associations() {
  log_step "Configurando associações de arquivos (MIME)..."

  local browser_desktop="${1:-helium.desktop}"
  local editor_desktop="${2:-org.gnome.TextEditor.desktop}"
  local image_viewer_desktop="${3:-org.gnome.Loupe.desktop}"

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

  for mime in "${browser_mimes[@]}"; do
    xdg-mime default "$browser_desktop" "$mime" 2>/dev/null || true
  done
  xdg-settings set default-web-browser "$browser_desktop" 2>/dev/null || true

  xdg-mime default org.gnome.Nautilus.desktop inode/directory 2>/dev/null || true
  xdg-mime default "$editor_desktop" "text/plain" 2>/dev/null || true

  for mime in "${pdf_mimes[@]}"; do
    xdg-mime default org.gnome.Papers.desktop "$mime" 2>/dev/null || true
  done

  for mime in "${image_mimes[@]}"; do
    xdg-mime default "$image_viewer_desktop" "$mime" 2>/dev/null || true
  done

  log_info "Associações MIME aplicadas!"
}

setup_greeter() {
  local greeter_type="${1:-hyprland}" # hyprland ou sway
  local config_root="$REPO_ROOT/config/greeter/$greeter_type"
  local dest_dir="/etc/greetd"

  log_step "Configurando greetd greeter ($greeter_type)..."

  if [[ ! -d "$config_root" ]]; then
    log_warn "Diretório de configurações do greeter não encontrado: $config_root"
    FAILED_STEPS+=("greeter:missing-config-dir")
    return 1
  fi

  if sudo systemctl enable greetd.service 2>/dev/null; then
    log_info "  ✓ greetd.service habilitado"
  else
    log_warn "  ✗ Falha ao habilitar greetd.service"
    FAILED_STEPS+=("greeter:enable-service")
  fi

  sudo mkdir -p "$dest_dir"

  for file in "$config_root"/*; do
    if [[ -f "$file" ]]; then
      local filename
      filename=$(basename "$file")
      if [[ ! -f "$dest_dir/$filename" ]] || ! diff -q "$file" "$dest_dir/$filename" &>/dev/null; then
        if sudo cp "$file" "$dest_dir/$filename"; then
          log_info "  ✓ $filename -> $dest_dir/$filename"
        else
          log_warn "  ✗ Falha ao copiar $filename"
          FAILED_STEPS+=("greeter:copy-$filename")
        fi
      else
        log_info "  ✓ $filename (já atualizado)"
      fi
    fi
  done

  log_info "Greeter configurado com sucesso!"
}

setup_gaming() {
  local should_install=false

  if command -v gum &>/dev/null; then
    if gum confirm "Deseja configurar o setup de gaming (Steam, Lutris, GameMode, LACT, GOverlay)?"; then
      should_install=true
    fi
  else
    read -r -p "Deseja configurar o setup de gaming? [s/N] " response
    case "$response" in
      [sS][iI][mM] | [sS]) should_install=true ;;
      *) should_install=false ;;
    esac
  fi

  if [[ "$should_install" == "true" ]]; then
    log_step "Instalando ferramentas e pacotes de gaming..."

    if ! sudo pacman -S --noconfirm --needed gamemode lact 2>/dev/null; then
      log_warn "Falha ao instalar gamemode / lact via pacman"
      FAILED_STEPS+=("gaming:gamemode-lact")
    fi

    if command -v yay &>/dev/null; then
      yay -S --noconfirm --needed steam-devices-git 2>/dev/null || FAILED_STEPS+=("gaming:steam-devices")
    fi

    if command -v flatpak &>/dev/null; then
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
      flatpak install -y flathub com.valvesoftware.Steam 2>/dev/null || FAILED_STEPS+=("gaming:steam-flatpak")
      flatpak install -y flathub io.github.benjamimgois.goverlay 2>/dev/null || FAILED_STEPS+=("gaming:goverlay")
      flatpak install -y flathub net.lutris.Lutris 2>/dev/null || FAILED_STEPS+=("gaming:lutris")
      flatpak install -y flathub net.davidotek.pupgui2 2>/dev/null || FAILED_STEPS+=("gaming:pupgui2")
    fi

    log_info "Setup de gaming concluído!"
  else
    log_info "Setup de gaming pulado."
  fi
}
