#!/bin/bash
# ==============================================================================
# lib/packages.sh - Gerenciamento de Pacotes (Pacman, Yay, Chaotic-AUR)
# ==============================================================================

PACMAN_CONF="${PACMAN_CONF:-/etc/pacman.conf}"

# Garante uma opção em [options] do pacman.conf (descomenta se existir comentada).
_pacman_conf_set() {
  local key="$1" value="${2:-}" line
  line="$key"
  [[ -n "$value" ]] && line="$key = $value"

  if grep -Eq "^${key}([[:space:]]|=|\$)" "$PACMAN_CONF"; then
    return 0 # já definido (respeita o valor do usuário)
  elif grep -Eq "^#${key}([[:space:]]|=|\$)" "$PACMAN_CONF"; then
    sudo sed -i -E "s|^#${key}([[:space:]]*=.*)?\$|${line}|" "$PACMAN_CONF"
  else
    sudo sed -i "/^\[options\]/a ${line}" "$PACMAN_CONF"
  fi
}

setup_pacman_conf() {
  log_step "Ajustando pacman.conf (Color, ILoveCandy, ParallelDownloads)..."
  local key need=false
  for key in Color ILoveCandy ParallelDownloads; do
    grep -Eq "^${key}([[:space:]]|=|\$)" "$PACMAN_CONF" || need=true
  done

  if [[ "$need" == "false" ]]; then
    log_info "pacman.conf já está ajustado"
    return 0
  fi

  backup_file "$PACMAN_CONF"
  _pacman_conf_set Color
  _pacman_conf_set ILoveCandy
  _pacman_conf_set ParallelDownloads 10
  log_info "pacman.conf ajustado!"
}

setup_makepkg_conf() {
  local conf="${MAKEPKG_CONF:-/etc/makepkg.conf}"
  [[ -f "$conf" ]] || return 0

  if grep -Eq '^MAKEFLAGS=' "$conf"; then
    log_info "MAKEFLAGS já definido no makepkg.conf"
    return 0
  fi

  if grep -Eq '^#MAKEFLAGS=' "$conf"; then
    backup_file "$conf"
    # $(nproc) é avaliado pelo próprio makepkg na hora do build
    sudo sed -i -E 's|^#MAKEFLAGS=.*|MAKEFLAGS="-j$(nproc)"|' "$conf"
    log_info "makepkg usará todos os núcleos (MAKEFLAGS=-j\$(nproc))"
  fi
}

setup_mirrors() {
  local countries="${POST_INSTALL_MIRROR_COUNTRIES:-Brazil,United States}"
  log_step "Otimizando mirrors com reflector (${countries})..."

  if ! command -v reflector &>/dev/null; then
    if ! run_logged sudo pacman -S --needed --noconfirm reflector; then
      FAILED_STEPS+=("mirrors:reflector")
      return 1
    fi
  fi

  backup_file /etc/pacman.d/mirrorlist
  # O reflector só grava o arquivo no final; se falhar, a mirrorlist original permanece.
  if ! run_logged sudo reflector --country "$countries" --protocol https --age 24 \
    --latest 10 --sort rate --save /etc/pacman.d/mirrorlist; then
    log_warn "reflector falhou; mantendo a mirrorlist atual"
    FAILED_STEPS+=("mirrors:reflector-run")
    return 1
  fi

  # Atualização semanal automática
  printf -- '--save /etc/pacman.d/mirrorlist\n--protocol https\n--country %s\n--latest 10\n--age 24\n--sort rate\n' \
    "$countries" | sudo tee /etc/xdg/reflector/reflector.conf >/dev/null
  sudo systemctl enable reflector.timer &>/dev/null || true
  log_info "Mirrors otimizados e reflector.timer habilitado!"
}

