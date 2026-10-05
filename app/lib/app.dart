import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_page.dart';
import 'features/web/web_app_page.dart';
import 'state/providers.dart';
import 'ui/tokens/memos_tokens.dart';

/// 应用根组件。
///
/// 架构：
/// - **主界面 `/`**：内嵌官方 Web 前端。界面 100% 对齐官方
///   （地图 / 热力图 / 评论 / 反应 / Views / Inbox 全部直接可用）；
/// - **首次配置 `/setup`**：原生登录页（实例地址 + 账号密码 → 长效 PAT），
///   仅未登录时出现。除此以外没有任何原生业务界面。
///
/// 主题：官方**不使用** Material You 动态取色，而是自带 oklch 主题令牌，
/// 因此这里也用 [MemosTokens] 的精确色值（见 `ui/tokens/`）。
class MemosApp extends ConsumerWidget {
  const MemosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool signedIn = ref.watch(activeAccountProvider) != null;

    return MaterialApp.router(
      title: 'Peli',
      debugShowCheckedModeBanner: false,
      theme: memosTheme(Brightness.light),
      darkTheme: memosTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: _router(signedIn),
      builder: (BuildContext context, Widget? child) {
        // 全面屏：系统栏透明 + 图标明暗跟随主题，内容延伸到屏幕四边。
        final bool dark = Theme.of(context).brightness == Brightness.dark;
        final MemosThemeTokens tokens = context.tokens;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
            systemStatusBarContrastEnforced: false,
          ),
          child: ColoredBox(color: tokens.background, child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }

  /// 路由表。
  ///
  /// 用户可见的界面只有一个：`/`（官方 Web 前端本身）。
  /// `/setup` 是不可见的基础设施 —— 只在未登录时出现，登录后不再可达。
  GoRouter _router(bool signedIn) => GoRouter(
        initialLocation: signedIn ? '/' : '/setup',
        redirect: (BuildContext context, GoRouterState state) {
          final String location = state.matchedLocation;
          final bool atSetup = location == '/setup';
          if (!signedIn && !atSetup) return '/setup';
          if (signedIn && atSetup) return '/';
          return null;
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/setup',
            builder: (BuildContext context, GoRouterState state) => const AuthPage(),
          ),
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) => const WebViewHost(),
          ),
        ],
      );
}
/// 按官方令牌构建 ThemeData（light/dark 各一套）。
ThemeData memosTheme(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final ColorScheme scheme = dark ? MemosTokens.darkScheme() : MemosTokens.lightScheme();
  final MemosThemeTokens tokens = dark ? MemosThemeTokens.ofDark() : MemosThemeTokens.ofLight();

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.background,
    canvasColor: tokens.background,
    dividerColor: tokens.border,
    fontFamily: MemosTokens.fontSans,
    extensions: <ThemeExtension<dynamic>>[tokens],
    // 官方圆角体系：radius 8，sm/md/lg/xl = 4/6/8/12
    cardTheme: CardThemeData(
      color: tokens.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MemosTokens.radiusLg),
        side: BorderSide(color: tokens.border.withValues(alpha: 0.7)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MemosTokens.radiusXl),
        side: BorderSide(color: tokens.border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MemosTokens.radiusMd),
        side: BorderSide(color: tokens.border),
      ),
      textStyle: TextStyle(fontSize: MemosTokens.textUi, color: tokens.popoverForeground),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.muted,
      side: BorderSide.none,
      labelStyle: TextStyle(fontSize: MemosTokens.text2xs, color: tokens.foreground),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MemosTokens.radiusFull)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: false,
      hintStyle: TextStyle(fontSize: MemosTokens.textUi, color: tokens.mutedForeground),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MemosTokens.radiusMd),
        borderSide: BorderSide(color: tokens.input),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MemosTokens.radiusMd),
        borderSide: BorderSide(color: tokens.input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MemosTokens.radiusMd),
        borderSide: BorderSide(color: tokens.ring),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.primary,
        foregroundColor: tokens.primaryForeground,
        minimumSize: const Size(0, MemosTokens.buttonHeight),
        textStyle: const TextStyle(fontSize: MemosTokens.textUi),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MemosTokens.radiusMd),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tokens.primary,
        minimumSize: const Size(0, MemosTokens.buttonHeightSm),
        textStyle: const TextStyle(fontSize: MemosTokens.textUi),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MemosTokens.radiusMd),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: tokens.mutedForeground,
        minimumSize: const Size(MemosTokens.iconSm, MemosTokens.iconSm),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? tokens.popover : tokens.foreground,
      contentTextStyle: TextStyle(
        fontSize: MemosTokens.textUi,
        color: dark ? tokens.popoverForeground : tokens.background,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MemosTokens.radiusMd)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? tokens.popover : tokens.foreground,
        borderRadius: BorderRadius.circular(MemosTokens.radiusSm),
      ),
      textStyle: TextStyle(
        fontSize: MemosTokens.text2xs,
        color: dark ? tokens.popoverForeground : tokens.background,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: tokens.primary),
    listTileTheme: ListTileThemeData(
      textColor: tokens.foreground,
      iconColor: tokens.mutedForeground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}
