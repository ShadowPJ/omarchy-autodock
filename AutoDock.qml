import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "DockModel.js" as DockModel

// Auto Dock: a curated row of apps on every workspace that waits tucked
// against a screen edge and slides out when the pointer touches that edge.
// The apps, edge, icon size and hide delay come from config.json next to this
// file, which is watched, so edits apply on save.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var appLibrary: shell ? shell.appLibrary : null

  // Used when config.json is missing or lists nothing usable.
  readonly property var defaultApps: [
    "brave-browser", "org.gnome.Nautilus", "Alacritty", "com.microsoft.VSCode",
    "obsidian", "spotify", "Discord", "signal", "steam", "com.obsproject.Studio"
  ]

  property var config: DockModel.parseConfig("{}", defaultApps)
  readonly property string position: config.position
  readonly property bool vertical: DockModel.isVertical(position)

  readonly property string configPath: {
    var url = String(Qt.resolvedUrl("config.json"))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.config = DockModel.parseConfig(text(), root.defaultApps)
    onLoadFailed: root.config = DockModel.parseConfig("{}", root.defaultApps)
  }

  // Configured apps that are installed, each with its open windows. An app
  // that is not installed is skipped until it is.
  readonly property var items: {
    var revision = DesktopEntries.applications.values.length
    var toplevels = Hyprland.toplevels.values
    var out = []
    for (var i = 0; i < config.apps.length; i++) {
      var entry = DesktopEntries.byId(config.apps[i])
      if (!entry) continue
      var windows = []
      for (var t = 0; t < toplevels.length; t++) {
        var wayland = toplevels[t].wayland
        if (!wayland || !wayland.appId || wayland.parent) continue
        if (!root.claims(entry, wayland.appId)) continue
        var workspace = toplevels[t].workspace
        windows.push({ workspaceId: workspace ? workspace.id : -1, toplevel: wayland })
      }
      out.push({ id: entry.id, name: entry.name, icon: entry.icon, entry: entry, windows: windows })
    }
    return out
  }

  // Whether a window's app id belongs to this desktop entry.
  function claims(entry, appId) {
    var app = String(appId).toLowerCase()
    if (String(entry.id).toLowerCase() === app) return true
    if (entry.startupClass && String(entry.startupClass).toLowerCase() === app) return true
    var guess = DesktopEntries.heuristicLookup(appId)
    return !!guess && guess.id === entry.id
  }

  function iconFor(item) {
    var icon = item && item.icon ? item.icon : (item ? item.id : "")
    return root.appLibrary ? root.appLibrary.iconSource(icon) : Quickshell.iconPath(icon, true)
  }

  function launch(item) {
    if (!item) return
    if (root.appLibrary) root.appLibrary.launch(item.id, item.name)
    else item.entry.execute()
  }

  // A running app is brought forward; one with no windows is started.
  function activate(item) {
    if (!item) return
    if (item.windows.length === 0) {
      root.launch(item)
      return
    }
    var monitor = Hyprland.focusedMonitor
    var workspaceId = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    item.windows[DockModel.pickWindow(item.windows, workspaceId)].toplevel.activate()
  }

  function quit(item) {
    if (!item) return
    var windows = item.windows.slice()
    for (var i = 0; i < windows.length; i++) windows[i].toplevel.close()
  }

  // `omarchy-shell shadowpj.autodock reload` re-reads config.json.
  ShellIpc {
    target: "shadowpj.autodock"
    function reload(): void { configFile.reload() }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DockWindow {
        required property var modelData
        screen: modelData
        dock: root
      }
    }
  }
}
