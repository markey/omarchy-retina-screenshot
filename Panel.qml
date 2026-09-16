import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "mark.retina-screenshot"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property string resultText: ""
  property bool captureProducedOutput: false
  property var pendingCommand: []
  readonly property bool captureBusy: captureDelay.running || captureProcess.running

  readonly property string scriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("scripts/retina-screenshot")).replace(/^file:\/\//, ""))
  readonly property bool copyEnabled: setting("copyToClipboard", true) === true
  readonly property bool saveEnabled: setting("saveScreenshot", true) === true

  function persistSetting(name, value) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[name] = value
    root.settings = entry
    if (root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function capture(mode) {
    if (root.captureBusy || (!copyEnabled && !saveEnabled)) return
    resultText = "Preparing…"
    captureProducedOutput = false
    pendingCommand = [
      "timeout", "--signal=TERM", "--kill-after=3s", "180s",
      scriptPath,
      mode,
      "--scale", "2",
      copyEnabled ? "--copy" : "--no-copy",
      saveEnabled ? "--save" : "--no-save"
    ]
    root.close()
    captureDelay.restart()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  Process {
    id: captureProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (value !== "") {
          root.captureProducedOutput = true
          root.resultText = value
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && !root.captureProducedOutput) root.resultText = "Cancelled"
      else if (exitCode === 0) root.resultText = root.saveEnabled ? "Saved" : "Copied"
      else root.resultText = "Capture failed — see notification"
    }
  }

  Timer {
    id: captureDelay
    interval: 250
    repeat: false
    onTriggered: {
      captureProcess.command = root.pendingCommand
      captureProcess.running = true
      root.resultText = "Capturing…"
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onReturnRequested: root.capture("--region")
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        Text {
          text: "Retina Screenshot"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          Layout.fillWidth: true
        }

        Text {
          text: "Interactive selection · dynamic 2× output"
          color: root.bar ? Qt.darker(root.bar.foreground, 1.35) : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          Layout.fillWidth: true
        }

        CheckBox {
          text: "Copy to clipboard"
          checked: root.copyEnabled
          enabled: !root.captureBusy
          onToggled: if (checked !== root.copyEnabled)
            root.persistSetting("copyToClipboard", checked)
        }

        CheckBox {
          text: "Save screenshot"
          checked: root.saveEnabled
          enabled: !root.captureBusy
          onToggled: if (checked !== root.saveEnabled)
            root.persistSetting("saveScreenshot", checked)
        }

        Button {
          text: root.captureBusy ? "Capturing…" : "Select a region"
          enabled: !root.captureBusy && (root.copyEnabled || root.saveEnabled)
          Layout.fillWidth: true
          onClicked: root.capture("--region")
        }

        Button {
          text: "Select a whole window"
          enabled: !root.captureBusy && (root.copyEnabled || root.saveEnabled)
          Layout.fillWidth: true
          onClicked: root.capture("--window")
        }

        Text {
          visible: root.resultText !== ""
          text: root.resultText
          elide: Text.ElideMiddle
          color: root.bar ? Qt.darker(root.bar.foreground, 1.25) : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          Layout.fillWidth: true
        }
      }
    }
  }
}
