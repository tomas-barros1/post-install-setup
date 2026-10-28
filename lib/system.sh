#!/bin/bash
# ==============================================================================
# lib/system.sh - Módulos de Configuração do Sistema e Ferramentas
# ==============================================================================

setup_locale() {
  local locale_name="${POST_INSTALL_LOCALE:-pt_BR.UTF-8}"
  local timezone="${POST_INSTALL_TIMEZONE:-America/Sao_Paulo}"
  local locale_re="${locale_name//./\\.}"

  log_step "Configurando locale (${locale_name}) e timezone (${timezone})..."

  # Garantir o locale no locale.gen (descomenta ou adiciona)
  if grep -q "^#${locale_re} " /etc/locale.gen 2>/dev/null; then
    backup_file /etc/locale.gen
    sudo sed -i "s/^#\(${locale_re} \)/\1/" /etc/locale.gen
    log_info "  ✓ ${locale_name} descomentado em /etc/locale.gen"
  elif ! grep -q "^${locale_re} " /etc/locale.gen 2>/dev/null; then
    echo "${locale_name} UTF-8" | sudo tee -a /etc/locale.gen >/dev/null
    log_info "  ✓ ${locale_name} adicionado em /etc/locale.gen"
  fi

  if sudo locale-gen >/dev/null 2>&1; then
    log_info "  ✓ locale-gen executado"
  else
    log_warn "  ✗ Falha ao gerar locales"
    FAILED_STEPS+=("locale:locale-gen")
  fi

  if sudo localectl set-locale "LANG=${locale_name}" 2>/dev/null; then
    log_info "  ✓ LANG=${locale_name}"
  else
    log_warn "  ✗ Falha ao definir locale (localectl)"
    FAILED_STEPS+=("locale:set-locale")
  fi

  # No WSL o timezone/NTP são controlados pelo Windows
  if is_wsl; then
    log_info "  ✓ WSL detectado: timezone e NTP ficam a cargo do Windows"
    return 0
  fi

  if sudo timedatectl set-timezone "$timezone" 2>/dev/null; then
    log_info "  ✓ Timezone: ${timezone}"
  else
    log_warn "  ✗ Falha ao definir timezone"
    FAILED_STEPS+=("locale:timezone")
  fi

  if sudo timedatectl set-ntp true 2>/dev/null; then
    log_info "  ✓ NTP habilitado"
  else
    log_warn "  ✗ Falha ao habilitar NTP"
    FAILED_STEPS+=("locale:ntp")
  fi
}

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

# Extrai, da saída de erro do stow, os alvos (relativos ao $HOME) que conflitam.
_stow_conflicts() {
  printf '%s\n' "$1" | sed -nE \
    -e 's/.*existing target is (neither a link nor a directory|not owned by stow): (.*)$/\2/p' \
    -e 's/.*cannot stow .* over existing target (.*) since .*/\1/p' | sort -u
}

