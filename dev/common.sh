#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  common.sh — lo que comparten macos.sh, fedora.sh y arch.sh
#
#  No se ejecuta solo; los otros scripts le hacen `source`.
#  Aquí vive todo lo que NO depende del gestor de paquetes:
#  Node vía nvm, pnpm, uv, el venv de ciencia de datos y el
#  resumen final.
# ════════════════════════════════════════════════════════════

# ── salida con la paleta NERV ───────────────────────────────
_P=$'\033[38;2;124;58;237m'; _G=$'\033[38;2;163;230;53m'
_O=$'\033[38;2;249;115;22m'; _D=$'\033[38;2;107;100;128m'
_C=$'\033[38;2;34;211;238m'; _RS=$'\033[0m'

step() { printf '\n%s▶ %s%s\n' "$_P" "$1" "$_RS"; }
ok()   { printf '  %s✓%s %s\n' "$_G" "$_RS" "$1"; }
warn() { printf '  %s!%s %s\n' "$_O" "$_RS" "$1"; WARNINGS+=("$1"); }
info() { printf '  %s·%s %s\n' "$_D" "$_RS" "$1"; }
die()  { printf '\n%s✗ %s%s\n\n' "$_O" "$1" "$_RS" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

WARNINGS=()
NEEDS_RELOGIN=0
DRY_RUN=0

# ── run: la única puerta por la que pasa lo que modifica la máquina ──
# Con --dry-run imprime el comando en vez de ejecutarlo, así se puede
# revisar qué va a tocar antes de dejarlo suelto.
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  %s→%s %s\n' "$_C" "$_RS" "$*"
        return 0
    fi
    "$@"
}
dry() { [ "$DRY_RUN" -eq 1 ]; }

# Igual que run, pero silencia la salida del comando de verdad. Hace falta
# porque `run algo >/dev/null` también se tragaría el eco del dry-run y el
# comando no aparecería en el listado.
runq() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  %s→%s %s\n' "$_C" "$_RS" "$*"
        return 0
    fi
    "$@" >/dev/null 2>&1
}

# ── banderas ────────────────────────────────────────────────
SKIP_TEX=0; SKIP_DOCKER=0; SKIP_DS=0; SKIP_GUI=0
parse_flags() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-tex)    SKIP_TEX=1 ;;
            --no-docker) SKIP_DOCKER=1 ;;
            --no-ds)     SKIP_DS=1 ;;
            --no-gui)    SKIP_GUI=1 ;;
            --minimal)   SKIP_TEX=1; SKIP_DOCKER=1; SKIP_DS=1; SKIP_GUI=1 ;;
            --dry-run)   DRY_RUN=1 ;;
            -h|--help)
                cat <<HELP
Uso: $(basename "$0") [opciones]

  --no-tex      no instala pandoc ni LaTeX (exportar notebooks a PDF)
  --no-docker   no instala Docker ni lazydocker
  --no-ds       no crea el venv de ciencia de datos en ~/.venvs/ds
  --no-gui      no instala apps de escritorio (VS Code, Chromium…)
  --minimal     las cuatro anteriores de golpe
  --dry-run     enseña lo que haría, sin instalar ni cambiar nada
  -h, --help    esto

Se puede correr las veces que haga falta: lo que ya está, se salta.
HELP
                exit 0 ;;
            *) die "opción desconocida: $1  (--help para ver las que hay)" ;;
        esac
        shift
    done
}

# ── Node: nvm + LTS + pnpm ──────────────────────────────────
# Se usa nvm y no el paquete del sistema porque tus proyectos piden
# versiones distintas (FastKitchen >=24, ManoCard >=22) y conviene
# poder saltar entre ellas sin pelearse con el gestor de paquetes.
NVM_VERSION="v0.40.3"

