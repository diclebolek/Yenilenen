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
      _DonateSlide(
        title: translate('docev_title', locale),
        buttonLabel: translate('docev_foundation', locale),
        url: 'https://www.docev.org.tr/',
        icon: Icons.forest,
        logoPath: 'assets/images/doçev.jpg',
      ),
      _DonateSlide(
        title: translate('cekul_title', locale),
        buttonLabel: translate('cekul_foundation', locale),
        url: 'https://www.cekulvakfi.org.tr/',
        icon: Icons.account_balance,
        logoPath: 'assets/images/cekül.jpg',
      ),
    ];
  }

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
    }
  }

  Widget _buildDonateCard(
    _DonateSlide slide,
    bool isMobile,
    bool isTablet,
    double cardWidth,
    double cardHeight,
    double buttonFontSize,
    double labelFontSize,
    bool isDark,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF304411) // Koyu modda navbar rengi
                : const Color(0xFF48631F), // Açık modda navbar rengi
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
                            errorBuilder: (context, error, stackTrace) {
                              // Logo yüklenemezse ikon göster
                              return Icon(
                                slide.icon,
                                color: Theme.of(context).colorScheme.primary,
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
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white, // Her iki modda da beyaz
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
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
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
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(
                                  0xFF304411) // Koyu modda navbar rengi
                              : const Color(
                                  0xFF48631F), // Açık modda navbar rengi
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
    );
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
    final buttonFontSize = isMobile ? 12.0 : (isTablet ? 13.0 : 14.0);
    final labelFontSize = isMobile ? 10.0 : (isTablet ? 11.0 : 12.0);

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Başlık: GNÇ tarzında başlık
        Text(
          translate(
            'donate_title',
            widget.languageProvider?.currentLocale ?? const Locale('tr'),
          ),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        // GNÇ tarzında kart tasarımı
        LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth >= 900;
            if (isWide) {
              // Geniş ekran: kutuları ortala
              return SizedBox(
                height: cardHeight,
                child: Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: _slides.map((slide) {
                      return SizedBox(
                        width: cardWidth,
                        height: cardHeight,
                        child: _buildDonateCard(
                          slide,
                          isMobile,
                          isTablet,
                          cardWidth,
                          cardHeight,
                          buttonFontSize,
                          labelFontSize,
                          isDark,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            }
            // Mobil/tablet: yatay scroll
            return SizedBox(
              height: cardHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Container(
                    width: cardWidth,
                    margin: const EdgeInsets.only(right: 12),
                    child: _buildDonateCard(
                      slide,
                      isMobile,
                      isTablet,
                      cardWidth,
                      cardHeight,
                      buttonFontSize,
                      labelFontSize,
                      isDark,
                    ),
                  );
                },
              ),
            );
          },
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
