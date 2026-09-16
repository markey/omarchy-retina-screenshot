import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string scriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("scripts/retina-screenshot")).replace(/^file:\/\//, ""))

  function startCapture(mode): string {
    if (captureProcess.running) return "busy"
    captureProcess.command = [root.scriptPath, mode, "--scale", "2"]
    captureProcess.running = true
    return "started"
  }

  function capture(): string { return root.startCapture("--region") }
  function captureRegion(): string { return root.startCapture("--region") }
  function captureWindow(): string { return root.startCapture("--window") }

  Process {
    id: captureProcess
  }

  IpcHandler {
    target: "mark.retina-screenshot"

    function capture(): string { return root.capture() }
    function captureRegion(): string { return root.captureRegion() }
    function captureWindow(): string { return root.captureWindow() }
    function status(): string { return captureProcess.running ? "busy" : "idle" }
  }
}
