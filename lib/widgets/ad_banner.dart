import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  String? get _bannerUnitId {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'ca-app-pub-3940256099942544/6300978111',
      TargetPlatform.iOS => 'ca-app-pub-3940256099942544/2934735716',
      _ => null,
    };
  }

  @override
  void initState() {
    super.initState();
    final id = _bannerUnitId;
    if (id == null) return;

    _bannerAd = BannerAd(
      adUnitId: id,
      size: AdSize.banner, // 320x50
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _bannerAd = null);
        },
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the UI height stable even if the ad isn’t loaded yet.
    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox(height: 50);
    }
    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }
}
