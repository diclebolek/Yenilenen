import 'package:flutter/material.dart';

import '../themes/app_theme.dart';

/// Açık yeşil arka plan, koyu yeşil metin; uygulama karanlık modunda bile aynı görünür.
void showThemeIndependentInfoDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String okLabel,
}) {
  showDialog<void>(
    context: context,
    builder: (ctx) {
      return Theme(
        data: ThemeData(
          useMaterial3: true,
          fontFamily: 'PlayfairDisplay',
          colorScheme: const ColorScheme.light(
            primary: AppTheme.infoDialogForeground,
            onPrimary: Colors.white,
            surface: AppTheme.infoDialogBackground,
            onSurface: AppTheme.infoDialogForeground,
          ),
        ),
        child: AlertDialog(
          backgroundColor: AppTheme.infoDialogBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          title: Text(
            title,
            style: const TextStyle(
              color: AppTheme.infoDialogForeground,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              body,
              style: const TextStyle(
                color: AppTheme.infoDialogForeground,
                height: 1.45,
                fontSize: 15,
              ),
            ),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.infoDialogForeground,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                okLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
