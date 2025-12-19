import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import '../localization/translations.dart';
import '../providers/language_provider.dart';

/// A card that flips on tap to reveal additional information.
class InfoFlipCard extends StatefulWidget {
  const InfoFlipCard({
    super.key,
    required this.frontTitle,
    required this.frontSummary,
    required this.backDetails,
    this.languageProvider,
  });

  final String frontTitle;
  final String frontSummary;
  final String backDetails;
  final LanguageProvider? languageProvider;

  @override
  State<InfoFlipCard> createState() => _InfoFlipCardState();
}

class _InfoFlipCardState extends State<InfoFlipCard> {
  bool _showBack = false;

  void _toggle() => setState(() => _showBack = !_showBack);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const Color flipBackColor =
        Colors.black; // arka yüz temel renk (cam efekti ile yarı saydam)

    Widget front = Container(
      width: 320,
      constraints: const BoxConstraints(minHeight: 120),
      child: Card(
        color: colorScheme.primary,
        surfaceTintColor: colorScheme.primary,
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.frontTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.frontSummary,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimary.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.touch_app, color: colorScheme.onPrimary),
                    const SizedBox(width: 6),
                    Text(
                      translate(
                        'touch_to_flip',
                        widget.languageProvider?.currentLocale ??
                            const Locale('tr'),
                      ),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onPrimary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Widget back = Container(
      width: 320,
      constraints: const BoxConstraints(minHeight: 120),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: flipBackColor.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      translate(
                        'details',
                        widget.languageProvider?.currentLocale ??
                            const Locale('tr'),
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.backDetails,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) {
        // İki yüz için ayrı dönüş eğrisi ve metni ayna yapmamak için iç düzeltme
        final bool isBack =
            (child.key is ValueKey) && (child.key as ValueKey).value == 'back';
        final double fullAngle =
            (isBack ? (animation.value + 1.0) : animation.value) *
            3.1416; // 0..pi (front), pi..2pi (back)
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final bool pastHalf =
                (fullAngle % (2 * 3.1416)) > (3.1416 / 2) &&
                (fullAngle % (2 * 3.1416)) < (3.1416 * 3 / 2);
            final Widget correctedChild = pastHalf
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(3.1416),
                    child: child,
                  )
                : child ?? const SizedBox.shrink();

            return Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(fullAngle),
              alignment: Alignment.center,
              child: correctedChild,
            );
          },
        );
      },
      child: _showBack
          ? back.copyWith(key: const ValueKey('back'))
          : front.copyWith(key: const ValueKey('front')),
    );
  }
}

extension on Widget {
  Widget copyWith({Key? key}) => KeyedSubtree(key: key, child: this);
}
