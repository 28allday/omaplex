import QtQuick
import Quickshell
import Quickshell.Io

// State for the OmaPlex panel. Everything goes through bin/omaplex beside this
// file: `status` for a JSON snapshot, the rest for actions. Service control is
// plain systemctl, so polkit asks for a password through the shell's own agent.
Item {
  id: root

  property var settings: ({})
  // Polling runs faster while the panel is open, for live now-playing.
  property bool watching: false

  property bool installed: false
  property bool running: false
  property bool starting: false
  property bool enabled: false
  property bool reachable: false
  property bool claimed: false
  property bool tokenSaved: false
  property bool tokenValid: false
  property string version: ""
  property string serverName: ""
  property string address: ""
  property bool serverMode: false
  property string powerProfile: ""
  property var sessions: []
  property var libraries: []
  property bool loaded: false
  property string actionStatus: ""
  property string lastError: ""
  property string scanningId: ""

  // Optimistic on/off so the switch throws the instant it is clicked. -1 means
  // follow the real state, 0/1 while a stop/start is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  readonly property bool busy: actionProcess.running
  readonly property bool connected: tokenSaved && tokenValid
  readonly property string webUrl: address !== "" ? "http://" + address + ":32400/web" : "http://localhost:32400/web"
  readonly property string statusText: !loaded ? "Checking…"
    : !installed ? "Not installed"
    : starting || (running && !reachable) ? "Starting…"
    : running ? "Running"
    : "Stopped"

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property string helper: String(Qt.resolvedUrl("bin/omaplex")).replace(/^file:\/\//, "")

  property string _pendingLabel: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.running = true
    statusWatchdog.restart()
  }

  function applyStatus(raw) {
    var s
    try {
      s = JSON.parse(String(raw || ""))
    } catch (e) {
      lastError = "Couldn't read Plex's status"
      return
    }
    if (!s || s.ok !== true) return
    installed = s.installed === true
    running = s.running === true
    starting = s.starting === true
    enabled = s.enabled === true
    reachable = s.reachable === true
    claimed = s.claimed === true
    tokenSaved = s.tokenSaved === true
    tokenValid = s.tokenValid === true
    version = String(s.version || "")
    serverName = String(s.name || "")
    address = String(s.address || "")
    serverMode = s.serverMode === true
    powerProfile = String(s.powerProfile || "")
    sessions = s.sessions instanceof Array ? s.sessions : []
    libraries = s.libraries instanceof Array ? s.libraries : []
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    if (s.error) lastError = String(s.error)
    else if (!actionProcess.running) lastError = ""
    loaded = true
  }

  function run(args, label, desired) {
    if (actionProcess.running) return
    _desired = desired === undefined ? -1 : desired
    _pendingLabel = label || ""
    actionStatus = label || ""
    lastError = ""
    actionProcess.command = [helper].concat(args)
    actionProcess.running = true
  }

  function start() { if (installed) run(["start"], "", 1) }
  function stop() { if (installed) run(["stop"], "", 0) }
  function restart() { if (installed) run(["restart"], "Restarting Plex…") }
  function toggleRunning() { active ? stop() : start() }
  function setBoot(on) { if (installed) run(["boot", on ? "on" : "off"], on ? "Plex will start with the computer" : "Plex won't start with the computer") }
  function connect() { run(["connect"], "Connecting to Plex…") }
  function forget() { run(["forget"], "") }

  function scan(library) {
    if (!library || !connected) return
    scanningId = String(library.id || "")
    run(["scan", scanningId], "Scanning " + String(library.title || "library") + "…")
  }

  function openWeb() { Quickshell.execDetached([helper, "open"]) }
  function install() { Quickshell.execDetached([helper, "setup", "install"]) }
  function addDrive() { Quickshell.execDetached([helper, "setup", "drive"]) }
  function uninstall() { Quickshell.execDetached([helper, "setup", "uninstall"]) }
  function serverSetup() { Quickshell.execDetached([helper, "setup", "server"]) }

  Timer {
    id: refreshTimer
    interval: root.watching ? 4000 : root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // Plex takes several seconds to answer after a start, and the set-up
    // terminal installs it behind our back, so poll quickly for a while
    // after anything changes rather than waiting for the next tick.
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 8) {
        ticks = 0
        running = false
        root._desired = -1
      }
    }
  }

  Timer {
    // A status call that never returns must not freeze the panel forever.
    id: statusWatchdog
    interval: 12000
    onTriggered: if (statusProcess.running) statusProcess.running = false
  }

  Timer {
    id: actionStatusTimer
    interval: 2600
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    command: [root.helper, "status"]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyStatus(statusOut.text)
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      var err = String(actionErr.text || "").trim()
      if (exitCode !== 0) {
        root._desired = -1
        // systemctl reports a dismissed polkit prompt as an access error.
        root.lastError = /Access denied|Interactive authentication|cancelled/i.test(err)
          ? "Password prompt cancelled"
          : root.elide(err || "That didn't work")
        root.actionStatus = ""
      } else {
        root.actionStatus = String(actionOut.text || "").trim() === "Connected" ? "Connected to Plex" : root._pendingLabel
        if (root.actionStatus !== "") actionStatusTimer.restart()
      }
      root.scanningId = ""
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }
}
