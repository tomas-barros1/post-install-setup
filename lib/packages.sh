#!/bin/bash
# ==============================================================================
# lib/packages.sh - Gerenciamento de Pacotes (Pacman, Yay, Chaotic-AUR)
# ==============================================================================

install_pacman_packages() {
  local packages=("$@")
  if [[ ${#packages[@]} -eq 0 ]]; then
    return 0
  fi

  log_step "Atualizando base de dados e instalando pacotes oficiais (${#packages[@]} pacotes)..."

  sudo pacman -Syu --noconfirm

  if ! sudo pacman -S --noconfirm --needed "${packages[@]}"; then
    log_warn "Falha na instalação em lote pelo pacman. Tentando pacote por pacote..."
    for pkg in "${packages[@]}"; do
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
    log_info "yay (AUR Helper) já instalado"
    return 0
  fi

  log_step "Instalando yay (AUR helper)..."
  local tmp_dir
  tmp_dir=$(mktemp -d)

  if ! sudo pacman -S --needed --noconfirm git base-devel; then
    log_warn "Falha ao instalar dependências de build do yay (base-devel)"
    FAILED_STEPS+=("yay:base-devel")
    rm -rf "$tmp_dir"
    return 1
  fi

  # Preferir yay-bin se disponível para compilação instantânea
  if git clone https://aur.archlinux.org/yay-bin.git "$tmp_dir/yay" 2>/dev/null || \
     git clone https://aur.archlinux.org/yay.git "$tmp_dir/yay"; then
    if (cd "$tmp_dir/yay" && makepkg -si --noconfirm); then
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

  if ! sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' || \
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

  log_info "Chaotic AUR configurado com sucesso!"
}

install_aur_packages() {
  local packages=("$@")
  if [[ ${#packages[@]} -eq 0 ]]; then
    return 0
  fi

  if ! command -v yay &>/dev/null; then
    log_error "yay não encontrado para instalação de pacotes AUR!"
    FAILED_STEPS+=("aur:missing-yay")
    return 1
  fi

  log_step "Instalando pacotes do AUR via yay (${#packages[@]} pacotes)..."

  if ! yay -S --noconfirm --needed "${packages[@]}"; then
    log_warn "Falha na instalação em lote do AUR. Tentando pacote por pacote..."
    for pkg in "${packages[@]}"; do
      if ! yay -S --noconfirm --needed "$pkg"; then
        log_warn "Falha ao instalar pacote AUR: $pkg"
        FAILED_PACKAGES+=("$pkg (aur)")
      fi
    done
  fi

  log_info "Pacotes AUR processados!"
}

cleanup_yay() {
  if command -v yay &>/dev/null; then
    log_step "Limpando dependências e cache de build do yay..."
    if yay -Ycc --noconfirm 2>/dev/null; then
      log_info "Dependências de build removidas!"
    else
      log_warn "Falha ao limpar pacotes de build do yay (pode já estar limpo)"
    fi
  fi
}
