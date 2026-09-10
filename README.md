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
