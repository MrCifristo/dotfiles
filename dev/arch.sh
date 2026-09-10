#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  arch.sh — entorno de desarrollo en Arch Linux
#
#  Uso:  ~/.dotfiles/dev/arch.sh [--no-tex] [--no-docker]
#                                [--no-ds]  [--no-gui] [--minimal]
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

have pacman || die "esto es para Arch (no encuentro pacman)"
[ "$(id -u)" -eq 0 ] && die "no lo corras como root: makepkg se niega y sudo se pide cuando toca"

printf '\n%s  NERV — entorno de desarrollo · Arch Linux%s\n' "$_P" "$_RS"

dry || sudo -v || die "necesito sudo"

# ── actualización completa antes de instalar ────────────────
# Arch no soporta actualizaciones parciales: instalar sobre una base
# desactualizada rompe enlaces de librerías. Por eso va -Syu y no -Sy.
step "Actualizando el sistema (pacman -Syu)"
info "Arch no admite instalaciones parciales, así que esto no es opcional"
runq sudo pacman -Syu --noconfirm \
    && ok "sistema al día" \
    || warn "la actualización falló; revísala a mano antes de seguir"

# ── instala solo lo que falta, tolerando nombres que cambiaron ──
pac_install() {
    local want=("$@") todo=()
    for p in "${want[@]}"; do
        # -T además de -Qq: así se detecta cuando otro paquete ya provee
        # lo que se pide, sin reinstalar por encima.
        pacman -Qq "$p" >/dev/null 2>&1 && continue
        pacman -T "$p" >/dev/null 2>&1 && continue
        if pacman -Si "$p" >/dev/null 2>&1; then
            todo+=("$p")
        else
            warn "no existe el paquete «$p» en los repos oficiales"
        fi
    done
    if [ ${#todo[@]} -eq 0 ]; then ok "nada que instalar"; return 0; fi
    if dry; then run sudo pacman -S --needed "${todo[@]}"; return 0; fi
    info "instalando: ${todo[*]}"
    sudo pacman -S --needed --noconfirm "${todo[@]}" >/dev/null 2>&1 \
        && ok "listo (${#todo[@]} paquetes)" \
        || warn "pacman falló con: ${todo[*]}"
}

# Instala el primero de la lista que exista de verdad. Sirve para los
# paquetes que Arch renombra (redis pasó a llamarse valkey).
pac_install_first() {
    local label="$1"; shift
    for p in "$@"; do
        if pacman -Qq "$p" >/dev/null 2>&1; then ok "$label: $p ya está"; return 0; fi
        if pacman -Si "$p" >/dev/null 2>&1; then pac_install "$p"; return 0; fi
    done
    warn "$label: ninguno de estos existe ya ($*)"
}

# ════════════════════════════════════════════════════════════
#  1. Compiladores
# ════════════════════════════════════════════════════════════
step "Compiladores y herramientas de construcción"
pac_install base-devel git cmake pkgconf curl wget unzip

# ════════════════════════════════════════════════════════════
#  2. Ayudante de AUR
# ════════════════════════════════════════════════════════════
# lazydocker y VS Code con marketplace de Microsoft solo están en AUR.
AUR=""
step "Ayudante de AUR"
for h in yay paru; do have "$h" && { AUR="$h"; break; }; done
if [ -n "$AUR" ]; then
    ok "$AUR ya está"
elif [ "$SKIP_GUI" -eq 1 ] && [ "$SKIP_DOCKER" -eq 1 ]; then
    info "no hace falta con --no-gui y --no-docker"
else
    info "compilando yay-bin desde AUR"
    if dry; then run git clone https://aur.archlinux.org/yay-bin.git "&&" makepkg -si; AUR="yay"; fi
    dry || tmp="$(mktemp -d)"
    if dry; then
        :
    elif git clone -q --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" 2>/dev/null \
       && (cd "$tmp/yay-bin" && makepkg -si --noconfirm >/dev/null 2>&1); then
        AUR="yay"; ok "yay instalado"
    else
        warn "no pude instalar yay; lo de AUR habrá que ponerlo a mano"
    fi
    dry || rm -rf "$tmp"
fi

aur_install() {
    [ -z "$AUR" ] && { warn "sin ayudante de AUR: instala a mano $*"; return 1; }
    local todo=()
    for p in "$@"; do pacman -Qq "$p" >/dev/null 2>&1 || todo+=("$p"); done
    [ ${#todo[@]} -eq 0 ] && { ok "nada que instalar desde AUR"; return 0; }
    if dry; then run "$AUR" -S --needed "${todo[@]}"; return 0; fi
    info "AUR: ${todo[*]}"
    "$AUR" -S --needed --noconfirm "${todo[@]}" >/dev/null 2>&1 \
        && ok "listo" || warn "AUR falló con: ${todo[*]}"
}

# ════════════════════════════════════════════════════════════
#  3. Librerías nativas que piden tus dependencias de npm
# ════════════════════════════════════════════════════════════
# cairo/pango/jpeg/gif/rsvg → node-canvas (chartjs-node-canvas, los
#                             reportes de ManoCard)
# libvips                   → sharp
step "Librerías nativas (node-canvas, sharp)"
pac_install cairo pango libjpeg-turbo giflib librsvg libvips

# ════════════════════════════════════════════════════════════
#  4. Git, GitHub y terminal
# ════════════════════════════════════════════════════════════
step "Git y GitHub CLI"
pac_install git-lfs github-cli lazygit

step "Herramientas de terminal"
pac_install jq ripgrep fd bat eza zoxide fzf tmux htop btop tree ncdu

# ════════════════════════════════════════════════════════════
#  5. Docker
# ════════════════════════════════════════════════════════════
if [ "$SKIP_DOCKER" -eq 1 ]; then
    step "Docker"; info "saltado (--no-docker)"
else
    step "Docker"
    pac_install docker docker-compose docker-buildx
    aur_install lazydocker

    # Arch no habilita servicios al instalar: hay que hacerlo a mano.
    if systemctl is-enabled docker >/dev/null 2>&1; then
        ok "servicio docker habilitado"
    else
        runq sudo systemctl enable --now docker.service \
            && ok "servicio docker habilitado y arrancado" \
            || warn "no pude arrancar el servicio docker"
    fi

    if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
        ok "ya estás en el grupo docker"
    else
        run sudo usermod -aG docker "$USER" \
            && { ok "te añadí al grupo docker"; NEEDS_RELOGIN=1; } \
            || warn "no pude añadirte al grupo docker"
    fi
fi

# ════════════════════════════════════════════════════════════
#  6. Clientes de base de datos
# ════════════════════════════════════════════════════════════
# Los servidores corren en Docker; aquí solo van los clientes.
step "Clientes de base de datos"
# En Arch el binario psql viene dentro del paquete `postgresql`, junto con
# el servidor. No pasa nada: Arch no habilita servicios al instalar, así
# que el servidor queda ahí parado y tú sigues usando el de Docker.
pac_install postgresql mariadb-clients sqlite
pac_install_first "cliente de Redis" valkey redis
have valkey-cli && info "el cliente de Redis aquí se llama valkey-cli"

# ════════════════════════════════════════════════════════════
#  7. Notebooks a PDF
# ════════════════════════════════════════════════════════════
if [ "$SKIP_TEX" -eq 1 ]; then
    step "Exportar notebooks a PDF"; info "saltado (--no-tex)"
else
    step "Exportar notebooks a PDF (pandoc + LaTeX)"
    info "texlive-latexextra son ~1 GB; usa --no-tex si no lo quieres"
    pac_install_first "pandoc" pandoc-cli pandoc
    pac_install texlive-xetex texlive-latexextra texlive-latexrecommended \
                texlive-fontsrecommended
    info "también sirve la ruta sin LaTeX: nbconvert --to html y luego imprimir con Chromium"
fi

# ════════════════════════════════════════════════════════════
#  8. Apps de escritorio
# ════════════════════════════════════════════════════════════
if [ "$SKIP_GUI" -eq 1 ]; then
    step "Apps de escritorio"; info "saltado (--no-gui)"
else
    step "Apps de escritorio"
    # chromium: lo usa puppeteer-core y sirve para imprimir notebooks
    # a PDF sin pasar por LaTeX.
    pac_install chromium
    if have code; then
        ok "VS Code ya está"
    else
        # El paquete oficial `code` es la compilación libre, sin el
        # marketplace de Microsoft. El de AUR es el binario de siempre.
        aur_install visual-studio-code-bin || pac_install code
    fi
fi

# ════════════════════════════════════════════════════════════
#  9. Runtimes (comunes a los tres sistemas)
# ════════════════════════════════════════════════════════════
# Node va por nvm y no por pacman: en Arch el paquete `nodejs` salta a
# la versión mayor nueva en cuanto sale, y tus proyectos piden versiones
# concretas.
setup_node
setup_uv
setup_python_ds
setup_git_identity
summary
