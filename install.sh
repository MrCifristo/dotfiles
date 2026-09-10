#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  install.sh — deja el rice NERV listo en macOS o Fedora
#
#  Uso (desde un clon del repo):
#      ~/.dotfiles/install.sh
#
#  Qué hace, en orden:
#    1. Instala los paquetes que falten (brew / dnf) y la fuente.
#    2. Instala Oh My Zsh + plugins si no están.
#    3. Enlaza (symlink) cada config a su sitio, guardando copia
#       de lo que hubiera en ~/.dotfiles-backup/<fecha>/.
#    4. Pone zsh como shell por defecto si no lo es.
#
#  Es idempotente: se puede volver a correr las veces que haga falta.
# ════════════════════════════════════════════════════════════
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
OS="$(uname -s)"

P=$'\033[38;2;124;58;237m'; G=$'\033[38;2;163;230;53m'
O=$'\033[38;2;249;115;22m'; D=$'\033[38;2;107;100;128m'; RS=$'\033[0m'
step() { printf '\n%s▶ %s%s\n' "$P" "$1" "$RS"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$RS" "$1"; }
warn() { printf '  %s!%s %s\n' "$O" "$RS" "$1"; }
info() { printf '  %s·%s %s\n' "$D" "$RS" "$1"; }

# ────────────────────────────────────────────────────────────
#  1. Paquetes
# ────────────────────────────────────────────────────────────
install_macos() {
    if ! command -v brew >/dev/null 2>&1; then
        step "Instalando Homebrew"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            [ -x "$b" ] && eval "$("$b" shellenv)" && break
        done
    fi
    step "Paquetes (brew bundle)"
    brew bundle --file "$DOTFILES/packages/Brewfile" --no-upgrade
    ok "paquetes y fuente listos"
}

install_fedora() {
    step "Paquetes (dnf)"
    local missing=()
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        rpm -q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done < "$DOTFILES/packages/fedora.txt"
    if [ ${#missing[@]} -gt 0 ]; then
        info "faltan: ${missing[*]}"
        sudo dnf install -y "${missing[@]}"
    fi
    ok "paquetes listos"

    if ! command -v starship >/dev/null 2>&1; then
        step "Starship"
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi

    step "Fuente JetBrainsMono Nerd Font"
    if fc-list 2>/dev/null | grep -qi 'JetBrainsMono Nerd Font'; then
        ok "ya instalada"
    else
        local fdir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont" tmp
        tmp="$(mktemp -d)"
        curl -fsSL -o "$tmp/jb.zip" \
            https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
        mkdir -p "$fdir"
        unzip -qo "$tmp/jb.zip" -d "$fdir" '*.ttf'
        rm -rf "$tmp"
        fc-cache -f >/dev/null
        ok "instalada en $fdir"
    fi
}

case "$OS" in
    Darwin) install_macos ;;
    Linux)
        if command -v dnf >/dev/null 2>&1; then install_fedora
        else warn "distro sin dnf: instala a mano kitty fastfetch starship eza bat zoxide fzf zsh imagemagick y la Nerd Font"; fi ;;
    *) warn "sistema $OS no reconocido: se saltan los paquetes" ;;
esac

# ────────────────────────────────────────────────────────────
#  2. Oh My Zsh + plugins
# ────────────────────────────────────────────────────────────
step "Oh My Zsh"
export ZSH="$HOME/.oh-my-zsh"
if [ -d "$ZSH" ]; then
    ok "ya instalado"
else
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ok "instalado"
fi
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"
for repo in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting; do
    name="${repo#*/}"
    if [ -d "$ZSH_CUSTOM/plugins/$name" ]; then
        ok "plugin $name"
    else
        git clone -q --depth 1 "https://github.com/$repo" "$ZSH_CUSTOM/plugins/$name"
        ok "plugin $name (clonado)"
    fi
done

# ────────────────────────────────────────────────────────────
#  3. Symlinks
# ────────────────────────────────────────────────────────────
step "Enlazando configs"
link() {
    local src="$DOTFILES/$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        ok "$dst"
        return
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mkdir -p "$BACKUP/$(dirname "${dst#$HOME/}")"
        mv "$dst" "$BACKUP/${dst#$HOME/}"
        info "copia de seguridad: $BACKUP/${dst#$HOME/}"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    ok "$dst → $1"
}

link zsh/zshrc               "$HOME/.zshrc"
link starship/starship.toml  "$HOME/.config/starship.toml"
link kitty/kitty.conf        "$HOME/.config/kitty/kitty.conf"
link kitty/nerv.conf         "$HOME/.config/kitty/nerv.conf"
link kitty/nerv.session      "$HOME/.config/kitty/nerv.session"
link kitty/linux.conf        "$HOME/.config/kitty/linux.conf"
link kitty/macos.conf        "$HOME/.config/kitty/macos.conf"
link nerv                    "$HOME/.config/nerv"
link bin/nerv-boot           "$HOME/.local/bin/nerv-boot"

# la caché del logo se regenera con la imagen del repo
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/nerv"

[ -f "$HOME/.zshrc.local" ] || {
    printf '# Cosas solo de esta máquina (no se versiona).\n' > "$HOME/.zshrc.local"
    info "creado ~/.zshrc.local para lo específico de esta máquina"
}

# ────────────────────────────────────────────────────────────
#  4. Shell por defecto
# ────────────────────────────────────────────────────────────
step "Shell por defecto"
zsh_path="$(command -v zsh)"
if [ "${SHELL:-}" = "$zsh_path" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
    ok "ya es zsh"
elif [ -t 0 ]; then
    chsh -s "$zsh_path" && ok "cambiada a zsh (haz logout/login)" \
        || warn "no pude cambiar la shell; hazlo con: chsh -s $zsh_path"
else
    warn "cambia la shell a mano: chsh -s $zsh_path"
fi

printf '\n%s▛▀▀ NERV MAGI SYSTEM ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀\n' "$P"
printf '▌%s  Listo. Abre kitty (o corre %snerv%s en una shell nueva).\n' "$RS" "$G" "$RS"
printf '%s▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄%s\n\n' "$P" "$RS"