install_pacman_packages() {
  local packages=("$@")
  if [[ ${#packages[@]} -eq 0 ]]; then
    return 0
  fi

  log_step "Atualizando base de dados e instalando pacotes oficiais (${#packages[@]} pacotes)..."

  if ! run_logged sudo pacman -Syu --noconfirm; then
    log_error "Falha ao atualizar o sistema (pacman -Syu). Verifique rede/mirrors e tente novamente."
    FAILED_STEPS+=("pacman:upgrade")
    return 1
  fi

  if ! run_logged sudo pacman -S --noconfirm --needed "${packages[@]}"; then
    log_warn "Falha na instalação em lote pelo pacman. Tentando pacote por pacote..."
    for pkg in "${packages[@]}"; do
      if ! run_logged sudo pacman -S --noconfirm --needed "$pkg"; then
        log_warn "Falha ao instalar: $pkg"
        FAILED_PACKAGES+=("$pkg (pacman)")
      fi
    done
  fi

  log_info "Pacotes oficiais processados!"
}

install_yay() {
  if command -v yay &>/dev/null; then
    log_info "yay (AUR Helper) já instalado"
    return 0
  fi

  log_step "Instalando yay (AUR helper)..."
  local tmp_dir
  tmp_dir=$(mktemp -d)

  if ! run_logged sudo pacman -S --needed --noconfirm git base-devel; then
    log_warn "Falha ao instalar dependências de build do yay (base-devel)"
    FAILED_STEPS+=("yay:base-devel")
    rm -rf "$tmp_dir"
    return 1
  fi

  # Preferir yay-bin se disponível para compilação instantânea
  if git clone https://aur.archlinux.org/yay-bin.git "$tmp_dir/yay" 2>/dev/null ||
    git clone https://aur.archlinux.org/yay.git "$tmp_dir/yay"; then
    if (cd "$tmp_dir/yay" && run_logged makepkg -si --noconfirm); then
      log_info "yay instalado com sucesso!"
    else
      log_warn "Falha ao compilar/instalar yay"
      FAILED_STEPS+=("yay:makepkg")
      rm -rf "$tmp_dir"
      return 1
    fi
  else
    log_warn "Falha ao clonar repositório do yay"
    FAILED_STEPS+=("yay:clone")
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
}

setup_chaotic_aur() {
  if grep -q "chaotic-aur" /etc/pacman.conf 2>/dev/null; then
    log_info "Chaotic AUR já configurado"
    return 0
  fi

  log_step "Configurando repositório Chaotic AUR..."

  if ! run_logged sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com; then
    log_warn "Falha ao receber chave do Chaotic AUR"
    FAILED_STEPS+=("chaotic-aur:recv-key")
    return 1
  fi

  if ! run_logged sudo pacman-key --lsign-key 3056513887B78AEB; then
    log_warn "Falha ao assinar chave do Chaotic AUR"
    FAILED_STEPS+=("chaotic-aur:lsign-key")
    return 1
  fi

  if ! run_logged sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' ||
    ! sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'; then
    log_warn "Falha ao instalar keyring/mirrorlist do Chaotic AUR"
    FAILED_STEPS+=("chaotic-aur:packages")
    return 1
  fi

  if ! grep -q "chaotic-aur" /etc/pacman.conf; then
    backup_file /etc/pacman.conf
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
  fi

  if ! run_logged sudo pacman -Syu --noconfirm; then
    log_warn "Falha ao sincronizar pacman após adicionar Chaotic AUR"
    FAILED_STEPS+=("chaotic-aur:sync")
    return 1
  fi

  log_info "Chaotic AUR configurado com sucesso!"
}

setup_multilib() {
  if grep -q "^\[multilib\]" /etc/pacman.conf 2>/dev/null; then
    log_info "Repositório multilib já está habilitado"
    return 0
  fi

  log_step "Habilitando repositório multilib no pacman.conf..."
  backup_file /etc/pacman.conf

  if grep -q "^#\[multilib\]" /etc/pacman.conf 2>/dev/null; then
    sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
  else
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
  fi

  log_step "Atualizando base de dados do pacman com multilib..."
  if ! run_logged sudo pacman -Syu --noconfirm; then
    log_warn "Falha ao sincronizar pacman após habilitar multilib"
    FAILED_STEPS+=("multilib:sync")
    return 1
  fi

  log_info "Repositório multilib habilitado com sucesso!"
}

install_aur_packages() {
  local packages=("$@")
  if [[ ${#packages[@]} -eq 0 ]]; then
    return 0
  fi

  local to_pacman=()
  local to_aur=()

  # Se o pacote existir em qualquer repositório do Pacman (Core, Extra, Multilib, Chaotic-AUR), usa pacman diretamente
  for pkg in "${packages[@]}"; do
    if pacman -Si "$pkg" &>/dev/null; then
      to_pacman+=("$pkg")
    else
      to_aur+=("$pkg")
    fi
  done

  if [[ ${#to_pacman[@]} -gt 0 ]]; then
    log_step "Instalando pacotes disponíveis em repositórios binários / Chaotic AUR (${#to_pacman[@]} pacotes)..."
    if ! run_logged sudo pacman -S --noconfirm --needed "${to_pacman[@]}"; then
      log_warn "Falha na instalação em lote via pacman. Tentando pacote por pacote..."
      for pkg in "${to_pacman[@]}"; do
        if ! run_logged sudo pacman -S --noconfirm --needed "$pkg"; then
          log_warn "Falha ao instalar via pacman: $pkg. Adicionando ao fallback do AUR..."
          to_aur+=("$pkg")
        fi
      done
    fi
  fi

  if [[ ${#to_aur[@]} -eq 0 ]]; then
    log_info "Todos os pacotes foram instalados via binários pré-compilados do Pacman/Chaotic AUR!"
    return 0
  fi

  if ! command -v yay &>/dev/null; then
    log_error "yay não encontrado para instalação de pacotes AUR!"
    FAILED_STEPS+=("aur:missing-yay")
    return 1
  fi

  log_step "Instalando pacotes restantes exclusivamente do AUR via yay (${#to_aur[@]} pacotes)..."
  log_warn "AUR é instalado com --noconfirm (PKGBUILDs NÃO são revisados)."
  local git_pkgs=()
  for pkg in "${to_aur[@]}"; do
    [[ "$pkg" == *-git ]] && git_pkgs+=("$pkg")
  done
  if [[ ${#git_pkgs[@]} -gt 0 ]]; then
    log_warn "Pacotes -git compilam o HEAD do upstream (sem versão fixa): ${git_pkgs[*]}"
  fi

  if ! run_logged yay -S --noconfirm --needed "${to_aur[@]}"; then
    log_warn "Falha na instalação em lote do AUR. Tentando pacote por pacote..."
    for pkg in "${to_aur[@]}"; do
      if ! run_logged yay -S --noconfirm --needed "$pkg"; then
        log_warn "Falha ao instalar pacote AUR: $pkg"
        FAILED_PACKAGES+=("$pkg (aur)")
      fi
    done
  fi

  log_info "Pacotes AUR processados!"
}

cleanup_yay() {
  if command -v yay &>/dev/null && [[ -d "$HOME/.cache/yay" ]]; then
    log_step "Limpando fontes e pacotes temporários de build do yay..."
    # Remove só src/ e pkg/ de cada build; NÃO remove pacotes órfãos do sistema.
    find "$HOME/.cache/yay" -mindepth 2 -maxdepth 2 -type d \( -name src -o -name pkg \) -exec rm -rf {} + 2>/dev/null || true
    log_info "Cache de build limpo!"
  fi

  local orphans
  orphans=$(pacman -Qdtq 2>/dev/null | wc -l)
  if [[ "$orphans" -gt 0 ]]; then
    log_warn "$orphans pacote(s) órfão(s) no sistema. Revise com 'pacman -Qdtq' e remova manualmente se quiser."
  fi
}
