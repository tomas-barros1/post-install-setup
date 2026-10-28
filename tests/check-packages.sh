#!/bin/bash
# ==============================================================================
# tests/check-packages.sh - Valida os perfis (rodar num Arch, ex.: container CI)
#
#  - cada perfil carrega sem erro e define as variáveis esperadas
#  - não há pacotes duplicados dentro de PACMAN_PACKAGES
#  - os pacotes de PACMAN_PACKAGES existem nos repositórios configurados
#    (pacotes que só existem no Chaotic AUR geram apenas AVISO; use STRICT=1 para falhar)
# ==============================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
status=0
warnings=0

for profile in "$REPO_ROOT"/profiles/*.sh; do
  name="$(basename "$profile" .sh)"
  echo "== perfil: $name"

  out="$(
    PACMAN_PACKAGES=() AUR_PACKAGES=() DOTFILES_DIRS=()
    # shellcheck source=/dev/null
    source "$profile" || exit 90

    [[ -n "${PROFILE_NAME:-}" ]] || echo "ERRO: PROFILE_NAME ausente"
    [[ -n "${PROFILE_DESCRIPTION:-}" ]] || echo "ERRO: PROFILE_DESCRIPTION ausente"
    [[ ${#PACMAN_PACKAGES[@]} -gt 0 ]] || echo "ERRO: PACMAN_PACKAGES vazio"

    while read -r dup; do
      [[ -n "$dup" ]] && echo "ERRO: pacote duplicado: $dup"
    done < <(printf '%s\n' "${PACMAN_PACKAGES[@]}" | sort | uniq -d)

    if command -v pacman &>/dev/null; then
      for pkg in "${PACMAN_PACKAGES[@]}"; do
        pacman -Si "$pkg" &>/dev/null || echo "AVISO: '$pkg' não existe nos repos oficiais (Chaotic AUR?)"
      done
    fi
  )"
  rc=$?

  if [[ $rc -ne 0 ]]; then
    echo "ERRO: falha ao carregar o perfil (código $rc)"
    status=1
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "  $line"
    case "$line" in
      ERRO*) status=1 ;;
      AVISO*)
        warnings=$((warnings + 1))
        echo "::warning::$name: $line"
        ;;
    esac
  done <<<"$out"
done

if [[ "${STRICT:-0}" == "1" && $warnings -gt 0 ]]; then
  status=1
fi

exit "$status"
