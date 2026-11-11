import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// One screen's auto dock. The layer surface stays mapped; while the dock is
// tucked away only a thin strip along the screen edge takes input, so clicks
// fall through to the windows below everywhere else.
PanelWindow {
  id: window

  property var dock: null

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string position: dock ? dock.position : "bottom"
  readonly property bool vertical: dock ? dock.vertical : false
  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1

  // A fullscreen window on this screen's workspace keeps the dock out of the
  // way entirely, so games and videos are never interrupted by the edge.
  readonly property bool fullscreen: {
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (!toplevel.workspace || toplevel.workspace.id !== workspaceId) continue
      var ipc = toplevel.lastIpcObject
      if (ipc && ipc.fullscreen >= 2) return true
    }
    return false
  }

  // Space other surfaces (such as the bar) reserve on the dock's edge. The
  // window itself covers the whole edge so the trigger sits on the real screen
  // border, and the dock pops out just clear of that space. Hyprland lists it
  // as left, top, right, bottom.
  readonly property int reservedEdge: {
    var reserved = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
    var index = position === "left" ? 0 : position === "top" ? 1 : position === "right" ? 2 : 3
    return Math.max(0, Math.round(Number(reserved[index]) || 0))
  }

  property bool revealed: false
  property var menuItem: null
  property Item menuSlot: null
  readonly property bool menuOpen: menuItem !== null
  readonly property bool open: !fullscreen && (revealed || menuOpen)

  readonly property int gap: Style.spacing.lg
  readonly property int iconSize: Math.round((dock ? dock.config.iconSize : 40) * Style.fontScale)
  readonly property int iconInset: Style.spacing.md
  readonly property int slotSize: iconSize + iconInset * 2
  readonly property int padding: Style.spacing.sm
  // Room inward of the dock for the tooltip and the right-click menu.
  readonly property int popupRoom: Style.spacing.popupRowHeight * 3 + Style.spacing.sm * 4 + gap
  readonly property int popOrigin: position === "top" ? Item.Top
    : position === "left" ? Item.Left
    : position === "right" ? Item.Right
    : Item.Bottom

  color: "transparent"
  WlrLayershell.namespace: "shadowpj-autodock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Never reserves space: tiled windows keep the whole screen.
  exclusionMode: ExclusionMode.Ignore
  exclusiveZone: 0

  anchors {
    top: window.position !== "bottom"
    bottom: window.position !== "top"
    left: window.position !== "right"
    right: window.position !== "left"
  }

  readonly property int inset: reservedEdge + gap

  implicitWidth: window.vertical ? window.inset + body.width + window.popupRoom : 0
  implicitHeight: window.vertical ? 0 : window.inset + body.height + window.popupRoom

  mask: Region {
    item: window.open ? body : null
    Region { item: !window.fullscreen ? edgeTrigger : null }
    Region { item: menu.visible ? menu : null }
  }

  onFullscreenChanged: if (fullscreen) close()
  onWorkspaceIdChanged: close()

  function close() {
    window.menuItem = null
    window.menuSlot = null
    window.revealed = false
  }

  function closeMenu() {
    window.menuItem = null
    window.menuSlot = null
    hideTimer.restart()
  }

  Timer {
    id: hideTimer
    interval: window.dock ? window.dock.config.hideDelayMs : 400
    onTriggered: {
      if (!bodyHover.hovered && !edgeHover.hovered && !window.menuOpen) window.revealed = false
    }
  }

  HyprlandFocusGrab {
    active: window.menuOpen
    windows: [window]
    onCleared: window.closeMenu()
  }

  // The strip along the screen edge that calls the dock out. It spans the
  // whole edge so the dock is easy to find without aiming.
  Item {
    id: edgeTrigger
    readonly property int depth: Math.max(2, Style.spacing.xxs)

    x: window.position === "right" ? window.width - depth : 0
    y: window.position === "bottom" ? window.height - depth : 0
    width: window.vertical ? depth : window.width
    height: window.vertical ? window.height : depth

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered && !window.fullscreen) window.revealed = true
        else hideTimer.restart()
      }
    }
  }

  Rectangle {
    id: body

    readonly property int count: appRepeater.count
    width: window.vertical ? window.slotSize + window.padding * 2 : Math.max(1, count) * window.slotSize + window.padding * 2
    height: window.vertical ? Math.max(1, count) * window.slotSize + window.padding * 2 : window.slotSize + window.padding * 2

    radius: Math.max(Style.cornerRadius, Style.spacing.lg)
    color: Commons.Color.bar.background
    border.width: Style.normalBorderWidth
    border.color: Style.normalBorderColor

    // How far past its edge the dock sits while tucked away. Leaving is
    // quicker than arriving.
    property real tuck: window.open ? 0 : (window.vertical ? width : height) + window.inset + 2
    Behavior on tuck {
      id: tuckMotion
      NumberAnimation {
        duration: Style.duration(tuckMotion.targetValue > 0 ? 120 : 180)
        easing.type: Easing.OutCubic
      }
    }
    opacity: window.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic } }

    x: window.position === "left" ? window.inset - tuck
      : window.position === "right" ? window.width - width - window.inset + tuck
      : Math.round((window.width - width) / 2)
    y: window.position === "top" ? window.inset - tuck
      : window.position === "bottom" ? window.height - height - window.inset + tuck
      : Math.round((window.height - height) / 2)

    HoverHandler {
      id: bodyHover
      onHoveredChanged: if (!hovered) hideTimer.restart()
    }

    Grid {
      id: slots
      anchors.centerIn: parent
      columns: window.vertical ? 1 : Math.max(1, appRepeater.count)

      Repeater {
        id: appRepeater
        model: window.dock ? window.dock.items : []
        delegate: AppSlot {}
      }
    }
  }

  component AppSlot: Item {
    id: slot

    required property var modelData
    required property int index
    readonly property bool running: modelData.windows.length > 0
    readonly property bool hovered: mouse.containsMouse

    width: window.slotSize
    height: window.slotSize

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      onClicked: function(event) {
        if (event.button === Qt.RightButton) {
          window.menuItem = slot.modelData
          window.menuSlot = slot
          return
        }
        window.closeMenu()
        if (event.button === Qt.MiddleButton) window.dock.launch(slot.modelData)
        else window.dock.activate(slot.modelData)
      }
    }

    Image {
      x: window.iconInset
      y: window.iconInset
      width: window.iconSize
      height: window.iconSize
      sourceSize: Qt.size(window.iconSize * 2, window.iconSize * 2)
      source: window.dock ? window.dock.iconFor(slot.modelData) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      scale: slot.hovered ? 1.15 : 1
      transformOrigin: window.popOrigin
      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    }

    // A dot on the edge side marks a running app.
    Rectangle {
      visible: slot.running
      width: Math.max(4, Math.round(window.iconSize * 0.12))
      height: width
      radius: width / 2
      color: Commons.Color.accent
      x: window.position === "left" ? 1
        : window.position === "right" ? slot.width - width - 1
        : Math.round((slot.width - width) / 2)
      y: window.position === "top" ? 1
        : window.position === "bottom" ? slot.height - height - 1
        : Math.round((slot.height - height) / 2)
    }
  }

  // Places a popup inward of the dock, centered on a slot.
  function popupX(slot, popup) {
    if (!slot) return 0
    var center = slot.mapToItem(window.contentItem, slot.width / 2, 0).x
    if (window.position === "left") return body.x + body.width + Style.spacing.sm
    if (window.position === "right") return body.x - Style.spacing.sm - popup.width
    return Math.max(Style.spacing.sm, Math.min(window.width - popup.width - Style.spacing.sm, center - popup.width / 2))
  }

  function popupY(slot, popup) {
    if (!slot) return 0
    var center = slot.mapToItem(window.contentItem, 0, slot.height / 2).y
    if (window.position === "top") return body.y + body.height + Style.spacing.sm
    if (window.position === "bottom") return body.y - Style.spacing.sm - popup.height
    return Math.max(Style.spacing.sm, Math.min(window.height - popup.height - Style.spacing.sm, center - popup.height / 2))
  }

  // The app's name over the hovered icon.
  Rectangle {
    id: tooltip
    readonly property Item slot: {
      for (var i = 0; i < appRepeater.count; i++) {
        var item = appRepeater.itemAt(i)
        if (item && item.hovered) return item
      }
      return null
    }
    visible: window.open && !window.menuOpen && !!slot
    width: label.implicitWidth + Style.spacing.lg * 2
    height: label.implicitHeight + Style.spacing.sm * 2
    x: window.popupX(slot, tooltip)
    y: window.popupY(slot, tooltip)
    radius: Style.cornerRadius
    color: Commons.Color.tooltip.background
    border.width: Style.normalBorderWidth
    border.color: Commons.Color.tooltip.border

    Text {
      id: label
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: tooltip.slot ? tooltip.slot.modelData.name : ""
      color: Commons.Color.tooltip.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Rectangle {
    id: menu

    readonly property var item: window.menuItem
    readonly property bool running: !!item && item.windows.length > 0

    visible: window.open && !!item
    width: Math.max(Style.space(140), menuColumn.implicitWidth) + Style.spacing.sm * 2
    height: menuColumn.implicitHeight + Style.spacing.sm * 2
    x: window.popupX(window.menuSlot, menu)
    y: window.popupY(window.menuSlot, menu)
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    border.width: Style.normalBorderWidth
    border.color: Commons.Color.popups.border

    Column {
      id: menuColumn
      x: Style.spacing.sm
      y: Style.spacing.sm
      width: menu.width - Style.spacing.sm * 2

      MenuRow {
        text: menu.running ? strings.t("menu.newWindow") : strings.t("menu.open")
        onTriggered: window.dock.launch(menu.item)
      }

      MenuRow {
        visible: menu.running
        text: strings.tn("menu.quit", menu.item ? menu.item.windows.length : 0)
          .arg(Commons.I18n.formatNumber(menu.item ? menu.item.windows.length : 0))
        onTriggered: window.dock.quit(menu.item)
      }
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? Style.spacing.popupRowHeight : 0
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: row.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        row.triggered()
        window.closeMenu()
      }
    }
  }
}