setup_node() {
    step "Node (nvm + LTS)"
    export NVM_DIR="$HOME/.nvm"

    if [ -s "$NVM_DIR/nvm.sh" ]; then
        ok "nvm ya está"
    elif dry; then
        run curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" "| bash"
        run nvm install --lts
        run corepack enable
        return 0
    else
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" \
            | PROFILE=/dev/null bash >/dev/null 2>&1 \
            || die "no pude instalar nvm"
        ok "nvm $NVM_VERSION instalado"
    fi

    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"

    # `nvm ls | grep lts/*` no sirve: nvm imprime el alias siempre, esté
    # instalado o no. `nvm version lts/*` devuelve N/A si falta de verdad.
    local lts_have; lts_have="$(nvm version 'lts/*' 2>/dev/null)"
    if [ "$lts_have" != "N/A" ] && [ -n "$lts_have" ]; then
        ok "Node LTS ya está ($lts_have)"
    elif dry; then
        run nvm install --lts
    else
        info "descargando la LTS…"
        nvm install --lts >/dev/null 2>&1 || die "no pude instalar Node LTS"
        lts_have="$(nvm version 'lts/*' 2>/dev/null)"
        ok "Node $lts_have instalado"
    fi

    # La versión por defecto solo se toca si no había ninguna: en una
    # máquina que ya usabas, cambiártela por debajo rompería proyectos.
    local cur_default; cur_default="$(nvm version default 2>/dev/null)"
    if [ "$cur_default" = "N/A" ] || [ -z "$cur_default" ]; then
        dry || nvm alias default 'lts/*' >/dev/null 2>&1
        ok "Node por defecto: LTS"
    elif [ "$cur_default" != "$lts_have" ] && [ "$lts_have" != "N/A" ]; then
        ok "Node por defecto: $cur_default (sin tocar)"
        info "la LTS nueva es $lts_have; para cambiar: nvm alias default 'lts/*'"
    else
        ok "Node por defecto: $cur_default"
    fi

    # ── pnpm ──
    # corepack lee el campo "packageManager" de cada package.json y baja
    # la versión exacta que pide el proyecto (los tuyos piden pnpm 10.33.1).
    if dry; then
        run corepack enable
        run corepack prepare pnpm@latest --activate
    elif have corepack; then
        corepack enable >/dev/null 2>&1 || true
        corepack prepare pnpm@latest --activate >/dev/null 2>&1 || true
    fi
    if dry; then
        :
    elif have pnpm; then
        ok "pnpm $(pnpm -v) (vía corepack)"
    else
        npm install -g pnpm >/dev/null 2>&1 \
            && ok "pnpm $(pnpm -v) (vía npm)" \
            || warn "no pude instalar pnpm; hazlo con: npm i -g pnpm"
    fi
}

# ── Python: uv ──────────────────────────────────────────────
# Fedora y Arch marcan su Python como "externally managed": pip install
# a secas falla a propósito. uv resuelve eso y además crea venvs en un
# segundo, así que es la herramienta por defecto aquí.
setup_uv() {
    step "uv (gestor de paquetes de Python)"
    if have uv; then
        ok "ya está ($(uv --version 2>/dev/null | awk '{print $2}'))"
        return
    fi
    if dry; then run curl -fsSL https://astral.sh/uv/install.sh "| sh"; return 0; fi
    curl -fsSL https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 \
        || { warn "no pude instalar uv"; return 1; }
    export PATH="$HOME/.local/bin:$PATH"
    have uv && ok "instalado en ~/.local/bin" || warn "uv no quedó en el PATH"
}

# ── venv de ciencia de datos ────────────────────────────────
DS_VENV="$HOME/.venvs/ds"

