#!/bin/bash
# ==============================================================================
# lib/system.sh - Módulos de Configuração do Sistema e Ferramentas
# ==============================================================================

# Cria um backup com timestamp antes de alterar arquivos de sistema
backup_file() {
  local file="$1"
  [[ -e "$file" ]] || return 0

  local backup
  backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"
  if sudo cp -a "$file" "$backup"; then
    log_info "  ✓ Backup: $backup"
  else
    log_warn "  ✗ Falha ao criar backup de $file"
    FAILED_STEPS+=("backup:$file")
  fi
}

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

setup_network() {
  log_step "Configurando e otimizando rede (iwd)..."

  # Desativar e mascarar completamente serviços de rede conflitantes
  for service in \
    systemd-networkd \
    systemd-networkd.socket \
    systemd-networkd-wait-online \
    NetworkManager \
    NetworkManager.service \
    NetworkManager-wait-online; do
    sudo systemctl stop "$service" 2>/dev/null || true
    sudo systemctl disable "$service" 2>/dev/null || true
    sudo systemctl mask "$service" 2>/dev/null || true
  done

  enable_iwd
  disable_wifi_power_save
}

enable_iwd() {
  log_step "Habilitando iwd..."

  sudo mkdir -p /etc/iwd
  if [[ ! -f /etc/iwd/main.conf ]]; then
    cat <<'EOF' | sudo tee /etc/iwd/main.conf >/dev/null
[General]
EnableNetworkConfiguration=true
EOF
    log_info "  ✓ /etc/iwd/main.conf criado"
  elif ! sudo grep -q '^EnableNetworkConfiguration=true' /etc/iwd/main.conf; then
    cat <<'EOF' | sudo tee -a /etc/iwd/main.conf >/dev/null

[General]
EnableNetworkConfiguration=true
EOF
    log_info "  ✓ EnableNetworkConfiguration=true adicionado ao iwd"
  fi

  if sudo systemctl enable --now iwd.service 2>/dev/null; then
    log_info "  ✓ iwd.service habilitado e iniciado"
  else
    log_warn "  ✗ Falha ao habilitar iwd.service"
    FAILED_STEPS+=("network:enable-iwd")
  fi
}

disable_wifi_power_save() {
  log_step "Desativando economia de energia do Wi‑Fi..."

  sudo mkdir -p /etc/modprobe.d /etc/udev/rules.d

  backup_file /etc/modprobe.d/iwlwifi.conf
  cat <<'EOF' | sudo tee /etc/modprobe.d/iwlwifi.conf >/dev/null
options iwlwifi power_save=0
options iwlmvm power_scheme=1
EOF
  log_info "  ✓ Tweaks aplicados para drivers Intel (iwlwifi/iwlmvm)"

  backup_file /etc/udev/rules.d/81-wifi-powersave.rules
  cat <<'EOF' | sudo tee /etc/udev/rules.d/81-wifi-powersave.rules >/dev/null
ACTION=="add", SUBSYSTEM=="net", KERNEL=="wl*", RUN+="/usr/bin/iw dev %k set power_save off"
EOF
  log_info "  ✓ Regra udev criada para desligar power save do Wi‑Fi"

  if sudo udevadm control --reload 2>/dev/null; then
    log_info "  ✓ Regras udev recarregadas"
  else
    log_warn "  ✗ Falha ao recarregar regras udev"
    FAILED_STEPS+=("network:udev-reload")
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
  gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 10' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface font-name 'Inter 10' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface document-font-name 'Inter 10' 2>/dev/null || true
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

# Codifica um caminho como URI (acentos e espaços) para o arquivo de bookmarks do GTK
_uri_encode() {
  local LC_ALL=C
  local s="$1" out="" c i

  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9/._~-]) out+="$c" ;;
      *)
        printf -v c '%%%02X' "'$c"
        out+="$c"
        ;;
    esac
  done

  printf '%s' "$out"
}

