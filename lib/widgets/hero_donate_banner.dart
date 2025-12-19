import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui' show ImageFilter;
import '../localization/translations.dart';
import '../providers/language_provider.dart';

class HeroDonateBanner extends StatefulWidget {
  const HeroDonateBanner({
    super.key,
    required this.imageAssetPath,
    this.languageProvider,
  });

  final String imageAssetPath; // Sol panel görseli
  final LanguageProvider? languageProvider;

  @override
  State<HeroDonateBanner> createState() => _HeroDonateBannerState();
}

class _HeroDonateBannerState extends State<HeroDonateBanner> {
  List<_DonateSlide> get _slides {
    final locale = widget.languageProvider?.currentLocale ?? const Locale('tr');
    return [
      _DonateSlide(
        title: translate('tema_title', locale),
        buttonLabel: translate('tree_donation', locale),
        url:
            'https://www.tema.org.tr/yenidenyesertecegiz-canakkale/tesekkur-sertifika',
        icon: Icons.volunteer_activism_outlined,
        logoPath: 'assets/images/tema-vakfi-logosu_1.png',
      ),
      _DonateSlide(
        title: translate('greenpeace_title', locale),
        buttonLabel: translate('greenpeace_turkey', locale),
        url: 'https://www.greenpeace.org/turkey/',
        icon: Icons.public,
        logoPath: 'assets/images/greenpeacelogo.png',
      ),
      _DonateSlide(
        title: translate('akut_title', locale),
        buttonLabel: translate('akut_foundation', locale),
        url: 'https://www.akutvakfi.org.tr/',
        icon: Icons.warning_amber_rounded,
        logoPath: 'assets/images/akut.png',
      ),
      _DonateSlide(
        title: translate('cevko_title', locale),
        buttonLabel: translate('cevko_foundation', locale),
        url: 'https://www.cevko.org.tr/',
        icon: Icons.recycling,
        logoPath: 'assets/images/çevko.jpg',
      ),
    ];
  }

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ekran boyutunu al
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1024;

    // Responsive boyutlar
    final cardHeight = isMobile ? 120.0 : (isTablet ? 140.0 : 150.0);
    final cardWidth = isMobile ? 120.0 : (isTablet ? 130.0 : 140.0);
    final titleFontSize = isMobile ? 16.0 : (isTablet ? 18.0 : 20.0);
    final buttonFontSize = isMobile ? 12.0 : (isTablet ? 13.0 : 14.0);
    final labelFontSize = isMobile ? 10.0 : (isTablet ? 11.0 : 12.0);

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Başlık: GNÇ tarzında başlık
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              translate(
                'donate_title',
                widget.languageProvider?.currentLocale ?? const Locale('tr'),
              ),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: titleFontSize,
              ),
            ),
            Text(
              translate(
                'see_all',
                widget.languageProvider?.currentLocale ?? const Locale('tr'),
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.6,
                ),
                fontSize: buttonFontSize,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // GNÇ tarzında kart tasarımı
        SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _slides.length,
            itemBuilder: (context, index) {
              final slide = _slides[index];
              return Container(
                width: cardWidth,
                margin: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF304411).withValues(
                                alpha: 0.6,
                              ) // Koyu modda
                            : const Color(0xFF304411).withValues(
                                alpha: 0.6,
                              ), // Açık modda da koyu mod rengi
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => _open(Uri.parse(slide.url)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Padding(
                              padding: EdgeInsets.all(isMobile ? 8 : 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Logo
                                  Container(
                                    width: isMobile ? 24 : 32,
                                    height: isMobile ? 24 : 32,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: Image.asset(
                                        slide.logoPath,
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              // Logo yüklenemezse ikon göster
                                              return Icon(
                                                slide.icon,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                                size: isMobile ? 16 : 20,
                                              );
                                            },
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: isMobile ? 6 : 8),
                                  // Başlık
                                  Text(
                                    slide.buttonLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Colors
                                              .white, // Her iki modda da beyaz
                                          fontWeight: FontWeight.bold,
                                          fontSize: buttonFontSize,
                                        ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Alt şerit - tam genişlik, container'ın en altına yapışık
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 8 : 12,
                                vertical: isMobile ? 6 : 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(16),
                                  bottomRight: Radius.circular(16),
                                ),
                              ),
                              child: Text(
                                translate(
                                  'donate_button',
                                  widget.languageProvider?.currentLocale ??
                                      const Locale('tr'),
                                ),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: const Color(0xFF304411),
                                      fontWeight: FontWeight.w600,
                                      fontSize: labelFontSize,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DonateSlide {
  const _DonateSlide({
    required this.title,
    required this.buttonLabel,
    required this.url,
    required this.icon,
    required this.logoPath,
  });
  final String title;
  final String buttonLabel;
  final String url;
  final IconData icon;
  final String logoPath;
}