setup_python_ds() {
    [ "$SKIP_DS" -eq 1 ] && { info "venv de ciencia de datos: saltado (--no-ds)"; return; }

    step "Entorno de ciencia de datos (~/.venvs/ds)"
    local req="$DEV_DIR/python-ds.txt"
    [ -f "$req" ] || { warn "no encuentro $req"; return; }

    if dry; then
        run uv venv "$DS_VENV"
        run uv pip install -r "$req"
        run "$DS_VENV/bin/python" -m ipykernel install --user --name ds
        return 0
    fi
    have uv || { warn "sin uv no puedo crear el venv"; return; }

    if [ ! -d "$DS_VENV" ]; then
        uv venv "$DS_VENV" >/dev/null 2>&1 || { warn "no pude crear el venv"; return; }
        ok "venv creado"
    else
        ok "venv ya existía"
    fi

    info "instalando paquetes (numpy, pandas, polars, duckdb, jupyter…)"
    if VIRTUAL_ENV="$DS_VENV" uv pip install -q -r "$req" 2>/dev/null; then
        ok "paquetes al día"
    else
        warn "falló la instalación de algún paquete; reintenta con: VIRTUAL_ENV=$DS_VENV uv pip install -r $req"
        return
    fi

    # Registrar el kernel para que salga en Jupyter y en VS Code.
    if "$DS_VENV/bin/python" -m ipykernel install --user \
         --name ds --display-name "Python (ds)" >/dev/null 2>&1; then
        ok "kernel de Jupyter registrado como «Python (ds)»"
    else
        warn "no pude registrar el kernel de Jupyter"
    fi
}

# ── LaTeX para exportar notebooks a PDF ─────────────────────
# Los paquetes que nbconvert necesita y que las distribuciones mínimas
# de TeX no traen. Es la lista que ya tuviste que instalar a mano.
TEX_EXTRAS="adjustbox collectbox enumitem environ pdfcol rsfs soul tcolorbox titling trimspaces ucs"

# ── git: identidad ──────────────────────────────────────────
setup_git_identity() {
    step "Identidad de git"
    local n e
    n="$(git config --global user.name  || true)"
    e="$(git config --global user.email || true)"
    [ -n "$n" ] && ok "user.name  = $n"  || warn "falta: git config --global user.name \"Tu Nombre\""
    [ -n "$e" ] && ok "user.email = $e"  || warn "falta: git config --global user.email \"tu@correo\""
    if have gh && gh auth status >/dev/null 2>&1; then
        ok "gh autenticado como $(gh api user -q .login 2>/dev/null)"
    else
        warn "GitHub CLI sin sesión: corre  gh auth login"
    fi
}

# ── resumen ─────────────────────────────────────────────────
summary() {
    printf '\n%s▛▀▀ NERV DEV SETUP ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀%s\n' "$_P" "$_RS"

    have node && printf '  %-12s %s\n' "node"   "$(node -v 2>/dev/null)"
    have pnpm && printf '  %-12s %s\n' "pnpm"   "$(pnpm -v 2>/dev/null)"
    have python3 && printf '  %-12s %s\n' "python" "$(python3 -V 2>&1 | awk '{print $2}')"
    have uv   && printf '  %-12s %s\n' "uv"     "$(uv --version 2>/dev/null | awk '{print $2}')"
    have docker && printf '  %-12s %s\n' "docker" "$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ,)"
    [ -d "$DS_VENV" ] && printf '  %-12s %s\n' "venv ds" "$DS_VENV"

    if [ ${#WARNINGS[@]} -gt 0 ]; then
        printf '\n%s  Quedó pendiente:%s\n' "$_O" "$_RS"
        for w in "${WARNINGS[@]}"; do printf '    %s·%s %s\n' "$_D" "$_RS" "$w"; done
    fi

    if [ "$NEEDS_RELOGIN" -eq 1 ]; then
        printf '\n%s  Cierra sesión y vuelve a entrar%s para que tomen efecto los grupos nuevos.\n' "$_O" "$_RS"
    fi

    printf '\n  %sAtajos:%s\n' "$_C" "$_RS"
    printf '    %sds%s        source ~/.venvs/ds/bin/activate   (notebooks, pandas, polars)\n' "$_G" "$_RS"
    printf '    %snvm use%s   cambiar de versión de Node dentro de un proyecto\n' "$_G" "$_RS"
    printf '%s▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄%s\n\n' "$_P" "$_RS"
}
