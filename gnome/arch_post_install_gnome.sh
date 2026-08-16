#!/bin/bash
# Wrapper de retrocompatibilidade para o perfil GNOME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../install.sh" --profile gnome "$@"
