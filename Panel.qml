import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// OmaPlex: a Plex Media Server control panel hanging off its bar icon.
// Left click opens it, right click refreshes, middle click opens Plex.
Panel {
  id: root
  moduleName: "nosignal.plex"
  ipcTarget: "nosignal.plex"
  manageIpc: false

  // Keyboard cursor: a flat list of row keys rebuilt from what is on screen,
  // so j/k walks every actionable row whatever state the server is in.
  property bool cursorActive: false
  property string cursorKey: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool streaming: plex.sessions.length > 0
  readonly property color barIconColor: !plex.active ? Qt.darker(barForeground, 1.55) : (streaming ? Color.accent : barForeground)
  readonly property bool showConnect: plex.running && plex.reachable && plex.claimed && !plex.connected
  readonly property bool showClaim: plex.running && plex.reachable && !plex.claimed

  function glyph(cp) { return String.fromCodePoint(cp) }

  function libraryGlyph(type) {
    if (type === "movie") return glyph(0xF0381)
    if (type === "show") return glyph(0xF0502)
    if (type === "artist") return glyph(0xF075A)
    if (type === "photo") return glyph(0xF02E9)
    return glyph(0xF024B)
  }

  function libraryMeta(lib) {
    if (!lib) return ""
    if (lib.scanning || plex.scanningId === lib.id) return "Scanning for new files…"
    var names = { movie: "Movies", show: "TV shows", artist: "Music", photo: "Photos" }
    var kind = names[lib.type] || "Library"
    if (!lib.scannedAt) return kind
    return kind + " · scanned " + relativeTime(lib.scannedAt)
  }

  function relativeTime(epochSec) {
    var mins = Math.max(0, Math.round((Date.now() / 1000 - epochSec) / 60))
    if (mins < 1) return "just now"
    if (mins < 60) return mins + " min ago"
    var hours = Math.round(mins / 60)
    if (hours < 24) return hours + (hours === 1 ? " hour ago" : " hours ago")
    var days = Math.round(hours / 24)
    return days + (days === 1 ? " day ago" : " days ago")
  }

  function sessionMeta(s) {
    if (!s) return ""
    var parts = []
    if (s.user) parts.push(s.user)
    if (s.player) parts.push(s.player)
    parts.push(s.transcoding ? "Converting" : "Direct")
    if (s.state === "paused") parts.push("Paused")
    return parts.join(" · ")
  }

  // The hero draws this as a small pill beside the title, so keep it short.
  function heroDetail() {
    return plex.installed && plex.version !== "" ? "v" + plex.version : ""
  }

  function heroMeta() {
    if (!plex.loaded || !plex.installed) return plex.statusText
    if (plex.running && plex.reachable && streaming) {
      return plex.sessions.length === 1 ? "1 stream playing" : plex.sessions.length + " streams playing"
    }
    return plex.statusText + (plex.enabled ? " · starts with the computer" : "")
  }

  function navKeys() {
    var keys = []
    if (!plex.installed) return plex.loaded ? ["install"] : []
    keys.push("power", "boot", "open")
    if (showClaim) keys.push("claim")
    if (showConnect) keys.push("connect")
    keys.push("drive", "restart")
    if (plex.connected) {
      for (var i = 0; i < plex.libraries.length; i++) keys.push("lib:" + plex.libraries[i].id)
    }
    keys.push("uninstall")
    return keys
  }

  function has(key) { return cursorActive && cursorKey === key }

  function setCursor(key) {
    cursorActive = true
    cursorKey = key
  }

  function moveCursor(dy) {
    var keys = navKeys()
    if (keys.length === 0) return
    var at = keys.indexOf(cursorKey)
    if (at === -1) at = dy > 0 ? -1 : keys.length
    cursorKey = keys[Math.max(0, Math.min(keys.length - 1, at + dy))]
    cursorActive = true
    scrollCursorIntoView()
  }

  function activate(key) {
    if (key === "install") plex.install()
    else if (key === "power") plex.toggleRunning()
    else if (key === "boot") plex.setBoot(!plex.enabled)
    else if (key === "open" || key === "claim") plex.openWeb()
    else if (key === "connect") plex.connect()
    else if (key === "drive") plex.addDrive()
    else if (key === "restart") plex.restart()
    else if (key === "uninstall") plex.uninstall()
    else if (key.indexOf("lib:") === 0) plex.scan(libraryById(key.substring(4)))
  }

  function libraryById(id) {
    for (var i = 0; i < plex.libraries.length; i++) if (String(plex.libraries[i].id) === id) return plex.libraries[i]
    return null
  }

  function scrollCursorIntoView() {
    Qt.callLater(function() {
      var item = findRow(column, cursorKey)
      if (!panelFlick || !item) return
      var margin = Style.space(6)
      var top = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function findRow(item, key) {
    if (!item) return null
    if (item.rowKey !== undefined && item.rowKey === key && item.visible) return item
    for (var i = 0; i < item.children.length; i++) {
      var hit = findRow(item.children[i], key)
      if (hit) return hit
    }
    return null
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    plex.watching = opened
    if (opened) {
      cursorActive = false
      cursorKey = ""
      if (panelFlick) panelFlick.contentY = 0
      plex.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Service {
    id: plex
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { plex.refresh(); return "ok" }
    function status(): string { return plex.statusText }
    function start(): string { plex.start(); return "ok" }
    function stop(): string { plex.stop(); return "ok" }
    function restart(): string { plex.restart(); return "ok" }
    function openWeb(): string { plex.openWeb(); return "ok" }
    function connect(): string { plex.connect(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        PlexIcon {
          anchors.centerIn: parent
          iconSize: Style.space(13)
          color: root.barIconColor
          opacity: plex.active ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) plex.refresh()
      else if (buttonCode === Qt.MiddleButton) { if (plex.installed) plex.openWeb() }
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.moveCursor(1); return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activate(root.cursorKey)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = String(t).toLowerCase()
        if (k === "r") plex.refresh()
        else if (k === "o" && plex.installed) plex.openWeb()
        else if (k === "p" && plex.installed) plex.toggleRunning()
        else if (k === "s" && root.cursorKey.indexOf("lib:") === 0) root.activate(root.cursorKey)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            readonly property string rowKey: "power"
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              width: parent.width
              title: plex.serverName !== "" ? plex.serverName : "Plex"
              meta: root.heroMeta()
              detail: root.heroDetail()
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: plex.active ? 1.0 : 0.5
              iconComponent: Component {
                PlexIcon {
                  iconSize: Style.font.display
                  color: plex.active ? root.foreground : root.dim
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: plex.installed
                  checked: plex.active
                  busy: plex.busy
                  hasCursor: root.has("power")
                  foreground: root.foreground
                  onHovered: function(on) { if (on) root.setCursor("power") }
                  onToggled: plex.toggleRunning()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: plex.active ? "Stop Plex" : "Start Plex"
                    fontFamily: root.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: plex.actionStatus !== "" || plex.lastError !== ""
            width: parent.width
            text: plex.actionStatus !== "" ? plex.actionStatus : plex.lastError
            color: plex.lastError !== "" && plex.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          ActionRow {
            rowKey: "install"
            visible: plex.loaded && !plex.installed
            icon: root.glyph(0xF01DA)
            title: "Install Plex Media Server"
            subtitle: "Installs Plex and starts it with the computer"
          }

          Column {
            visible: plex.installed
            width: parent.width
            spacing: Style.space(6)

            ActionRow {
              rowKey: "boot"
              icon: root.glyph(0xF0425)
              title: "Start with the computer"
              subtitle: plex.enabled ? "Plex starts by itself after a restart" : "You start Plex yourself"
              trailing: Component {
                ToggleSwitch {
                  checked: plex.enabled
                  busy: plex.busy
                  cursorRing: false
                  foreground: root.foreground
                  onToggled: plex.setBoot(!plex.enabled)
                }
              }
            }

            ActionRow {
              rowKey: "open"
              icon: root.glyph(0xF059F)
              title: "Open Plex"
              subtitle: plex.running ? plex.webUrl : "Start Plex first"
              enabled: plex.running
            }

            ActionRow {
              rowKey: "claim"
              visible: root.showClaim
              icon: root.glyph(0xF0342)
              title: "Finish setting up Plex"
              subtitle: "Sign in to claim this server and add your libraries"
            }

            ActionRow {
              rowKey: "connect"
              visible: root.showConnect
              icon: root.glyph(0xF0306)
              title: plex.tokenSaved ? "Connect again" : "Connect OmaPlex to Plex"
              subtitle: "Shows what's playing and lets you scan libraries"
            }

            ActionRow {
              rowKey: "drive"
              icon: root.glyph(0xF02CA)
              title: "Add a media drive"
              subtitle: "Opens it at every start and lets Plex read it"
            }

            ActionRow {
              rowKey: "restart"
              icon: root.glyph(0xF0709)
              title: "Restart Plex"
              subtitle: "Fixes most hiccups"
              enabled: plex.running
            }
          }

          PanelSeparator {
            visible: plex.connected
            foreground: root.foreground
          }

          Column {
            visible: plex.connected
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "NOW PLAYING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              textFormat: Text.PlainText
              visible: plex.sessions.length === 0
              width: parent.width
              text: "Nothing is playing."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Repeater {
              model: plex.sessions
              SessionRow {
                required property var modelData
                width: column.width
                session: modelData
              }
            }
          }

          PanelSeparator {
            visible: plex.connected
            foreground: root.foreground
          }

          Column {
            visible: plex.connected
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "LIBRARIES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              textFormat: Text.PlainText
              visible: plex.libraries.length === 0
              width: parent.width
              text: "No libraries yet. Add one in Plex."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Repeater {
              model: plex.libraries
              ActionRow {
                required property var modelData
                rowKey: "lib:" + modelData.id
                icon: root.libraryGlyph(modelData.type)
                title: modelData.title
                subtitle: root.libraryMeta(modelData)
                enabled: !plex.busy
                trailing: Component {
                  PanelActionButton {
                    iconText: root.glyph(0xF0450)
                    tooltipText: "Scan for new files"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    enabled: !plex.busy
                    onClicked: plex.scan(modelData)
                  }
                }
              }
            }
          }

          PanelSeparator {
            visible: plex.installed
            foreground: root.foreground
          }

          ActionRow {
            rowKey: "uninstall"
            visible: plex.installed
            icon: root.glyph(0xF01B4)
            title: "Remove Plex"
            subtitle: "Your media files are never touched"
            muted: true
          }
        }
      }
    }
  }

  // One clickable, cursor-able row: glyph, title over subtitle, and an
  // optional trailing control (a switch or a small action button).
  component ActionRow: CursorSurface {
    id: row
    property string rowKey: ""
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool muted: false
    property Component trailing: null

    width: parent ? parent.width : 0
    hasCursor: root.has(rowKey)
    foreground: root.foreground
    opacity: enabled ? 1.0 : 0.45
    implicitHeight: rowLayout.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: row.enabled
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(row.rowKey)
      onClicked: root.activate(row.rowKey)
    }

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: row.icon
        color: row.muted ? root.dim : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.font.icon * 1.4
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.title
          color: row.muted ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: row.subtitle !== ""
          text: row.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Loader {
        active: row.trailing !== null
        sourceComponent: row.trailing
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  // A stream in progress: what, who and where, with a thin progress line.
  component SessionRow: Item {
    id: srow
    property var session: null

    implicitHeight: sessionCol.implicitHeight + Style.space(8)

    RowLayout {
      id: sessionLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: srow.session && srow.session.state === "paused" ? root.glyph(0xF03E4) : root.glyph(0xF040A)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.font.icon * 1.4
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignTop
      }

      ColumnLayout {
        id: sessionCol
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: srow.session ? srow.session.title : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: text !== ""
          text: srow.session ? srow.session.subtitle : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: root.sessionMeta(srow.session)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
          implicitHeight: Math.max(2, Style.space(3))
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
          radius: Style.cornerRadius > 0 ? height / 2 : 0

          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, srow.session ? Number(srow.session.progress || 0) : 0))
            height: parent.height
            radius: parent.radius
            color: Color.accent
          }
        }
      }
    }
  }
}
