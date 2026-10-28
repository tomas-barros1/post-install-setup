#!/bin/bash
# ==============================================================================
# lib/network.sh - Rede (iwd puro), regdomain e firewall
# ==============================================================================

# Instala um arquivo em /etc a partir do stdin, só se o conteúdo mudou (com backup).
_install_root_file() {
  local dest="$1" tmp rc=0
  tmp="$(mktemp)"
  cat >"$tmp"

  if [[ -f "$dest" ]] && sudo cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 0
  fi

  backup_file "$dest"
  sudo install -D -m 0644 "$tmp" "$dest" || rc=$?
  rm -f "$tmp"
  return "$rc"
}

setup_network() {
  log_step "Configurando rede (iwd puro: ele mesmo faz o DHCP do Wi‑Fi)..."

  # Sem iwd, mascarar o NetworkManager deixaria o sistema sem rede.
  if ! command -v iwctl &>/dev/null; then
    log_warn "  ✗ iwd não encontrado; NetworkManager NÃO será mascarado para evitar perda de rede"
    FAILED_STEPS+=("network:iwd-missing")
    return 1
  fi

  # A troca é feita SEM parar nada agora (não derruba a sessão atual):
  # só vale a partir do próximo boot.
  local service
  for service in \
    NetworkManager.service \
    NetworkManager-wait-online.service \
    systemd-networkd.service \
    systemd-networkd.socket \
    systemd-networkd-wait-online.service; do
    sudo systemctl disable "$service" &>/dev/null || true
    sudo systemctl mask "$service" &>/dev/null || true
  done

  enable_iwd
  if [[ "${POST_INSTALL_WIRED_NETWORKD:-false}" == "true" ]]; then
    # Opt-in: o iwd não cuida de cabo
    sudo systemctl unmask systemd-networkd.service systemd-networkd.socket &>/dev/null || true
    setup_wired_networkd
  fi
  setup_resolved
  disable_wifi_power_save
  setup_regdom

  log_warn "Rede trocada: vale a partir do próximo boot. Wi‑Fi: use 'impala' ou 'iwctl'."
}

enable_iwd() {
  log_step "Habilitando iwd..."

  # DNS via systemd-resolved (sem ele o iwd, com EnableNetworkConfiguration, fica sem DNS)
  _install_root_file /etc/iwd/main.conf <<'CONF'
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=systemd
CONF

  if sudo systemctl enable iwd.service &>/dev/null; then
    log_info "  ✓ iwd.service habilitado (inicia no próximo boot)"
  else
    log_warn "  ✗ Falha ao habilitar iwd.service"
    FAILED_STEPS+=("network:enable-iwd")
  fi
}

# O iwd só cuida de Wi‑Fi: sem isso, com o NetworkManager mascarado, o cabo ficaria sem DHCP.
setup_wired_networkd() {
  log_step "Configurando DHCP para cabo (systemd-networkd)..."

  _install_root_file /etc/systemd/network/20-wired.network <<'CONF'
[Match]
Name=en* eth*

[Network]
DHCP=yes

[DHCPv4]
RouteMetric=100
CONF

  if sudo systemctl enable systemd-networkd.service &>/dev/null; then
    log_info "  ✓ systemd-networkd habilitado (somente interfaces cabeadas)"
  else
    log_warn "  ✗ Falha ao habilitar systemd-networkd"
    FAILED_STEPS+=("network:enable-networkd")
  fi
}

setup_resolved() {
  log_step "Habilitando systemd-resolved..."

  if sudo systemctl enable --now systemd-resolved.service &>/dev/null; then
    sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    log_info "  ✓ systemd-resolved ativo e /etc/resolv.conf apontando para o stub"
  else
    log_warn "  ✗ Falha ao habilitar systemd-resolved"
    FAILED_STEPS+=("network:resolved")
  fi
}

disable_wifi_power_save() {
  log_step "Desativando economia de energia do Wi‑Fi..."

  # Tweak específico de placas Intel: só aplica se o driver existir
  if [[ -d /sys/module/iwlwifi ]] || lspci -k 2>/dev/null | grep -qi iwlwifi; then
    _install_root_file /etc/modprobe.d/iwlwifi.conf <<'CONF'
options iwlwifi power_save=0
options iwlmvm power_scheme=1
CONF
    log_info "  ✓ Tweaks aplicados para drivers Intel (iwlwifi/iwlmvm)"
  else
    log_info "  ✓ Placa Intel não detectada; tweak iwlwifi ignorado"
  fi

  _install_root_file /etc/udev/rules.d/81-wifi-powersave.rules <<'CONF'
ACTION=="add", SUBSYSTEM=="net", KERNEL=="wl*", RUN+="/usr/bin/iw dev %k set power_save off"
CONF
  log_info "  ✓ Regra udev para desligar power save do Wi‑Fi"

  if sudo udevadm control --reload 2>/dev/null; then
    log_info "  ✓ Regras udev recarregadas"
  else
    log_warn "  ✗ Falha ao recarregar regras udev"
    FAILED_STEPS+=("network:udev-reload")
  fi
}

# wireless-regdb é instalado pelo perfil, mas só tem efeito se o país for definido.
setup_regdom() {
  local country="${POST_INSTALL_REGDOM:-BR}"
  local conf="/etc/conf.d/wireless-regdom"

  if [[ ! -f "$conf" ]]; then
    log_warn "  $conf não existe (wireless-regdb ausente?); regdomain ignorado"
    return 0
  fi

  if grep -q "^WIRELESS_REGDOM=\"${country}\"" "$conf"; then
    log_info "  ✓ Regdomain já é ${country}"
  else
    backup_file "$conf"
    # Comenta qualquer país ativo e descomenta o escolhido
    sudo sed -i -E 's/^(WIRELESS_REGDOM=)/#\1/' "$conf"
    sudo sed -i -E "s/^#(WIRELESS_REGDOM=\"${country}\")/\1/" "$conf"
    log_info "  ✓ Regdomain definido para ${country}"
  fi

  sudo iw reg set "$country" 2>/dev/null || true
}

setup_firewall() {
  log_step "Configurando firewall (UFW)..."

  sudo ufw default deny incoming &>/dev/null || FAILED_STEPS+=("ufw:default-in")
  sudo ufw default allow outgoing &>/dev/null || FAILED_STEPS+=("ufw:default-out")

  # Só abre SSH se existir um servidor SSH habilitado
  if systemctl is-enabled --quiet sshd.service 2>/dev/null; then
    if sudo ufw limit ssh &>/dev/null; then
      log_info "  ✓ SSH liberado (com rate limit), pois sshd está habilitado"
    else
      log_warn "Falha ao liberar SSH no UFW"
      FAILED_STEPS+=("ufw:allow-ssh")
    fi
  fi

  if sudo ufw status | grep -q '^Status: active'; then
    log_info "UFW já estava ativo"
  elif sudo ufw --force enable &>/dev/null; then
    log_info "UFW ativado!"
  else
    log_warn "Falha ao ativar UFW"
    FAILED_STEPS+=("ufw:enable")
  fi

  # Sem o serviço habilitado, as regras não são carregadas no boot (Arch)
  if sudo systemctl enable ufw.service &>/dev/null; then
    log_info "  ✓ ufw.service habilitado (persiste após reboot)"
  else
    log_warn "Falha ao habilitar ufw.service"
    FAILED_STEPS+=("ufw:service")
  fi
}
