import Flutter
import Network
#if os(iOS)
import UIKit
#endif

/// Exposes the OS metered capability (`NWPath.isExpensive`, which reflects
/// the underlying transport even when a VPN masks it) over the
/// `net.kaiwu.connectivity_status/metered` MethodChannel.
///
/// Registered automatically by `GeneratedPluginRegistrant` — no manual
/// call needed in a consuming app's `AppDelegate`. Each query spins up a
/// fresh `NWPathMonitor` and reads the current path once, so the answer can
/// never be staler than the connection-type list it is joined with on the
/// Dart side.
public class ConnectivityStatusPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "net.kaiwu.connectivity_status/metered",
      binaryMessenger: registrar.messenger()
    )
    let instance = ConnectivityStatusPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "isActiveNetworkMetered" else {
      result(FlutterMethodNotImplemented)
      return
    }
    Self.readMetered(result: result)
  }

  /// Reads the current network path's metered flag via a one-shot
  /// `NWPathMonitor`, then tears it down.
  private static func readMetered(result: @escaping FlutterResult) {
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "net.kaiwu.connectivity_status.metered")
    var replied = false

    monitor.pathUpdateHandler = { path in
      // Single-reply guard: take the first delivered path, then tear the
      // monitor down. Cancelling and niling the handler breaks the
      // monitor↔closure retain cycle so this per-call monitor deallocates.
      guard !replied else {
        return
      }
      replied = true

      let metered = path.isExpensive
      monitor.cancel()
      monitor.pathUpdateHandler = nil

      // FlutterResult must be delivered on the platform (main) thread.
      DispatchQueue.main.async {
        result(metered)
      }
    }

    monitor.start(queue: queue)
  }
}
