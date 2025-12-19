import 'package:flutter/material.dart';

class HeroImageBanner extends StatelessWidget {
  const HeroImageBanner({
    super.key,
    required this.imageAssetPath,
    this.heightFraction = 0.4,
    this.overlayText,
  });

  final String imageAssetPath;
  final double heightFraction; // portion of screen height (< 0.5 recommended)
  final String? overlayText;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bannerHeight = (screenHeight * heightFraction).clamp(140.0, 360.0);
    final text = overlayText; // cache to avoid null assertions

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: bannerHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(imageAssetPath, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.40),
                  ],
                ),
              ),
            ),
            if (text != null && text.isNotEmpty)
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
