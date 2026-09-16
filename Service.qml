import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property string pendingMode: "--region"
  readonly property bool busy: captureDelay.running || captureProcess.running

  readonly property string scriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("scripts/retina-screenshot")).replace(/^file:\/\//, ""))

  function startCapture(mode): string {
    if (root.busy) return "busy"
    root.pendingMode = mode
    captureDelay.restart()
    return "started"
  }

  function capture(): string { return root.startCapture("--region") }
  function captureRegion(): string { return root.startCapture("--region") }
  function captureWindow(): string { return root.startCapture("--window") }

  Process {
    id: captureProcess
  }

  // Let the bar's pointer-release dispatch finish before slurp creates its
  // input-grabbing layer surface. Starting inside the click callback can leave
  // slurp alive after its surface loses the compositor grab.
  Timer {
    id: captureDelay
    interval: 250
    repeat: false
    onTriggered: {
      captureProcess.command = [
        "timeout", "--signal=TERM", "--kill-after=3s", "180s",
        root.scriptPath, root.pendingMode, "--scale", "2"
      ]
      captureProcess.running = true
    }
  }

  IpcHandler {
    target: "mark.retina-screenshot"

    function capture(): string { return root.capture() }
    function captureRegion(): string { return root.captureRegion() }
    function captureWindow(): string { return root.captureWindow() }
    function status(): string { return root.busy ? "busy" : "idle" }
  }
}
