#!/bin/bash
# Wrapper de retrocompatibilidade para o perfil Hyprland Noctalia
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../install.sh" --profile hyprland-noctalia "$@"
