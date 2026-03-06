package com.example.the_hero

import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    GoogleMobileAdsPlugin.registerNativeAdFactory(
      flutterEngine,
      "heroNative",
      HeroNativeAdFactory(LayoutInflater.from(this))
    )
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "heroNative")
    super.cleanUpFlutterEngine(flutterEngine)
  }
}

private class HeroNativeAdFactory(
  private val inflater: LayoutInflater
) : GoogleMobileAdsPlugin.NativeAdFactory {
  override fun createNativeAd(
    nativeAd: NativeAd,
    customOptions: MutableMap<String, Any>?
  ): NativeAdView {
    val adView = inflater.inflate(R.layout.hero_native_ad, null) as NativeAdView

    val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
    val bodyView = adView.findViewById<TextView>(R.id.ad_body)
    val iconView = adView.findViewById<ImageView>(R.id.ad_app_icon)
    val ctaView = adView.findViewById<Button>(R.id.ad_call_to_action)

    headlineView.text = nativeAd.headline
    adView.headlineView = headlineView

    val body = nativeAd.body
    if (body == null) {
      bodyView.visibility = View.GONE
    } else {
      bodyView.text = body
      bodyView.visibility = View.VISIBLE
    }
    adView.bodyView = bodyView

    val icon = nativeAd.icon
    if (icon == null) {
      iconView.visibility = View.GONE
    } else {
      iconView.setImageDrawable(icon.drawable)
      iconView.visibility = View.VISIBLE
    }
    adView.iconView = iconView

    val cta = nativeAd.callToAction
    if (cta == null) {
      ctaView.visibility = View.GONE
    } else {
      ctaView.text = cta
      ctaView.visibility = View.VISIBLE
    }
    adView.callToActionView = ctaView

    adView.setNativeAd(nativeAd)
    return adView
  }
}
