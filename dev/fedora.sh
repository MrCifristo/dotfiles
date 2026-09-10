#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  fedora.sh — entorno de desarrollo en Fedora
#
#  Uso:  ~/.dotfiles/dev/fedora.sh [--no-tex] [--no-docker]
#                                  [--no-ds]  [--no-gui] [--minimal]
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

have dnf || die "esto es para Fedora (no encuentro dnf)"
[ "$(id -u)" -eq 0 ] && die "no lo corras como root: pide sudo cuando le toca"

printf '\n%s  NERV — entorno de desarrollo · Fedora %s%s\n' "$_P" \
    "$(rpm -E %fedora 2>/dev/null || echo '?')" "$_RS"

dry || sudo -v || die "necesito sudo"

# ── instala solo lo que falta, y avisa de lo que no existe ──
# Un nombre inventado no debe tumbar el script entero: dnf aborta la
# transacción completa si uno de los paquetes no existe.
dnf_install() {
    local want=("$@") todo=()
    for p in "${want[@]}"; do
        # --whatprovides y no `rpm -q` a secas: en Fedora 44 el binario
        # wget lo trae el paquete wget2-wget, y hay más casos así.
        rpm -q --whatprovides "$p" >/dev/null 2>&1 && continue
        if dnf list --available --quiet "$p" >/dev/null 2>&1; then
            todo+=("$p")
        else
            warn "no existe el paquete «$p» en los repos; sáltatelo o busca el nombre nuevo"
        fi
    done
    if [ ${#todo[@]} -eq 0 ]; then ok "nada que instalar"; return 0; fi
    if dry; then run sudo dnf install -y "${todo[@]}"; return 0; fi
    info "instalando: ${todo[*]}"
    sudo dnf install -y --quiet "${todo[@]}" >/dev/null \
        && ok "listo (${#todo[@]} paquetes)" \
        || warn "dnf falló con: ${todo[*]}"
}

# ════════════════════════════════════════════════════════════
#  1. Compiladores y cabeceras
# ════════════════════════════════════════════════════════════
# node-gyp los necesita para compilar bcrypt, argon2 y sharp cuando no
# hay binario precompilado para tu arquitectura.
step "Compiladores y herramientas de construcción"
if dry; then
    run sudo dnf group install -y development-tools c-development
elif sudo dnf group install -y --quiet development-tools c-development >/dev/null 2>&1; then
    ok "grupos development-tools y c-development"
else
    warn "no pude instalar los grupos de desarrollo"
fi

dnf_install gcc-c++ make cmake pkgconf-pkg-config \
            openssl-devel libffi-devel zlib-ng-compat-devel \
            python3-devel curl wget unzip tar

# ════════════════════════════════════════════════════════════
#  2. Librerías nativas que piden tus dependencias de npm
# ════════════════════════════════════════════════════════════
# cairo/pango/jpeg/gif/rsvg  → node-canvas, que arrastra chartjs-node-canvas
#                              (los reportes de ManoCard)
# vips                       → sharp, el redimensionado de imágenes
step "Librerías nativas (node-canvas, sharp)"
dnf_install cairo-devel pango-devel libjpeg-turbo-devel giflib-devel \
            librsvg2-devel vips-devel

# ════════════════════════════════════════════════════════════
#  3. Git y GitHub
# ════════════════════════════════════════════════════════════
step "Git y GitHub CLI"
dnf_install git git-lfs gh

# lazygit y lazydocker viven en COPR, no en los repos oficiales.
step "lazygit y lazydocker"
for pair in "lazygit:atim/lazygit" "lazydocker:atim/lazydocker"; do
    bin="${pair%%:*}"; repo="${pair#*:}"
    if have "$bin"; then ok "$bin ya está"; continue; fi
    if [ "$bin" = "lazydocker" ] && [ "$SKIP_DOCKER" -eq 1 ]; then
        info "lazydocker: saltado (--no-docker)"; continue
    fi
    runq sudo dnf copr enable -y "$repo" || warn "no pude habilitar el COPR $repo"
    dnf_install "$bin"
done

# ════════════════════════════════════════════════════════════
#  4. Herramientas de terminal
# ════════════════════════════════════════════════════════════
step "Herramientas de terminal"
dnf_install jq ripgrep fd-find bat eza zoxide fzf tmux htop btop tree \
            ncdu bind-utils

# ════════════════════════════════════════════════════════════
#  5. Docker
# ════════════════════════════════════════════════════════════
# Se usa docker-ce del repo oficial y no el `moby-engine` de Fedora:
# es el que trae buildx y compose v2 al día, que es lo que usan tus
# docker-compose.yml.
if [ "$SKIP_DOCKER" -eq 1 ]; then
    step "Docker"; info "saltado (--no-docker)"
else
    step "Docker"
    if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
        runq sudo dnf config-manager addrepo --overwrite \
            --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo \
            || warn "no pude añadir el repo de Docker"
    fi
    dnf_install docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin

    if systemctl is-enabled docker >/dev/null 2>&1; then
        ok "servicio docker habilitado"
    else
        runq sudo systemctl enable --now docker \
            && ok "servicio docker habilitado y arrancado" \
            || warn "no pude arrancar el servicio docker"
    fi

    # Sin esto hay que anteponer sudo a cada comando de docker.
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
# Los servidores corren en Docker; en el sistema solo van los clientes
# para poder conectarse desde la terminal.
step "Clientes de base de datos"
dnf_install postgresql mariadb valkey sqlite
have valkey-cli && info "el cliente de Redis aquí se llama valkey-cli (Fedora cambió redis por valkey)"

# ════════════════════════════════════════════════════════════
#  7. Notebooks a PDF
# ════════════════════════════════════════════════════════════
if [ "$SKIP_TEX" -eq 1 ]; then
    step "Exportar notebooks a PDF"; info "saltado (--no-tex)"
else
    step "Exportar notebooks a PDF (pandoc + LaTeX)"
    info "texlive-collection-latexextra son ~1 GB; usa --no-tex si no lo quieres"
    # En Fedora el binario pandoc viene en el paquete pandoc-cli.
    dnf_install pandoc-cli texlive-xetex texlive-collection-latexextra \
                texlive-collection-fontsrecommended
    info "también sirve la ruta sin LaTeX: nbconvert --to html y luego imprimir con Chromium"
fi

# ════════════════════════════════════════════════════════════
#  8. Apps de escritorio
# ════════════════════════════════════════════════════════════
if [ "$SKIP_GUI" -eq 1 ]; then
    step "Apps de escritorio"; info "saltado (--no-gui)"
else
    step "Apps de escritorio"
    # chromium: lo usa puppeteer-core (ManoCard) y sirve para imprimir
    # notebooks a PDF sin LaTeX.
    dnf_install chromium

    if have code; then
        ok "VS Code ya está"
    else
        runq sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        dry && run "escribir /etc/yum.repos.d/vscode.repo"
        dry || printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' \
            | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
        dry || dnf_install code
    fi
fi

# ════════════════════════════════════════════════════════════
#  9. Runtimes (comunes a los tres sistemas)
# ════════════════════════════════════════════════════════════
setup_node
setup_uv
setup_python_ds
setup_git_identity
summary
