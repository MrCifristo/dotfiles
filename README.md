# dotfiles — rice NERV

Terminal con estética *Neon Genesis Evangelion* / *Akira*: kitty + zsh + Starship
+ fastfetch con pantalla de arranque propia. Funciona igual en Fedora y en macOS.

```
kitty/      kitty.conf, paleta (nerv.conf), sesión de arranque y ajustes por SO
starship/   prompt de dos líneas, a juego con la paleta
nerv/       fastfetch.jsonc, logo (imagen + ASCII de respaldo) y frases rotativas
bin/        nerv-boot: la pantalla de arranque que dispara kitty en cada ventana nueva
zsh/        .zshrc limpio (Oh My Zsh + plugins + aliases); lo local va en ~/.zshrc.local
packages/   Brewfile (macOS) y lista dnf (Fedora)
install.sh  instala paquetes, fuente, Oh My Zsh y enlaza todo (idempotente)
```

## Instalar en un Mac nuevo

```sh
xcode-select --install                      # git y compiladores
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install gh && gh auth login
gh repo clone MrCifristo/dotfiles ~/.dotfiles
~/.dotfiles/install.sh
```

Después abre kitty desde Launchpad. La primera ventana ya sale con el fetch.

## Instalar en Fedora

```sh
sudo dnf install -y git gh && gh auth login
gh repo clone MrCifristo/dotfiles ~/.dotfiles
~/.dotfiles/install.sh
```

## Entorno de desarrollo

Aparte del rice, hay un segundo instalador para dejar la máquina lista para
programar: compiladores, Node por nvm, pnpm, Docker, clientes de base de datos
y un entorno de Python para los notebooks.

```sh
~/.dotfiles/dev-setup.sh              # detecta el sistema y llama al que toca
~/.dotfiles/dev-setup.sh --dry-run    # enseña qué haría, sin tocar nada
```

O directamente el de cada sistema: `dev/macos.sh`, `dev/fedora.sh`, `dev/arch.sh`.

| Opción       | Qué se salta                                      |
|--------------|---------------------------------------------------|
| `--no-tex`   | pandoc y LaTeX (exportar notebooks a PDF, ~1 GB)  |
| `--no-docker`| Docker y lazydocker                               |
| `--no-ds`    | el entorno de Python en `~/.venvs/ds`             |
| `--no-gui`   | VS Code y Chromium                                |
| `--minimal`  | las cuatro anteriores                             |
| `--dry-run`  | no instala nada, solo enseña la lista             |

Qué instala, en corto:

- **Compiladores y librerías nativas.** cairo, pango, jpeg, giflib y librsvg
  para `node-canvas` (lo arrastra `chartjs-node-canvas`, los reportes de
  ManoCard); libvips para `sharp`. Sin esto `pnpm install` falla al compilar.
- **Node por nvm**, no por el gestor del sistema, porque FastKitchen pide `>=24`
  y ManoCard `>=22`. pnpm entra por corepack, que respeta el `packageManager`
  de cada `package.json`.
- **Docker** con compose y buildx, más lazygit y lazydocker.
- **Clientes** de Postgres, MySQL/MariaDB, Redis y SQLite. Los servidores
  siguen en Docker.
- **Python:** `uv` y un entorno en `~/.venvs/ds` con numpy, pandas, polars,
  duckdb, scikit-learn, matplotlib, seaborn, nltk y jupyter. Queda registrado
  como kernel «Python (ds)», así que aparece solo en VS Code y en Jupyter.
  El alias `ds` lo activa. La lista se edita en `dev/python-ds.txt`.
- **Exportar notebooks a PDF:** pandoc y lo justo de LaTeX, incluidos los
  paquetes que nbconvert necesita y las distribuciones mínimas no traen.

La versión de Node por defecto solo se cambia si no había ninguna, para no
romper proyectos en una máquina que ya usabas.

## Personalizar

| Quiero cambiar…            | Toco…                                   |
|----------------------------|-----------------------------------------|
| la imagen del fetch        | `nerv/logo.jpg` (vale png/jpg/webp/gif) |
| las frases                 | `nerv/phrases.txt`                      |
| qué datos muestra el fetch | `nerv/fastfetch.jsonc`                  |
| la paleta                  | `kitty/nerv.conf` y los `#hex` de `starship/starship.toml` |
| atajos según SO            | `kitty/linux.conf` o `kitty/macos.conf` |
| cosas solo de una máquina  | `~/.zshrc.local` (no se versiona)       |

Todo está enlazado por symlink, así que editar `~/.config/kitty/kitty.conf`
es editar el repo: `cd ~/.dotfiles && git commit -am "..." && git push`.

Si en el Mac la imagen sale achatada o estirada, ajusta la proporción de celda
en `~/.zshrc.local`:

```sh
export NERV_CELL_RATIO=220   # por defecto 232; sube/baja de 5 en 5
```

## Atajos

| Acción                       | Linux          | macOS  |
|------------------------------|----------------|--------|
| ventana nueva (con fetch)    | Ctrl+Shift+N   | Cmd+N  |
| pestaña nueva (sin fetch)    | Ctrl+Shift+T   | Cmd+T  |
| split (sin fetch)            | Ctrl+Shift+Enter | Cmd+Enter |
| opacidad en caliente         | Ctrl+Shift+A, luego M / L | igual |
| fetch a mano                 | `nerv`         | `nerv` |
