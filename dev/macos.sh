#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  macos.sh — entorno de desarrollo en macOS
#
#  Uso:  ~/.dotfiles/dev/macos.sh [--no-tex] [--no-docker]
#                                 [--no-ds]  [--no-gui] [--minimal]
#
#  Deja lista una máquina para tus proyectos: Next.js/NestJS con
#  pnpm, Postgres y Redis en Docker, y notebooks de Python.
#  Se puede correr las veces que haga falta.
# ════════════════════════════════════════════════════════════
set -uo pipefail

DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$DEV_DIR/common.sh"
parse_flags "$@"

[ "$(uname -s)" = "Darwin" ] || die "esto es para macOS"

printf '\n%s  NERV — entorno de desarrollo · macOS %s (%s)%s\n' "$_P" \
    "$(sw_vers -productVersion 2>/dev/null)" "$(uname -m)" "$_RS"

# ════════════════════════════════════════════════════════════
#  1. Command Line Tools
# ════════════════════════════════════════════════════════════
# Traen git, clang y las cabeceras del sistema. Sin esto Homebrew no
# arranca y node-gyp no compila nada.
step "Command Line Tools de Xcode"
if xcode-select -p >/dev/null 2>&1; then
    ok "ya están ($(xcode-select -p))"
else
    info "se abrirá una ventana de macOS: dale a «Instalar» y espera"
    runq xcode-select --install || true
    if dry; then
        ok "(dry-run) aquí esperaría a que termine la instalación"
    else
        until xcode-select -p >/dev/null 2>&1; do
            printf '  %s·%s esperando a que termine la instalación…\r' "$_D" "$_RS"
            /bin/sleep 20
        done
        printf '\n'; ok "instalados"
    fi
fi

# ════════════════════════════════════════════════════════════
#  2. Homebrew
# ════════════════════════════════════════════════════════════
step "Homebrew"
if ! have brew; then
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
fi
if have brew; then
    ok "ya está ($(brew --prefix))"
else
    dry && run /bin/bash -c "curl -fsSL .../Homebrew/install/HEAD/install.sh"
    dry || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || die "falló la instalación de Homebrew"
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
    dry || have brew || die "Homebrew quedó instalado pero no está en el PATH"
    dry || ok "instalado en $(brew --prefix)"
fi
export HOMEBREW_NO_ENV_HINTS=1