setup_dotfiles() {
  local dotfiles_dirs=("$@")
  local dotfiles_repo="${DOTFILES_REPO:-https://github.com/tomas-barros1/dotfiles}"
  local dotfiles_dir="${DOTFILES_DIR:-$HOME/dotfiles}"

  if [[ ! -d "$dotfiles_dir" ]]; then
    log_step "Clonando repositório de dotfiles ($dotfiles_repo)..."
    if ! git clone "$dotfiles_repo" "$dotfiles_dir"; then
      log_warn "Falha ao clonar dotfiles de $dotfiles_repo"
      FAILED_STEPS+=("dotfiles:clone")
      return 1
    fi
  else
    log_step "Atualizando repositório de dotfiles existente..."
    if ! git -C "$dotfiles_dir" pull --ff-only; then
      log_warn "Falha ao atualizar dotfiles (git pull --ff-only); usando a versão local"
      FAILED_STEPS+=("dotfiles:pull")
    fi
  fi

  # Cria ~/.local como diretório real (evita que o stow faça symlink da pasta inteira)
  mkdir -p "$HOME/.local"

  log_step "Aplicando stow nos dotfiles selecionados..."

  local dir out conflicts target stamp
  stamp="$(date +%Y%m%d-%H%M%S)"

  for dir in "${dotfiles_dirs[@]}"; do
    if [[ ! -d "$dotfiles_dir/$dir" ]]; then
      log_warn "  Diretório '$dir' não encontrado em dotfiles"
      continue
    fi

    if out=$(stow -d "$dotfiles_dir" -t "$HOME" -R "$dir" 2>&1); then
      log_info "  ✓ $dir"
      continue
    fi

    # Conflito com arquivos existentes: move para .bak.<data> (NUNCA usa --adopt,
    # que sobrescreveria o conteúdo do repositório com os arquivos locais).
    conflicts="$(_stow_conflicts "$out")"
    if [[ -z "$conflicts" ]]; then
      log_warn "  ✗ $dir: $out"
      FAILED_STEPS+=("stow:$dir")
      continue
    fi

    while IFS= read -r target; do
      if [[ -n "$target" ]] && { [[ -e "$HOME/$target" ]] || [[ -L "$HOME/$target" ]]; }; then
        mv "$HOME/$target" "$HOME/$target.bak.$stamp"
        log_info "    backup: ~/$target -> ~/$target.bak.$stamp"
      fi
    done <<<"$conflicts"

    if out=$(stow -d "$dotfiles_dir" -t "$HOME" -R "$dir" 2>&1); then
      log_info "  ✓ $dir (conflitos salvos como .bak.$stamp)"
    else
      log_warn "  ✗ $dir: $out"
      FAILED_STEPS+=("stow:$dir")
    fi
  done
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

setup_fish_shell() {
  log_step "Configurando Fish como shell padrão..."

  if ! grep -qx "/usr/bin/fish" /etc/shells 2>/dev/null; then
    echo "/usr/bin/fish" | sudo tee -a /etc/shells >/dev/null
  fi

  if sudo usermod -s /usr/bin/fish "$USER" 2>/dev/null || sudo chsh -s /usr/bin/fish "$USER"; then
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

  if [[ -n "${GIT_USER_NAME:-}" && -n "${GIT_USER_EMAIL:-}" ]]; then
    git_name="$GIT_USER_NAME"
    git_email="$GIT_USER_EMAIL"
  elif command -v gum &>/dev/null; then
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
# IMPORTANTE: o 'local LC_ALL=C' força o bash a iterar byte a byte em strings UTF-8
# (como "Músicas"), o que é exatamente o comportamento necessário para percent-encoding
# correto. Não remova essa linha.
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

install_ai_agents_refresh_hook() {
  local refresh_template="$REPO_ROOT/lib/ai-agents-refresh.sh"
  local hook_template="$REPO_ROOT/lib/ai-agents-refresh.hook"
  local refresh_tmp

  if [[ ! -f "$refresh_template" || ! -f "$hook_template" ]]; then
    log_warn "  ✗ Templates do refresh de agentes não encontrados"
    FAILED_STEPS+=("ai-agents:templates")
    return 1
  fi

  refresh_tmp="$(mktemp)"
  sed "s|@TARGET_USER@|${USER:-$(id -un)}|g" "$refresh_template" >"$refresh_tmp"

  if sudo install -m 0755 "$refresh_tmp" /usr/local/bin/ai-agents-refresh; then
    log_info "  ✓ /usr/local/bin/ai-agents-refresh"
  else
    log_warn "  ✗ Falha ao instalar ai-agents-refresh"
    FAILED_STEPS+=("ai-agents:refresh-script")
  fi
  rm -f "$refresh_tmp"

  if sudo install -d -m 0755 /etc/pacman.d/hooks; then
    backup_file /etc/pacman.d/hooks/ai-agents-refresh.hook
    if sudo install -m 0644 "$hook_template" /etc/pacman.d/hooks/ai-agents-refresh.hook; then
      log_info "  ✓ Hook do pacman: ai-agents-refresh.hook"
    else
      log_warn "  ✗ Falha ao instalar hook do pacman"
      FAILED_STEPS+=("ai-agents:pacman-hook")
    fi
  fi

  # Logrotate para /var/log/ai-agents-refresh.log
  local logrotate_conf="/etc/logrotate.d/ai-agents-refresh"
  if [[ ! -f "$logrotate_conf" ]]; then
    if printf '/var/log/ai-agents-refresh.log {\n    rotate 4\n    weekly\n    missingok\n    compress\n    notifempty\n}\n' |
      sudo tee "$logrotate_conf" >/dev/null; then
      log_info "  ✓ logrotate configurado para ai-agents-refresh.log"
    else
      log_warn "  ✗ Falha ao criar configuração de logrotate"
      FAILED_STEPS+=("ai-agents:logrotate")
    fi
  else
    log_info "  ✓ logrotate já configurado"
  fi
}

setup_ai_agents() {
  log_step "Configurando agentes de IA (ai-memory + RTK)..."

  if command -v ai-memory &>/dev/null; then
    local -a ai_memory_agents=()
    if command -v claude &>/dev/null || [[ -d "$HOME/.claude" ]]; then
      ai_memory_agents+=(--agent claude-code)
    fi
    command -v codex &>/dev/null && ai_memory_agents+=(--agent codex)
    if command -v cursor-agent &>/dev/null || [[ -d "$HOME/.cursor" ]]; then
      ai_memory_agents+=(--agent cursor)
    fi
    command -v copilot &>/dev/null && ai_memory_agents+=(--agent copilot-cli)
    command -v opencode &>/dev/null && ai_memory_agents+=(--agent open-code)
    command -v gemini &>/dev/null && ai_memory_agents+=(--agent gemini-cli)
    if command -v agy &>/dev/null || [[ -d "$HOME/.gemini/antigravity-cli" ]]; then
      ai_memory_agents+=(--agent antigravity-cli)
    fi

    if [[ ${#ai_memory_agents[@]} -gt 0 ]]; then
      if ai-memory setup --yes "${ai_memory_agents[@]}" >>"${LOGFILE:-/dev/null}" 2>&1; then
        log_info "  ✓ ai-memory integrado aos agentes instalados"
      else
        log_warn "  ✗ Falha ao configurar ai-memory (ver $LOGFILE)"
        FAILED_STEPS+=("ai-agents:ai-memory")
      fi
    else
      if ai-memory setup --yes >>"${LOGFILE:-/dev/null}" 2>&1; then
        log_info "  ✓ ai-memory configurado (autodetecção)"
      else
        log_warn "  ✗ Falha ao configurar ai-memory (ver $LOGFILE)"
        FAILED_STEPS+=("ai-agents:ai-memory")
      fi
    fi
  else
    log_warn "  ai-memory não encontrado; integração ignorada"
    FAILED_STEPS+=("ai-agents:ai-memory-missing")
  fi

  if command -v rtk &>/dev/null; then
    if command -v claude &>/dev/null || [[ -d "$HOME/.claude" ]]; then
      if rtk init -g --auto-patch --no-trust-filters >>"${LOGFILE:-/dev/null}" 2>&1; then
        log_info "  ✓ RTK: Claude Code"
      else
        log_warn "  ✗ RTK: Claude Code"
        FAILED_STEPS+=("ai-agents:rtk-claude")
      fi
    fi

    if command -v opencode &>/dev/null; then
      if rtk init -g --opencode --auto-patch --no-trust-filters >>"${LOGFILE:-/dev/null}" 2>&1; then
        log_info "  ✓ RTK: OpenCode"
      else
        log_warn "  ✗ RTK: OpenCode"
        FAILED_STEPS+=("ai-agents:rtk-opencode")
      fi
    fi

    if command -v codex &>/dev/null; then
      # O modo --codex não aceita --auto-patch; confirma o patch via stdin.
      if printf 'y\ny\ny\n' | rtk init -g --codex >>"${LOGFILE:-/dev/null}" 2>&1; then
        log_info "  ✓ RTK: Codex"
      else
        log_warn "  ✗ RTK: Codex"
        FAILED_STEPS+=("ai-agents:rtk-codex")
      fi
    fi

    if command -v copilot &>/dev/null; then
      if rtk init -g --copilot --auto-patch --no-trust-filters >>"${LOGFILE:-/dev/null}" 2>&1; then
        log_info "  ✓ RTK: Copilot CLI"
      else
        log_warn "  ✗ RTK: Copilot CLI"
        FAILED_STEPS+=("ai-agents:rtk-copilot")
      fi
    fi

    if command -v cursor-agent &>/dev/null || command -v cursor &>/dev/null; then
      if rtk init -g --agent cursor --auto-patch --no-trust-filters >>"${LOGFILE:-/dev/null}" 2>&1; then
        log_info "  ✓ RTK: Cursor"
      else
        log_warn "  ✗ RTK: Cursor"
        FAILED_STEPS+=("ai-agents:rtk-cursor")
      fi
    fi

    if command -v agy &>/dev/null || [[ -d "$HOME/.gemini/antigravity-cli" ]]; then
      if rtk init -g --agent antigravity --auto-patch --no-trust-filters >>"${LOGFILE:-/dev/null}" 2>&1; then
        log_info "  ✓ RTK: Antigravity CLI"
      else
        log_warn "  ✗ RTK: Antigravity CLI"
        FAILED_STEPS+=("ai-agents:rtk-antigravity")
      fi
    fi

    if command -v gemini &>/dev/null; then
      if rtk init -g --gemini --auto-patch --no-trust-filters >>"${LOGFILE:-/dev/null}" 2>&1; then
        log_info "  ✓ RTK: Gemini CLI"
      else
        log_warn "  ✗ RTK: Gemini CLI"
        FAILED_STEPS+=("ai-agents:rtk-gemini")
      fi
    fi
  else
    log_warn "  RTK não encontrado; integração ignorada"
    FAILED_STEPS+=("ai-agents:rtk-missing")
  fi

  if command -v ai-memory &>/dev/null || command -v rtk &>/dev/null; then
    install_ai_agents_refresh_hook
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
  local autologin="${GREETER_AUTOLOGIN:-true}"

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

  local file filename tmp
  tmp="$(mktemp)"
  for file in "$config_root"/*; do
    [[ -f "$file" ]] || continue
    filename=$(basename "$file")

    # Os arquivos do repo usam @USER@ como placeholder do usuário
    sed "s|@USER@|${USER}|g" "$file" >"$tmp"

    # Sem autologin: remove o bloco [initial_session] (é a última seção do config.toml)
    if [[ "$filename" == "config.toml" && "$autologin" != "true" ]]; then
      sed -i '/^\[initial_session\]/,$d' "$tmp"
    fi

    if [[ -f "$dest_dir/$filename" ]] && sudo cmp -s "$tmp" "$dest_dir/$filename"; then
      log_info "  ✓ $filename (já atualizado)"
      continue
    fi

    backup_file "$dest_dir/$filename"
    if sudo install -m 0644 "$tmp" "$dest_dir/$filename"; then
      log_info "  ✓ $filename -> $dest_dir/$filename"
    else
      log_warn "  ✗ Falha ao copiar $filename"
      FAILED_STEPS+=("greeter:copy-$filename")
    fi
  done
  rm -f "$tmp"

  # Garantir diretórios e permissões para log e cache do regreet
  sudo mkdir -p /var/log/regreet /var/lib/regreet
  if id greeter &>/dev/null; then
    sudo chown -R greeter:greeter /var/log/regreet /var/lib/regreet
  fi

  # Configurar pam_gnome_keyring no greetd se ainda nao estiver presente.
  # Obs.: o keyring só é destravado quando a senha é digitada no regreet;
  # no autologin (initial_session) não há senha, então ele fica trancado.
  if [[ -f "/etc/pam.d/greetd" ]] && ! grep -q "pam_gnome_keyring" "/etc/pam.d/greetd"; then
    log_info "  Configurando suporte a gnome-keyring no PAM do greetd..."
    backup_file /etc/pam.d/greetd
    sudo sed -i '/auth.*system-local-login/a auth       optional     pam_gnome_keyring.so' /etc/pam.d/greetd
    sudo sed -i '/session.*system-local-login/a session    optional     pam_gnome_keyring.so auto_start' /etc/pam.d/greetd
    sudo sed -i '/password.*system-local-login/a password   optional     pam_gnome_keyring.so' /etc/pam.d/greetd 2>/dev/null || true
  fi

  log_info "Greeter configurado com sucesso!"
}

# Detecta o fabricante da GPU principal: amd | intel | nvidia | unknown
detect_gpu_vendor() {
  local info
  info="$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d controller|display controller' || true)"

  # Prioriza GPU dedicada em máquinas híbridas
  if grep -qiE 'nvidia' <<<"$info"; then
    echo nvidia
  elif grep -qiE 'amd|ati|radeon' <<<"$info"; then
    echo amd
  elif grep -qi 'intel' <<<"$info"; then
    echo intel
  else
    echo unknown
  fi
}

setup_gaming() {
  log_step "Configurando suporte a multilib e drivers de gaming..."
  setup_multilib

  local gpu
  gpu="$(detect_gpu_vendor)"
  log_info "GPU detectada: $gpu"

  local gaming_pacman_pkgs=("gamemode" "steam" "lib32-pipewire" "goverlay" "lutris")
  case "$gpu" in
    amd) gaming_pacman_pkgs+=("vulkan-radeon" "lib32-vulkan-radeon" "lact") ;;
    intel) gaming_pacman_pkgs+=("vulkan-intel" "lib32-vulkan-intel") ;;
    nvidia) gaming_pacman_pkgs+=("nvidia-utils" "lib32-nvidia-utils" "lact") ;;
    *)
      log_warn "GPU não identificada: instale manualmente o driver Vulkan (vulkan-radeon/vulkan-intel/nvidia-utils)"
      FAILED_STEPS+=("gaming:vulkan-driver")
      ;;
  esac

  log_step "Instalando ferramentas de gaming via pacman (${gaming_pacman_pkgs[*]})..."
  if ! run_logged sudo pacman -S --noconfirm --needed "${gaming_pacman_pkgs[@]}"; then
    log_warn "Falha na instalação em lote de gaming pelo pacman. Tentando pacote por pacote..."
    for pkg in "${gaming_pacman_pkgs[@]}"; do
      if ! run_logged sudo pacman -S --noconfirm --needed "$pkg"; then
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