setup_user_dirs() {
  log_step "Configurando diretórios XDG e bookmarks do Nautilus..."

  # Nomes fixos em pt-BR, independentes do locale da instalação
  local dir_names=(
    "DOWNLOAD"
    "DOCUMENTS"
    "PICTURES"
    "MUSIC"
    "VIDEOS"
    "PROJECTS"
  )
  local dir_labels=(
    "Downloads"
    "Documentos"
    "Imagens"
    "Músicas"
    "Vídeos"
    "Projetos"
  )
  local dir_paths=(
    "$HOME/Downloads"
    "$HOME/Documentos"
    "$HOME/Imagens"
    "$HOME/Músicas"
    "$HOME/Vídeos"
    "$HOME/Projetos"
  )

  local i
  for i in "${!dir_paths[@]}"; do
    mkdir -p "${dir_paths[$i]}"
  done

  if command -v xdg-user-dirs-update &>/dev/null; then
    # Preenche os demais diretórios XDG conforme o locale (Desktop, Modelos, etc.)
    xdg-user-dirs-update 2>/dev/null || true
    for i in "${!dir_names[@]}"; do
      xdg-user-dirs-update --set "${dir_names[$i]}" "${dir_paths[$i]}" 2>/dev/null || true
    done
    log_info "  ✓ user-dirs.dirs atualizado (${dir_labels[*]})"
  else
    log_warn "  ✗ xdg-user-dirs-update não encontrado"
    FAILED_STEPS+=("user-dirs:xdg-user-dirs-update")
  fi

  # Nautilus (GTK3 e GTK4) lê os bookmarks de ~/.config/gtk-3.0/bookmarks
  local bookmarks_file="$HOME/.config/gtk-3.0/bookmarks"
  local uri
  mkdir -p "$(dirname "$bookmarks_file")"
  touch "$bookmarks_file"

  for i in "${!dir_paths[@]}"; do
    uri="file://$(_uri_encode "${dir_paths[$i]}")"
    if ! awk -v u="$uri" '$1 == u { found = 1 } END { exit !found }' "$bookmarks_file"; then
      printf '%s %s\n' "$uri" "${dir_labels[$i]}" >>"$bookmarks_file"
    fi
  done

  log_info "  ✓ Bookmarks do Nautilus atualizados"
}

setup_bluetooth() {
  log_step "Habilitando Bluetooth (sem autostart do applet)..."

  if ! command -v bluetoothctl &>/dev/null; then
    log_warn "  ✗ bluez não encontrado; Bluetooth não será habilitado"
    FAILED_STEPS+=("bluetooth:bluez-missing")
    return 0
  fi

  if sudo systemctl enable --now bluetooth.service 2>/dev/null; then
    log_info "  ✓ bluetooth.service habilitado e iniciado"
  else
    log_warn "  ✗ Falha ao habilitar bluetooth.service"
    FAILED_STEPS+=("bluetooth:enable")
  fi
}

setup_audio() {
  log_step "Habilitando PipeWire/WirePlumber..."

  if ! command -v systemctl &>/dev/null; then
    log_warn "  ✗ systemctl não encontrado; áudio não será habilitado"
    FAILED_STEPS+=("audio:missing-systemctl")
    return 0
  fi

  local units=(pipewire.socket pipewire-pulse.socket wireplumber.service)
  if XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" systemctl --user enable --now "${units[@]}" 2>/dev/null; then
    log_info "  ✓ PipeWire/WirePlumber habilitados"
  else
    log_warn "  ✗ Falha ao habilitar PipeWire/WirePlumber (será ativado no próximo login)"
    FAILED_STEPS+=("audio:user-services")
  fi
}

setup_maintenance() {
  log_step "Aplicando higiene e manutenção do sistema..."

  # Limita o cache do pacman a 2 versões por pacote e agenda a limpeza semanal
  if command -v paccache &>/dev/null; then
    if sudo paccache -rk2 >/dev/null 2>&1; then
      log_info "  ✓ Cache do pacman limpo (2 versões por pacote)"
    else
      log_warn "  ✗ Falha ao limpar o cache do pacman"
      FAILED_STEPS+=("maintenance:paccache")
    fi

    if sudo systemctl enable --now paccache.timer 2>/dev/null; then
      log_info "  ✓ paccache.timer habilitado"
    else
      log_warn "  ✗ Falha ao habilitar paccache.timer"
      FAILED_STEPS+=("maintenance:paccache-timer")
    fi
  else
    log_warn "  paccache não encontrado (pacman-contrib ausente)"
  fi

  # Atualiza os mirrors periodicamente
  if command -v reflector &>/dev/null; then
    if sudo systemctl enable --now reflector.timer 2>/dev/null; then
      log_info "  ✓ reflector.timer habilitado"
    else
      log_warn "  ✗ Falha ao habilitar reflector.timer"
      FAILED_STEPS+=("maintenance:reflector-timer")
    fi
  fi

  # Limita o journal a 500 MB
  local journald_conf="/etc/systemd/journald.conf.d/99-size.conf"
  if [[ ! -f "$journald_conf" ]]; then
    sudo mkdir -p "$(dirname "$journald_conf")"
    if printf '[Journal]\nSystemMaxUse=500M\n' | sudo tee "$journald_conf" >/dev/null; then
      sudo systemctl restart systemd-journald 2>/dev/null || true
      sudo journalctl --vacuum-size=500M >/dev/null 2>&1 || true
      log_info "  ✓ journald limitado a 500 MB"
    else
      log_warn "  ✗ Falha ao configurar o journald"
      FAILED_STEPS+=("maintenance:journald")
    fi
  else
    log_info "  ✓ journald já configurado"
  fi
}

