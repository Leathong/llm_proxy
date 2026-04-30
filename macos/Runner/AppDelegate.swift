import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 关闭窗口后不退出应用，保持后台运行
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // 点击 Dock 图标或通过其他方式重新打开应用时，确保窗口显示
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    if !hasVisibleWindows {
      // 如果没有可见窗口，遍历所有窗口找到主窗口并显示
      for window in sender.windows {
        if window.isKind(of: MainFlutterWindow.self) {
          window.setIsVisible(true)
          window.makeKeyAndOrderFront(nil)
          break
        }
      }
    }
    return true
  }
}
