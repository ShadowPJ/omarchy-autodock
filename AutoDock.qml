import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "DockModel.js" as DockModel

// Auto Dock: a curated row of apps on every workspace that waits tucked
// against a screen edge and slides out when the pointer touches that edge.
//
// Settings come from two files, both watched so edits apply on save:
//   - config.json next to this file: the plugin's defaults, tracked in git.
//   - ~/.config/omarchy/autodock.json: the user's choices, written by the
//     settings panel; any key it holds wins over the default.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var appLibrary: shell ? shell.appLibrary : null

  property string defaultsText: ""
  property string userText: ""
  readonly property var config: DockModel.effectiveConfig(defaultsText, userText)
  readonly property string position: config.position
  readonly property bool vertical: DockModel.isVertical(position)

  function localPath(url) {
    var value = String(url)
    return value.indexOf("file://") === 0 ? decodeURIComponent(value.slice(7)) : value
  }

  readonly property string userConfigPath: {
    var base = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    return base + "/omarchy/autodock.json"
  }

  FileView {
    id: defaultsFile
    path: root.localPath(Qt.resolvedUrl("config.json"))
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.defaultsText = text()
    onLoadFailed: root.defaultsText = ""
  }

  FileView {
    id: userFile
    path: root.userConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.userText = text()
    onLoadFailed: root.userText = ""
  }

  // Saves a new app list to the user's file. The dock follows at once rather
  // than waiting for the file watcher.
  function saveApps(apps) {
    var text = DockModel.withApps(root.userText, root.config, apps)
    root.userText = text
    userFile.setText(text)
  }

  function addApp(id) {
    if (!id || root.config.apps.indexOf(id) >= 0) return
    root.saveApps(root.config.apps.concat([id]))
  }

  function removeApp(id) {
    root.saveApps(root.config.apps.filter(function(other) { return other !== id }))
  }

  function moveApp(index, delta) {
    root.saveApps(DockModel.moved(root.config.apps, index, delta))
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

  function iconSource(icon) {
    return root.appLibrary ? root.appLibrary.iconSource(icon) : Quickshell.iconPath(String(icon || "application-x-executable"), true)
  }

  function iconFor(item) {
    return root.iconSource(item && item.icon ? item.icon : (item ? item.id : ""))
  }

  // Every app the launcher would show, filtered by a search query.
  function allApps(query) {
    if (root.appLibrary) return root.appLibrary.sortedEntries(query)
    var needle = String(query || "").toLowerCase()
    return DesktopEntries.applications.values.filter(function(entry) {
      return !entry.noDisplay && (!needle || String(entry.name).toLowerCase().indexOf(needle) >= 0)
    }).sort(function(a, b) { return String(a.name).localeCompare(String(b.name)) })
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

  function openSettings() { settings.shown = true }
  function toggleSettings() { settings.shown = !settings.shown }

  //   omarchy-shell shadowpj.autodock settings   opens the settings panel
  //   omarchy-shell shadowpj.autodock reload     re-reads both config files
  ShellIpc {
    target: "shadowpj.autodock"
    function settings(): void { root.toggleSettings() }
    function reload(): void {
      defaultsFile.reload()
      userFile.reload()
    }
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

  Settings {
    id: settings
    dock: root
  }
}
