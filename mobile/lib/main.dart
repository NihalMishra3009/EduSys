import "package:edusys_mobile/app_entry.dart";
import "package:edusys_mobile/providers/auth_provider.dart";
import "package:edusys_mobile/providers/theme_provider.dart";
import "package:edusys_mobile/core/theme/liquid_glass_shell.dart";
import "package:edusys_mobile/core/theme/app_theme.dart";
import "package:edusys_mobile/core/utils/app_navigator.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:provider/provider.dart";

void main() {
  debugPaintBaselinesEnabled = false;
  debugPaintSizeEnabled = false;
  debugPaintPointersEnabled = false;
  debugRepaintRainbowEnabled = false;
  runApp(const EduSysApp());
}

class EduSysApp extends StatelessWidget {
  const EduSysApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..init()),
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          navigatorKey: AppNavigator.key,
          title: "EduSys",
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: themeProvider.themeMode,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final clampedTextScaler = media.textScaler
                .clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);
            return MediaQuery(
              data: media.copyWith(textScaler: clampedTextScaler),
              child: LiquidGlassShell(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const AppEntry(),
        ),
      ),
    );
  }
}
