#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  dev-setup.sh — mira qué sistema es y llama al script que toca
#
#  Uso:  ~/.dotfiles/dev-setup.sh [opciones]
#
#  Las opciones se pasan tal cual al script de abajo:
#    --no-tex  --no-docker  --no-ds  --no-gui  --minimal
#
#  Si prefieres saltarte la detección, corre directamente
#  dev/macos.sh, dev/fedora.sh o dev/arch.sh.
# ════════════════════════════════════════════════════════════
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    Darwin) target=macos ;;
    Linux)
        if   command -v pacman >/dev/null 2>&1; then target=arch
        elif command -v dnf    >/dev/null 2>&1; then target=fedora
        else
            printf '\n\033[38;2;249;115;22m✗ distribución no contemplada.\033[0m\n' >&2
            printf '  Hay scripts para Fedora y Arch en %s/dev/.\n\n' "$DOTFILES" >&2
            exit 1
        fi ;;
    *) printf '\n\033[38;2;249;115;22m✗ sistema %s no contemplado.\033[0m\n\n' "$(uname -s)" >&2; exit 1 ;;
esac

exec "$DOTFILES/dev/$target.sh" "$@"
