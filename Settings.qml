import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The dock's settings panel: the apps in the dock, in order, beside every
// installed app with a search field. Changes are saved as they are made.
OverlayWindow {
  id: window

  property var dock: null

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  WlrLayershell.namespace: "shadowpj-autodock-settings"

  property string query: ""
  readonly property var dockApps: dock ? dock.config.apps : []
  readonly property var results: {
    var revision = window.dockApps.length
    if (!window.dock || !window.shown) return []
    var used = {}
    for (var i = 0; i < window.dockApps.length; i++) used[window.dockApps[i]] = true
    return window.dock.allApps(window.query).filter(function(entry) { return !used[entry.id] }).slice(0, 200)
  }

  readonly property int rowHeight: Math.round(40 * Style.fontScale)
  readonly property int iconSize: Math.round(24 * Style.fontScale)
  readonly property int pad: Style.spacing.xxl

  onShownChanged: {
    if (!shown) return
    window.query = ""
    search.text = ""
    if (window.dock && window.dock.appLibrary) window.dock.appLibrary.refreshIcons()
    Qt.callLater(function() { search.forceActiveFocus() })
  }

  function close() { window.shown = false }

  // Clicking outside the card closes the panel.
  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Commons.Color.background, 0.45)
    MouseArea { anchors.fill: parent; onClicked: window.close() }
  }

  Rectangle {
    id: card
    width: Math.min(parent.width - window.pad * 4, Math.round(760 * Style.fontScale))
    height: Math.min(parent.height - window.pad * 4, Math.round(540 * Style.fontScale))
    anchors.centerIn: parent
    radius: Math.max(Style.cornerRadius, Style.spacing.lg)
    color: Commons.Color.popups.background
    border.width: Style.normalBorderWidth
    border.color: Commons.Color.popups.border

    scale: window.contentRevealed ? 1 : 0.97
    Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

    // Swallow clicks so they do not reach the backdrop.
    MouseArea { anchors.fill: parent }

    Keys.onEscapePressed: window.close()

    PlainLabel {
      id: title
      x: window.pad
      y: window.pad
      text: strings.t("settings.title")
      font.pixelSize: Style.font.body * 1.3
      font.bold: true
    }

    PlainLabel {
      anchors.right: parent.right
      anchors.rightMargin: window.pad
      anchors.verticalCenter: title.verticalCenter
      text: "✕"
      opacity: closeMouse.containsMouse ? 1 : 0.6
      MouseArea {
        id: closeMouse
        anchors.fill: parent
        anchors.margins: -Style.spacing.md
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: window.close()
      }
    }

    Row {
      id: columns
      x: window.pad
      y: title.y + title.height + window.pad
      width: card.width - window.pad * 2
      height: card.height - y - window.pad
      spacing: window.pad

      // The apps in the dock, in order.
      Column {
        width: (columns.width - columns.spacing) / 2
        height: columns.height
        spacing: Style.spacing.md

        PlainLabel {
          id: inDockLabel
          text: strings.tn("settings.inDock", window.dockApps.length).arg(Commons.I18n.formatNumber(window.dockApps.length))
          opacity: 0.7
        }

        Rectangle {
          width: parent.width
          height: parent.height - inDockLabel.height - parent.spacing
          radius: Style.cornerRadius
          color: Style.normalFill

          PlainLabel {
            visible: window.dockApps.length === 0
            anchors.centerIn: parent
            width: parent.width - window.pad * 2
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: strings.t("settings.empty")
            opacity: 0.6
          }

          ListView {
            id: dockList
            anchors.fill: parent
            anchors.margins: Style.spacing.sm
            clip: true
            model: window.dockApps
            boundsBehavior: Flickable.StopAtBounds

            delegate: AppRow {
              id: dockRow
              required property var modelData
              required property int index
              readonly property var entry: DesktopEntries.byId(modelData)

              width: dockList.width
              appName: entry ? entry.name : modelData
              appIcon: entry ? entry.icon : ""
              missing: !entry

              RowButton {
                glyph: "▲"
                enabled: dockRow.index > 0
                onClicked: window.dock.moveApp(dockRow.index, -1)
              }
              RowButton {
                glyph: "▼"
                enabled: dockRow.index < window.dockApps.length - 1
                onClicked: window.dock.moveApp(dockRow.index, 1)
              }
              RowButton {
                glyph: "✕"
                onClicked: window.dock.removeApp(dockRow.modelData)
              }
            }
          }
        }
      }

      // Every other app, searchable; clicking one adds it to the end.
      Column {
        width: (columns.width - columns.spacing) / 2
        height: columns.height
        spacing: Style.spacing.md

        TextField {
          id: search
          width: parent.width
          placeholderText: strings.t("settings.search")
          onTextChanged: window.query = text
          Keys.onEscapePressed: window.close()
          onAccepted: if (window.results.length > 0) window.dock.addApp(window.results[0].id)
        }

        Rectangle {
          width: parent.width
          height: parent.height - search.height - parent.spacing
          radius: Style.cornerRadius
          color: Style.normalFill

          PlainLabel {
            visible: window.results.length === 0
            anchors.centerIn: parent
            text: strings.t("settings.noResults")
            opacity: 0.6
          }

          ListView {
            id: allList
            anchors.fill: parent
            anchors.margins: Style.spacing.sm
            clip: true
            model: window.results
            boundsBehavior: Flickable.StopAtBounds

            delegate: AppRow {
              id: allRow
              required property var modelData
              width: allList.width
              appName: modelData.name
              appIcon: modelData.icon
              clickable: true
              onActivated: window.dock.addApp(allRow.modelData.id)

              RowButton {
                glyph: "+"
                onClicked: window.dock.addApp(allRow.modelData.id)
              }
            }
          }
        }
      }
    }
  }

  component PlainLabel: Text {
    textFormat: Text.PlainText
    color: Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  // One app: icon, name, and buttons placed in it as children.
  component AppRow: Rectangle {
    id: row

    property string appName: ""
    property string appIcon: ""
    property bool missing: false
    property bool clickable: false
    default property alias buttons: buttonRow.data
    signal activated()

    height: window.rowHeight
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (row.clickable) row.activated()
    }

    Image {
      id: icon
      x: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      width: window.iconSize
      height: window.iconSize
      sourceSize: Qt.size(window.iconSize * 2, window.iconSize * 2)
      source: window.dock ? window.dock.iconSource(row.appIcon) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      opacity: row.missing ? 0.4 : 1
    }

    PlainLabel {
      anchors.left: icon.right
      anchors.leftMargin: Style.spacing.lg
      anchors.right: buttonRow.left
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      text: row.missing ? strings.t("settings.notInstalled").arg(row.appName) : row.appName
      opacity: row.missing ? 0.5 : 1
    }

    Row {
      id: buttonRow
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs
    }
  }

  component RowButton: Rectangle {
    id: button

    property string glyph: ""
    signal clicked()

    width: Math.round(window.rowHeight * 0.8)
    height: width
    radius: Style.cornerRadius
    color: buttonMouse.containsMouse && button.enabled ? Style.hoverFill : "transparent"
    opacity: button.enabled ? 1 : 0.3

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: button.glyph
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: button.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }
}