# ── instala en lote; si el lote falla, uno por uno ──────────
# Un nombre que ya no existe hace que `brew install` aborte con todo
# el lote, así que se reintenta individualmente para salvar el resto.
brew_install() {
    local kind="$1"; shift
    local want=("$@") todo=()
    for p in "${want[@]}"; do
        if [ "$kind" = "--cask" ]; then
            brew list --cask "$p" >/dev/null 2>&1 && continue
        else
            brew list --formula "$p" >/dev/null 2>&1 && continue
        fi
        todo+=("$p")
    done
    if [ ${#todo[@]} -eq 0 ]; then ok "nada que instalar"; return 0; fi

    if dry; then run brew install "$kind" "${todo[@]}"; return 0; fi
    info "instalando: ${todo[*]}"
    if [ "$kind" = "--cask" ]; then
        brew install --cask --quiet "${todo[@]}" >/dev/null 2>&1 && { ok "listo (${#todo[@]})"; return 0; }
    else
        brew install --quiet "${todo[@]}" >/dev/null 2>&1 && { ok "listo (${#todo[@]})"; return 0; }
    fi

    info "el lote falló; reintentando uno por uno"
    local fail=0
    for p in "${todo[@]}"; do
        if [ "$kind" = "--cask" ]; then
            brew install --cask --quiet "$p" >/dev/null 2>&1 || { warn "no se pudo instalar «$p»"; fail=1; }
        else
            brew install --quiet "$p" >/dev/null 2>&1 || { warn "no se pudo instalar «$p»"; fail=1; }
        fi
    done
    [ "$fail" -eq 0 ] && ok "listo"
}

# ════════════════════════════════════════════════════════════
#  3. Construcción y librerías nativas
# ════════════════════════════════════════════════════════════
# cairo/pango/jpeg/giflib/librsvg → node-canvas (chartjs-node-canvas,
#                                   los reportes de ManoCard)
# vips                            → sharp
step "Librerías nativas (node-canvas, sharp)"
brew_install --formula pkg-config cmake cairo pango jpeg giflib librsvg vips

# ════════════════════════════════════════════════════════════
#  4. Git, GitHub y terminal
# ════════════════════════════════════════════════════════════
step "Git y GitHub CLI"
brew_install --formula git git-lfs gh lazygit

step "Herramientas de terminal"
brew_install --formula jq ripgrep fd bat eza zoxide fzf tmux htop btop tree ncdu watch

# ════════════════════════════════════════════════════════════
#  5. Docker
# ════════════════════════════════════════════════════════════
if [ "$SKIP_DOCKER" -eq 1 ]; then
    step "Docker"; info "saltado (--no-docker)"
else
    step "Docker Desktop"
    if [ -d /Applications/Docker.app ]; then
        ok "Docker Desktop ya está"
    else
        brew_install --cask docker
        warn "abre Docker Desktop una vez a mano: pide aceptar la licencia antes de funcionar"
    fi
    brew_install --formula lazydocker
    info "si prefieres algo más liviano que Docker Desktop: brew install colima && colima start"
fi

# ════════════════════════════════════════════════════════════
#  6. Clientes de base de datos
# ════════════════════════════════════════════════════════════
# libpq y mysql-client son "keg-only": Homebrew no los enlaza en el PATH
# para no chocar con un servidor instalado. Hay que añadirlos a mano.
step "Clientes de base de datos"
brew_install --formula libpq mysql-client sqlite redis

BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
DB_PATHS=""
for k in libpq mysql-client; do
    [ -d "$BREW_PREFIX/opt/$k/bin" ] && DB_PATHS="$DB_PATHS:$BREW_PREFIX/opt/$k/bin"
done
if [ -n "$DB_PATHS" ]; then
    LOCALRC="$HOME/.zshrc.local"
    if [ -f "$LOCALRC" ] && grep -q 'opt/libpq/bin' "$LOCALRC" 2>/dev/null; then
        ok "psql y mysql ya están en el PATH (~/.zshrc.local)"
    elif dry; then
        run "añadir $DB_PATHS al PATH en ~/.zshrc.local"
    else
        {
            printf '\n# Clientes de base de datos de Homebrew (keg-only, no se enlazan solos).\n'
            printf 'export PATH="%s${PATH:+:$PATH}"\n' "${DB_PATHS#:}"
        } >> "$LOCALRC"
        ok "psql y mysql añadidos al PATH en ~/.zshrc.local"
    fi
fi

# ════════════════════════════════════════════════════════════
#  7. Notebooks a PDF
# ════════════════════════════════════════════════════════════
if [ "$SKIP_TEX" -eq 1 ]; then
    step "Exportar notebooks a PDF"; info "saltado (--no-tex)"
else
    step "Exportar notebooks a PDF (pandoc + BasicTeX)"
    brew_install --formula pandoc
    if [ -d /Library/TeX ]; then
        ok "BasicTeX ya está"
    else
        brew_install --cask basictex
    fi

    # BasicTeX es la versión mínima: le faltan los paquetes que nbconvert
    # usa en sus plantillas. Se instalan en modo usuario (~/Library/texmf)
    # para no tener que pedir sudo.
    export PATH="/Library/TeX/texbin:$PATH"
    if have tlmgr; then
        runq tlmgr init-usertree || true
        # shellcheck disable=SC2086
        if dry; then
            run tlmgr --usermode install $TEX_EXTRAS
        elif tlmgr --usermode install $TEX_EXTRAS >/dev/null 2>&1; then
            ok "paquetes de LaTeX para nbconvert instalados"
        else
            warn "revisa los paquetes de LaTeX: tlmgr --usermode install $TEX_EXTRAS"
        fi
    else
        warn "tlmgr no aparece; abre una terminal nueva y corre: tlmgr --usermode install $TEX_EXTRAS"
    fi
fi

# ════════════════════════════════════════════════════════════
#  8. Apps de escritorio
# ════════════════════════════════════════════════════════════
if [ "$SKIP_GUI" -eq 1 ]; then
    step "Apps de escritorio"; info "saltado (--no-gui)"
else
    step "Apps de escritorio"
    # Chromium: lo usa puppeteer-core y sirve para imprimir notebooks a
    # PDF sin pasar por LaTeX (que es como lo resolviste en algebra-lineal).
    brew_install --cask visual-studio-code chromium
    [ -d "/Applications/Chromium.app" ] || \
        info "si Chromium da problemas de firma, vale igual: brew install --cask google-chrome"
fi

# ════════════════════════════════════════════════════════════
#  9. Runtimes (comunes a los tres sistemas)
# ════════════════════════════════════════════════════════════
setup_node
setup_uv
setup_python_ds
setup_git_identity
summary
