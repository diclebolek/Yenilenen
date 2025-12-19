import 'dart:ui';
import 'package:flutter/material.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final void Function(int) onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isReportsPage = selectedIndex == 1; // Raporlar sayfası index 1

    // Seçili olmayan ikonlar için renk belirleme
    // Açık modda ve raporlar sayfasındayken beyaz, diğer durumlarda tema rengi
    final unselectedColor = isDark
        ? colorScheme.onSurface.withValues(alpha: 0.6)
        : isReportsPage
            ? Colors.white.withValues(alpha: 0.85) // Raporlar sayfasında beyaz
            : colorScheme.onSurface.withValues(alpha: 0.7);

    // Alt gezinme çubuğunu blur ve saydam yapmak için BackdropFilter ile sarıyoruz
    // ve ikon/etiket renklerini temadaki birincil (yeşil) renge bağlıyoruz.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          color: Colors.transparent,
          child: Theme(
            data: Theme.of(context).copyWith(
              navigationBarTheme: NavigationBarThemeData(
                height: 56,
                elevation: 0,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                indicatorColor: Colors.transparent,
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final bool isSelected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    size: isSelected ? 26 : 24, // Seçili ikon daha büyük
                    color: isSelected
                        ? colorScheme.primary // Seçili: tema rengi (yeşil)
                        : unselectedColor, // Seçili değil: tema rengi (gri ton)
                  );
                }),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final bool isSelected = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: 10,
                    color: isSelected
                        ? colorScheme.primary // Seçili: tema rengi
                        : unselectedColor, // Seçili değil: tema rengi
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  );
                }),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                destinations: destinations,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                indicatorColor: Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