default_wayland_post_install() {
  setup_gsettings "footclient"
  setup_mime_associations "helium.desktop" "org.gnome.TextEditor.desktop" "org.gnome.Loupe.desktop"

  if [[ -f "$HOME/.local/scripts/font-set.py" ]] && command -v python3 &>/dev/null; then
    log_step "Aplicando JetBrainsMono Nerd Font como fonte padrão..."
    python3 "$HOME/.local/scripts/font-set.py" "JetBrainsMono Nerd Font" 2>/dev/null || true
    log_info "  ✓ JetBrainsMono Nerd Font aplicada em todos os apps e terminais"
  fi
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
        backup_file "$dest_dir/$filename"
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

  # Ajustar usuário da sessão inicial automaticamente para o usuário atual
  if [[ -f "$dest_dir/config.toml" ]]; then
    backup_file "$dest_dir/config.toml"
    sudo sed -i -e "/^\[initial_session\]/,/^user =/ s/user = .*/user = \"$USER\"/" "$dest_dir/config.toml"
  fi

  # Garantir diretórios e permissões para log e cache do regreet
  sudo mkdir -p /var/log/regreet /var/lib/regreet
  if id greeter &>/dev/null; then
    sudo chown -R greeter:greeter /var/log/regreet /var/lib/regreet
  fi

  # Configurar pam_gnome_keyring no greetd se ainda nao estiver presente
  if [[ -f "/etc/pam.d/greetd" ]] && ! grep -q "pam_gnome_keyring" "/etc/pam.d/greetd"; then
    log_info "  Configurando suporte a gnome-keyring no PAM do greetd..."
    backup_file /etc/pam.d/greetd
    sudo sed -i '/auth.*system-local-login/a auth       optional     pam_gnome_keyring.so' /etc/pam.d/greetd
    sudo sed -i '/session.*system-local-login/a session    optional     pam_gnome_keyring.so auto_start' /etc/pam.d/greetd
    sudo sed -i '/password.*system-local-login/a password   optional     pam_gnome_keyring.so' /etc/pam.d/greetd 2>/dev/null || true
  fi

  log_info "Greeter configurado com sucesso!"
}

setup_gaming() {
  log_step "Configurando suporte a multilib e drivers de gaming..."
  setup_multilib

  log_step "Instalando ferramentas e pacotes de gaming via pacman (Steam, Vulkan Radeon, GameMode, LACT, GOverlay, Lutris)..."
  local gaming_pacman_pkgs=(
    "vulkan-radeon"
    "lib32-vulkan-radeon"
    "gamemode"
    "steam"
    "lib32-pipewire"
    "lact"
    "goverlay"
    "lutris"
  )

  if ! sudo pacman -S --noconfirm --needed "${gaming_pacman_pkgs[@]}"; then
    log_warn "Falha na instalação em lote de gaming pelo pacman. Tentando pacote por pacote..."
    for pkg in "${gaming_pacman_pkgs[@]}"; do
      if ! sudo pacman -S --noconfirm --needed "$pkg" 2>/dev/null; then
        log_warn "Falha ao instalar: $pkg"
        FAILED_STEPS+=("gaming:$pkg")
      fi
    done
  fi

  log_step "Instalando ProtonUp-Qt via AUR/Chaotic-AUR..."
  install_aur_packages "protonup-qt"

  # O LACT é composto pelo app gráfico e pelo daemon (lactd)
  if command -v lact &>/dev/null; then
    if sudo systemctl enable --now lactd.service 2>/dev/null; then
      log_info "  ✓ lactd.service habilitado e iniciado"
    else
      log_warn "  ✗ Falha ao habilitar lactd.service"
      FAILED_STEPS+=("gaming:lactd")
    fi
  fi

  log_info "Setup de gaming concluído!"
}
