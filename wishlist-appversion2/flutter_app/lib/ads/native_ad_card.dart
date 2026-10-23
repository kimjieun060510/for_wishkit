import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../theme/diary_theme.dart';
import 'ads_config.dart';

/// 상품 카드 사이에 들어가는 광고 카드.
///
/// 상품 카드(흰색)와 헷갈리지 않게 한 톤 어두운 회색 바탕 + 왼쪽 위 "광고" 표시를 붙인다.
/// AdMob 정책상 광고는 앱 콘텐츠와 분명히 구분돼야 한다 — 이 색·표시를 상품 카드와 비슷하게
/// 바꾸지 말 것.
///
/// 광고를 못 불러오면(네트워크·광고 없음) 칸을 통째로 없앤다 — 빈 회색 박스를 남기지 않는다.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key});

  /// 상품 카드(흰색)보다 한 톤 어두운, 눈에 덜 띄는 회색.
  static const background = Color(0xFFEDEDED);

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard>
    with AutomaticKeepAliveClientMixin {
  NativeAd? _ad;
  bool _loaded = false;

  // 스크롤로 화면 밖에 나갔다 돌아올 때마다 광고를 새로 불러오지 않게 살려 둔다.
  @override
  bool get wantKeepAlive => _ad != null;

  @override
  void initState() {
    super.initState();
    if (!AdsConfig.supported) return;
    _ad = NativeAd(
      adUnitId: AdsConfig.nativeUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: NativeAdCard.background,
        cornerRadius: 10,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: DiaryColors.inkSoft,
          style: NativeTemplateFontStyle.bold,
          size: 13,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: DiaryColors.inkMuted,
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: DiaryColors.inkSoft,
          size: 12,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: DiaryColors.inkSoft,
          size: 11,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          if (mounted) {
            setState(() => _loaded = false);
            updateKeepAlive();
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: NativeAdCard.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DiaryColors.grid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: DiaryColors.inkSoft,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '광고',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 크기는 AdMob 작은 템플릿 권장 범위(320×90 ~ 400×200)를 따른다.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 320,
                minHeight: 90,
                maxWidth: 400,
                maxHeight: 200,
              ),
              child: AdWidget(ad: ad),
            ),
          ),
        ],
      ),
    );
  }
}
