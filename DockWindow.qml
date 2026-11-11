import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "DockModel.js" as DockModel

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

  // The app being dragged along the dock, how far the pointer has taken it,
  // and the slot it would land in.
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragOffset: 0
  readonly property bool dragging: dragIndex >= 0
  // Off while a drop resets the slots, so they snap to the new order rather
  // than sliding back from where they stepped aside.
  property bool animateShifts: true
  // After a drop the slots have moved under a still pointer, so hover is
  // stale until it moves again.
  property bool hoverStale: false
  property point dropPoint

  function endDrag() {
    window.animateShifts = false
    Qt.callLater(function() { window.animateShifts = true })
    window.hoverStale = true
    window.dragIndex = -1
    window.dropIndex = -1
    window.dragOffset = 0
    hideTimer.restart()
  }

  property var menuItem: null
  property Item menuSlot: null
  readonly property bool menuOpen: menuItem !== null
  readonly property bool open: !fullscreen && (revealed || menuOpen || dragging)

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
      if (!bodyHover.hovered && !edgeHover.hovered && !window.menuOpen && !window.dragging) window.revealed = false
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

    // The apps plus the settings button at the end.
    readonly property int count: appRepeater.count + 1
    width: window.vertical ? window.slotSize + window.padding * 2 : count * window.slotSize + window.padding * 2
    height: window.vertical ? count * window.slotSize + window.padding * 2 : window.slotSize + window.padding * 2

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
      // Only a real move clears stale hover; the release reports the pointer too.
      onPointChanged: {
        if (!window.hoverStale || window.dragging) return
        var at = point.position
        if (Math.hypot(at.x - window.dropPoint.x, at.y - window.dropPoint.y) > Style.space(4)) window.hoverStale = false
      }
    }

    Grid {
      id: slots
      anchors.centerIn: parent
      columns: window.vertical ? 1 : body.count

      Repeater {
        id: appRepeater
        model: window.dock ? window.dock.itemModel : null
        delegate: AppSlot {}
      }

      SettingsSlot { id: settingsSlot }
    }
  }

  // Opens the settings panel to choose the dock's apps.
  component SettingsSlot: Item {
    id: gear

    readonly property bool hovered: gearMouse.containsMouse
    readonly property string label: strings.t("dock.settings")

    width: window.slotSize
    height: window.slotSize

    MouseArea {
      id: gearMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        window.close()
        window.dock.openSettings()
      }
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "⚙"
      color: Commons.Color.bar.text
      opacity: gear.hovered ? 1 : 0.6
      font.family: Style.font.family
      font.pixelSize: Math.round(window.iconSize * 0.6)
      scale: gear.hovered ? 1.15 : 1
      transformOrigin: window.popOrigin
      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    }
  }

  component AppSlot: Item {
    id: slot

    required property string key
    required property int index
    readonly property var modelData: window.dock ? window.dock.itemFor(key) : null
    readonly property bool running: !!modelData && modelData.windows.length > 0
    readonly property bool hovered: mouse.containsMouse && !window.dragging && !window.hoverStale
    readonly property string label: modelData ? modelData.name : ""
    readonly property bool lifted: window.dragIndex === index
    property point pressPoint
    property bool dragged: false

    // Slots between where the dragged app was and where it would land step
    // aside to make room; the dragged one follows the pointer.
    readonly property real shift: !window.dragging ? 0
      : lifted ? window.dragOffset
      : (window.dragIndex < index && index <= window.dropIndex) ? -window.slotSize
      : (window.dropIndex <= index && index < window.dragIndex) ? window.slotSize
      : 0
    property real displayedShift: shift
    Behavior on displayedShift {
      enabled: window.animateShifts && window.dragging && !slot.lifted
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    z: lifted ? 1 : 0
    width: window.slotSize
    height: window.slotSize

    // The slot, and the pointer handling in it, stays put; only its content
    // moves. Reading the pointer through a moving item would feed each move
    // back into the next.
    function bodyPoint(event) {
      return slot.mapToItem(body, event.x, event.y)
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: slot.lifted ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      // Keeps the pointer while dragging, even past the dock's ends.
      preventStealing: true

      onPressed: function(event) {
        slot.dragged = false
        if (event.button === Qt.LeftButton) slot.pressPoint = slot.bodyPoint(event)
      }

      onPositionChanged: function(event) {
        if (!(mouse.pressedButtons & Qt.LeftButton)) return
        var point = slot.bodyPoint(event)
        var delta = window.vertical ? point.y - slot.pressPoint.y : point.x - slot.pressPoint.x
        // A press that wanders is a drag in the making, not a click.
        if (Math.hypot(point.x - slot.pressPoint.x, point.y - slot.pressPoint.y) > Style.space(4)) slot.dragged = true
        if (!window.dragging) {
          if (Math.abs(delta) < Style.space(6)) return
          window.closeMenu()
          // Landing slot first, so no slot counts as in between for a frame.
          window.dropIndex = slot.index
          window.dragIndex = slot.index
        }
        if (!slot.lifted) return
        window.dragOffset = delta
        window.dropIndex = DockModel.dropIndex(slot.index, delta, window.slotSize, appRepeater.count)
      }

      onReleased: function(event) {
        if (!slot.lifted) return
        window.dropPoint = slot.bodyPoint(event)
        var from = window.dragIndex
        var to = window.dropIndex
        slot.dragged = true
        window.endDrag()
        window.dock.reorder(from, to)
      }

      onCanceled: if (slot.lifted) window.endDrag()

      onClicked: function(event) {
        // A drag ends in a release over the app, which is not a click on it.
        if (slot.dragged) {
          slot.dragged = false
          return
        }
        if (!slot.modelData) return
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

    Item {
      id: content
      width: slot.width
      height: slot.height
      transform: Translate {
        x: window.vertical ? 0 : slot.displayedShift
        y: window.vertical ? slot.displayedShift : 0
      }

      Image {
        x: window.iconInset
        y: window.iconInset
        width: window.iconSize
        height: window.iconSize
        sourceSize: Qt.size(window.iconSize * 2, window.iconSize * 2)
        source: window.dock && slot.modelData ? window.dock.iconFor(slot.modelData) : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        scale: slot.lifted || slot.hovered ? 1.15 : 1
        opacity: slot.lifted ? 0.85 : 1
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
      if (settingsSlot.hovered) return settingsSlot
      for (var i = 0; i < appRepeater.count; i++) {
        var item = appRepeater.itemAt(i)
        if (item && item.hovered) return item
      }
      return null
    }
    visible: window.open && !window.menuOpen && !window.dragging && !!slot
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
      text: tooltip.slot ? tooltip.slot.label : ""
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

      MenuRow {
        text: strings.t("menu.remove")
        onTriggered: window.dock.removeApp(menu.item.id)
      }

      MenuRow {
        text: strings.t("dock.settings")
        onTriggered: window.dock.openSettings()
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
