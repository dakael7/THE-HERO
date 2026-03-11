import Flutter
import UIKit
import FirebaseCore
import GoogleMaps
import google_mobile_ads

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let mapsKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String,
       !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    }
    FirebaseApp.configure()
    GeneratedPluginRegistrant.register(with: self)

    let factory = HeroNativeAdFactory()
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "heroNative",
      nativeAdFactory: factory
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

class HeroNativeAdFactory: NSObject, FLTNativeAdFactory {
  func createNativeAd(
    _ nativeAd: GADNativeAd,
    customOptions: [AnyHashable : Any]?
  ) -> GADNativeAdView {
    let adView = GADNativeAdView(frame: .zero)

    let headline = UILabel()
    headline.numberOfLines = 1
    headline.font = UIFont.boldSystemFont(ofSize: 16)

    let body = UILabel()
    body.numberOfLines = 2
    body.font = UIFont.systemFont(ofSize: 13)
    body.textColor = UIColor.darkGray

    let icon = UIImageView()
    icon.contentMode = .scaleAspectFit

    let cta = UIButton(type: .system)

    let textStack = UIStackView(arrangedSubviews: [headline, body])
    textStack.axis = .vertical
    textStack.spacing = 6

    let row = UIStackView(arrangedSubviews: [icon, textStack, cta])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = 10

    let root = UIStackView(arrangedSubviews: [row])
    root.axis = .vertical
    root.spacing = 0
    root.translatesAutoresizingMaskIntoConstraints = false

    adView.addSubview(root)

    NSLayoutConstraint.activate([
      root.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
      root.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -12),
      root.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
      root.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),
      icon.widthAnchor.constraint(equalToConstant: 40),
      icon.heightAnchor.constraint(equalToConstant: 40),
    ])

    headline.text = nativeAd.headline
    body.text = nativeAd.body
    if let image = nativeAd.icon?.image {
      icon.image = image
    }
    cta.setTitle(nativeAd.callToAction, for: .normal)

    adView.headlineView = headline
    adView.bodyView = body
    adView.iconView = icon
    adView.callToActionView = cta
    adView.nativeAd = nativeAd

    return adView
  }
}
