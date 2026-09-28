import Flutter
import UIKit

/// Apple's own UITabBar, hosted in Flutter (`lib/core/widgets/pg_tab_bar.dart`).
///
/// On iOS 26 the system draws it in Liquid Glass: the floating capsule, the
/// lens that follows a finger across tabs, and the material's own response to
/// Reduce Transparency, Increase Contrast and Reduce Motion. Flutter can only
/// imitate that material, so on iOS 26+ the shell asks for the real bar and
/// everywhere else keeps PGFrostedNavBar.
///
/// Dart → iOS: creation params {labels, symbols, selectedSymbols, selectedIndex,
/// tint (ARGB), dark}, then `setSelectedIndex` and `setStyle`.
/// iOS → Dart: `select` with the tapped index.
final class NativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "pharmaguide/tab_bar"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeTabBarView(
      frame: frame,
      viewId: viewId,
      params: args as? [String: Any] ?? [:],
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class NativeTabBarView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let container: UIView
  private let tabBar = UITabBar()
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    params: [String: Any],
    messenger: FlutterBinaryMessenger
  ) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    channel = FlutterMethodChannel(
      name: "\(NativeTabBarFactory.viewType)_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    let labels = params["labels"] as? [String] ?? []
    let symbols = params["symbols"] as? [String] ?? []
    let selectedSymbols = params["selectedSymbols"] as? [String] ?? symbols
    tabBar.items = labels.enumerated().map { index, label in
      let item = UITabBarItem(
        title: label,
        image: UIImage(systemName: symbols[safe: index] ?? ""),
        selectedImage: UIImage(systemName: selectedSymbols[safe: index] ?? "")
      )
      item.tag = index
      return item
    }
    tabBar.delegate = self
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      tabBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      tabBar.topAnchor.constraint(equalTo: container.topAnchor),
    ])

    select(params["selectedIndex"] as? Int ?? 0)
    applyStyle(params)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "setSelectedIndex":
        self.select(call.arguments as? Int ?? 0)
        result(nil)
      case "setStyle":
        self.applyStyle(call.arguments as? [String: Any] ?? [:])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { container }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("select", arguments: item.tag)
  }

  private func select(_ index: Int) {
    tabBar.selectedItem = tabBar.items?[safe: index]
  }

  /// The app's own light/dark choice can differ from the system's, so the
  /// bar follows Flutter's brightness rather than the device setting.
  private func applyStyle(_ params: [String: Any]) {
    if let dark = params["dark"] as? Bool {
      container.overrideUserInterfaceStyle = dark ? .dark : .light
    }
    if let argb = params["tint"] as? Int {
      tabBar.tintColor = UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255
      )
    }
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
