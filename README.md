# Auto Dock

An Omarchy shell plugin: a dock of your favourite apps that hides itself against
the screen edge and slides out when the pointer touches that edge, on every
workspace (tiled or floating).

- Hidden by default; push the pointer to the edge to call it out.
- Hides again shortly after the pointer leaves.
- Stays away completely while a window is fullscreen.
- Left click: focus the app (or start it if it is not running).
- Middle click: open a new window.
- Right click: menu with *New window* / *Quit*.
- A dot marks apps that are running.
- Follows the Omarchy theme and the selected language (English and Spanish included).

## Install

```bash
omarchy plugin add https://github.com/ShadowPJ/omarchy-autodock.git --enable
```

Or for development, link a checkout:

```bash
ln -sfn "$PWD" ~/.config/omarchy/plugins/shadowpj.autodock
omarchy-shell shell rescanPlugins
omarchy plugin enable shadowpj.autodock
```

## Configure

Edit `config.json` in the plugin folder. It is watched, so changes apply on save
(or run `omarchy-shell shadowpj.autodock reload`).

```json
{
  "position": "bottom",
  "hideDelayMs": 400,
  "iconSize": 40,
  "apps": ["brave-browser", "org.gnome.Nautilus", "Alacritty"]
}
```

| Key           | Values                                  | Default  |
|---------------|-----------------------------------------|----------|
| `position`    | `bottom`, `top`, `left`, `right`        | `bottom` |
| `hideDelayMs` | 100–5000 ms after the pointer leaves    | `400`    |
| `iconSize`    | 24–96 px                                | `40`     |
| `apps`        | Desktop ids (file names in `/usr/share/applications` without `.desktop`) | see `config.json` |

Apps that are not installed are skipped until they are.

Omarchy's built-in dock only appears on floating workspaces and also sits at the
bottom; if you use both, consider `"position": "left"` here or moving the built-in
one with `omarchy dock position`.
