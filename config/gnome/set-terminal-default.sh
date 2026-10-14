#!/usr/bin/env bash
# ==============================================================================
# Define o terminal padrão do GNOME via xdg-terminal-exec, do mesmo modo que os
# perfis de window manager (Hyprland/Sway/Noctalia).
#
# O xdg-terminal-exec respeita ~/.config/xdg-terminals.list, então o terminal
# realmente aberto segue essa ordem de prioridade (foot, ghostty, alacritty,
# kitty, rio, ...). No GNOME só o alacritty é instalado, então ele é usado.
#
# OBS: o antigo uso de `update-alternatives --set x-terminal-emulator` era um
# costume do Debian/Ubuntu e não existe no Arch (era um no-op).
# ==============================================================================

TERMINAL="xdg-terminal-exec"

if ! command -v "$TERMINAL" &>/dev/null; then
  echo "Aviso: '$TERMINAL' não encontrado. Instale o pacote 'xdg-terminal-exec'." >&2
fi

if command -v gsettings &>/dev/null; then
  # Terminal padrão do GNOME (menus, "Abrir no Terminal", atalhos, etc.)
  gsettings set org.gnome.desktop.default-applications.terminal exec "$TERMINAL" 2>/dev/null || true
  gsettings set org.gnome.desktop.default-applications.terminal exec-arg '--' 2>/dev/null || true

  # Extensão nautilus-open-any-terminal ("Abrir no Terminal" no Nautilus)
  gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal "$TERMINAL" 2>/dev/null || true

  echo "Terminal padrão do GNOME definido para '$TERMINAL'."
fi
