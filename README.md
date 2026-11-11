# Auto Dock

An Omarchy shell plugin: a dock of your favourite apps that hides itself against
the screen edge and slides out when the pointer touches that edge, on every
workspace (tiled or floating).

- Hidden by default; push the pointer to the edge to call it out.
- Hides again shortly after the pointer leaves.
- Stays away completely while a window is fullscreen.
- Left click: focus the app (or start it if it is not running).
- Middle click: open a new window.
- Right click: menu with *New window*, *Quit*, *Remove from dock* and *Dock settings*.
- A settings panel to pick, search and reorder the dock's apps.
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

## Choose the apps

Click the **⚙** button at the end of the dock (or right-click any icon and pick
*Dock settings*) to open the settings panel:

- Left: the apps in the dock, in order. ▲ ▼ reorder, ✕ removes.
- Right: every installed app. Type to search, click (or press Enter for the
  first result) to add it. Escape or a click outside closes the panel.

Right-click an icon and pick *Remove from dock* to drop it straight away.

You can also open the panel from a keybinding or script:

```bash
omarchy-shell shadowpj.autodock settings
```

## Configure by hand

Your choices are saved to `~/.config/omarchy/autodock.json`, so they survive
plugin updates. Any key there wins over the plugin's bundled `config.json`,
which only holds the defaults. Both files are watched and apply on save
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

Apps that are not installed are skipped until they are. Delete
`~/.config/omarchy/autodock.json` to go back to the defaults.

Omarchy's built-in dock only appears on floating workspaces and also sits at the
bottom; if you use both, consider `"position": "left"` here or moving the built-in
one with `omarchy dock position`.
