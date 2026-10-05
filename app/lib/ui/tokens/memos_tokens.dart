import 'package:flutter/material.dart';

import 'oklch.dart';

/// 官方前端设计令牌（1:1 搬运自 `web/src/themes/default.css` 与 `default-dark.css`）。
///
/// 为什么不"改成 Material 风格"：用户要求像素级复刻，颜色/圆角/字号/控件尺寸
/// 全部按官方值来，任何"顺手调一下"都会造成可见偏差。
///
/// | 令牌 | Light | Dark |
/// |---|---|---|
/// | background | `oklch(0.9818 0.0054 95.0986)` | `oklch(0.24 0.008 255)` |
/// | foreground | `oklch(0.2438 0.0269 95.7226)` | `oklch(0.9 0.006 255)` |
/// | card | `oklch(1 0 0)` | `oklch(0.275 0.009 255)` |
/// | primary | `oklch(0.45 0.08 250)` | `oklch(0.66 0.11 250)` |
/// | … | 见下方常量 | |
abstract final class MemosTokens {
  // ---------------------------------------------------------------------------
  // Light（default.css :root）
  // ---------------------------------------------------------------------------

  static final Color lightBackground = oklch(0.9818, 0.0054, 95.0986);
  static final Color lightForeground = oklch(0.2438, 0.0269, 95.7226);
  static final Color lightCard = oklch(1, 0, 0);
  static final Color lightCardForeground = oklch(0.1908, 0.002, 106.5859);
  static final Color lightPopover = oklch(1, 0, 0);
  static final Color lightPopoverForeground = oklch(0.2671, 0.0196, 98.939);
  static final Color lightPrimary = oklch(0.45, 0.08, 250);
  static final Color lightPrimaryForeground = oklch(0.9818, 0.0054, 95.0986);
  static final Color lightSecondary = oklch(0.9245, 0.0138, 92.9892);
  static final Color lightSecondaryForeground = oklch(0.4334, 0.0177, 98.6048);
  static final Color lightMuted = oklch(0.9341, 0.0153, 90.239);
  static final Color lightMutedForeground = oklch(0.5559, 0.0075, 97.4233);
  static final Color lightAccent = oklch(0.9245, 0.0138, 92.9892);
  static final Color lightAccentForeground = oklch(0.2671, 0.0196, 98.939);
  static final Color lightDestructive = oklch(0.5, 0.12, 25);
  static final Color lightDestructiveForeground = oklch(1, 0, 0);
  static final Color lightSuccess = oklch(0.55, 0.13, 150);
  static final Color lightSuccessForeground = oklch(0.98, 0.01, 150);
  static final Color lightWarning = oklch(0.62, 0.12, 70);
  static final Color lightWarningForeground = oklch(0.25, 0.03, 75);
  static final Color lightBorder = oklch(0.8847, 0.0069, 97.3627);
  static final Color lightInput = oklch(0.7621, 0.0156, 98.3528);
  static final Color lightRing = oklch(0.45, 0.08, 250);
  static final Color lightSidebar = oklch(0.9663, 0.008, 98.8792);
  static final Color lightSidebarForeground = oklch(0.359, 0.0051, 106.6524);
  static final Color lightSidebarAccent = oklch(0.9245, 0.0138, 92.9892);
  static final Color lightSidebarAccentForeground = oklch(0.325, 0, 0);

  // ---------------------------------------------------------------------------
  // Dark（default-dark.css :root）
  // ---------------------------------------------------------------------------

  static final Color darkBackground = oklch(0.24, 0.008, 255);
  static final Color darkForeground = oklch(0.9, 0.006, 255);
  static final Color darkCard = oklch(0.275, 0.009, 255);
  static final Color darkCardForeground = oklch(0.9, 0.006, 255);
  static final Color darkPopover = oklch(0.32, 0.01, 255);
  static final Color darkPopoverForeground = oklch(0.92, 0.006, 255);
  static final Color darkPrimary = oklch(0.66, 0.11, 250);
  static final Color darkPrimaryForeground = oklch(0.24, 0.008, 255);
  static final Color darkSecondary = oklch(0.33, 0.011, 255);
  static final Color darkSecondaryForeground = oklch(0.88, 0.006, 255);
  static final Color darkMuted = oklch(0.35, 0.011, 255);
  static final Color darkMutedForeground = oklch(0.72, 0.007, 255);
  static final Color darkAccent = oklch(0.39, 0.018, 250);
  static final Color darkAccentForeground = oklch(0.94, 0.006, 255);
  static final Color darkDestructive = oklch(0.64, 0.18, 24);
  static final Color darkDestructiveForeground = oklch(0.98, 0.004, 255);
  static final Color darkSuccess = oklch(0.7, 0.15, 155);
  static final Color darkSuccessForeground = oklch(0.2, 0.03, 155);
  static final Color darkWarning = oklch(0.78, 0.14, 75);
  static final Color darkWarningForeground = oklch(0.25, 0.03, 75);
  static final Color darkBorder = oklch(0.38, 0.01, 255);
  static final Color darkInput = oklch(0.42, 0.011, 255);
  static final Color darkRing = oklch(0.58, 0.095, 250);
  static final Color darkSidebar = oklch(0.21, 0.009, 255);
  static final Color darkSidebarForeground = oklch(0.76, 0.007, 255);
  static final Color darkSidebarAccent = oklch(0.31, 0.015, 250);
  static final Color darkSidebarAccentForeground = oklch(0.9, 0.006, 255);

  /// 遮罩层基色，透明度由使用处决定（官方：`bg-overlay/50`）。
  static final Color overlay = oklch(0, 0, 0);

  // ---------------------------------------------------------------------------
  // 尺寸（@theme inline / 组件约定）
  // ---------------------------------------------------------------------------

  /// `--radius: 0.5rem`，sm/md/lg/xl = radius-4/-2/0/+4。
  static const double radius = 8;
  static const double radiusSm = 4;
  static const double radiusMd = 6;
  static const double radiusLg = 8;
  static const double radiusXl = 12;

  /// 标签胶囊 / 圆点等用 `rounded-full`。
  static const double radiusFull = 999;

  /// 官方自定义字号：`--text-2xs` 11/16、`--text-ui` 13/18；正文 16/24。
  static const double text2xs = 11;
  static const double text2xsLineHeight = 16;
  static const double textUi = 13;
  static const double textUiLineHeight = 18;
  static const double textBase = 16;
  static const double textBaseLineHeight = 24;

  /// 控件方块尺寸约定：`icon-sm`=24（卡片动作）、`icon-compact`=28（工具栏/侧栏）、`icon`=32。
  static const double iconSm = 24;
  static const double iconCompact = 28;
  static const double icon = 32;

  /// 按钮高度：`sm: h-7`、`default: h-8`、`lg: h-9`。
  static const double buttonHeightSm = 28;
  static const double buttonHeight = 32;
  static const double buttonHeightLg = 36;

  /// 侧栏宽度范围（RootLayout：`SIDEBAR_MIN_WIDTH=224`、`SIDEBAR_MAX_WIDTH=400`）。
  static const double sidebarMinWidth = 224;
  static const double sidebarMaxWidth = 400;
  static const double sidebarDefaultWidth = 256;

  /// 时间线单列宽度（`max-w-2xl`）；多列瀑布流列宽上限 420、间距 12。
  static const double feedMaxWidth = 672;
  static const double gridGap = 12;
  static const double maxColumnWidth = 420;

  /// 列表分页大小（`DEFAULT_LIST_MEMOS_PAGE_SIZE = 16`）。
  static const int listPageSize = 16;

  /// 折叠阈值（ClampedSection）。
  static const double clampPreviewHeight = 360;
  static const double clampTriggerHeight = 420;

  /// 移动端顶部栏高度（`MobileAppHeader: h-12`）。
  static const double mobileHeaderHeight = 48;

  static const String fontSans = 'Roboto';
  static const String fontMono = 'monospace';

  // ---------------------------------------------------------------------------
  // ColorScheme 组装
  // ---------------------------------------------------------------------------

  static ColorScheme lightScheme() => ColorScheme(
        brightness: Brightness.light,
        primary: lightPrimary,
        onPrimary: lightPrimaryForeground,
        secondary: lightSecondary,
        onSecondary: lightSecondaryForeground,
        error: lightDestructive,
        onError: lightDestructiveForeground,
        surface: lightCard,
        onSurface: lightCardForeground,
        surfaceContainerHighest: lightMuted,
        onSurfaceVariant: lightMutedForeground,
        outline: lightBorder,
        outlineVariant: lightBorder,
        shadow: lightForeground,
        scrim: overlay,
        inverseSurface: lightForeground,
        onInverseSurface: lightBackground,
        inversePrimary: darkPrimary,
      );

  static ColorScheme darkScheme() => ColorScheme(
        brightness: Brightness.dark,
        primary: darkPrimary,
        onPrimary: darkPrimaryForeground,
        secondary: darkSecondary,
        onSecondary: darkSecondaryForeground,
        error: darkDestructive,
        onError: darkDestructiveForeground,
        surface: darkCard,
        onSurface: darkCardForeground,
        surfaceContainerHighest: darkMuted,
        onSurfaceVariant: darkMutedForeground,
        outline: darkBorder,
        outlineVariant: darkBorder,
        shadow: Colors.black,
        scrim: overlay,
        inverseSurface: darkForeground,
        onInverseSurface: darkBackground,
        inversePrimary: lightPrimary,
      );
}

/// 官方主题里 Material `ColorScheme` 覆盖不到的令牌（success/warning/sidebar/
/// popover/overlay 与几何尺寸）。
///
/// 通过 `ThemeExtension` 挂在 `ThemeData` 上，使用处写 `context.tokens.success`。
@immutable
class MemosThemeTokens extends ThemeExtension<MemosThemeTokens> {
  const MemosThemeTokens({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.popoverForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.success,
    required this.successForeground,
    required this.warning,
    required this.warningForeground,
    required this.border,
    required this.input,
    required this.ring,
    required this.overlay,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarAccent,
    required this.sidebarAccentForeground,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color popover;
  final Color popoverForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color destructive;
  final Color destructiveForeground;
  final Color success;
  final Color successForeground;
  final Color warning;
  final Color warningForeground;
  final Color border;
  final Color input;
  final Color ring;
  final Color overlay;
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarAccent;
  final Color sidebarAccentForeground;

  static MemosThemeTokens ofLight() => MemosThemeTokens(
        background: MemosTokens.lightBackground,
        foreground: MemosTokens.lightForeground,
        card: MemosTokens.lightCard,
        cardForeground: MemosTokens.lightCardForeground,
        popover: MemosTokens.lightPopover,
        popoverForeground: MemosTokens.lightPopoverForeground,
        muted: MemosTokens.lightMuted,
        mutedForeground: MemosTokens.lightMutedForeground,
        accent: MemosTokens.lightAccent,
        accentForeground: MemosTokens.lightAccentForeground,
        primary: MemosTokens.lightPrimary,
        primaryForeground: MemosTokens.lightPrimaryForeground,
        secondary: MemosTokens.lightSecondary,
        secondaryForeground: MemosTokens.lightSecondaryForeground,
        destructive: MemosTokens.lightDestructive,
        destructiveForeground: MemosTokens.lightDestructiveForeground,
        success: MemosTokens.lightSuccess,
        successForeground: MemosTokens.lightSuccessForeground,
        warning: MemosTokens.lightWarning,
        warningForeground: MemosTokens.lightWarningForeground,
        border: MemosTokens.lightBorder,
        input: MemosTokens.lightInput,
        ring: MemosTokens.lightRing,
        overlay: MemosTokens.overlay,
        sidebar: MemosTokens.lightSidebar,
        sidebarForeground: MemosTokens.lightSidebarForeground,
        sidebarAccent: MemosTokens.lightSidebarAccent,
        sidebarAccentForeground: MemosTokens.lightSidebarAccentForeground,
      );

  static MemosThemeTokens ofDark() => MemosThemeTokens(
        background: MemosTokens.darkBackground,
        foreground: MemosTokens.darkForeground,
        card: MemosTokens.darkCard,
        cardForeground: MemosTokens.darkCardForeground,
        popover: MemosTokens.darkPopover,
        popoverForeground: MemosTokens.darkPopoverForeground,
        muted: MemosTokens.darkMuted,
        mutedForeground: MemosTokens.darkMutedForeground,
        accent: MemosTokens.darkAccent,
        accentForeground: MemosTokens.darkAccentForeground,
        primary: MemosTokens.darkPrimary,
        primaryForeground: MemosTokens.darkPrimaryForeground,
        secondary: MemosTokens.darkSecondary,
        secondaryForeground: MemosTokens.darkSecondaryForeground,
        destructive: MemosTokens.darkDestructive,
        destructiveForeground: MemosTokens.darkDestructiveForeground,
        success: MemosTokens.darkSuccess,
        successForeground: MemosTokens.darkSuccessForeground,
        warning: MemosTokens.darkWarning,
        warningForeground: MemosTokens.darkWarningForeground,
        border: MemosTokens.darkBorder,
        input: MemosTokens.darkInput,
        ring: MemosTokens.darkRing,
        overlay: MemosTokens.overlay,
        sidebar: MemosTokens.darkSidebar,
        sidebarForeground: MemosTokens.darkSidebarForeground,
        sidebarAccent: MemosTokens.darkSidebarAccent,
        sidebarAccentForeground: MemosTokens.darkSidebarAccentForeground,
      );

  @override
  MemosThemeTokens copyWith({
    Color? background,
    Color? foreground,
    Color? card,
    Color? cardForeground,
    Color? popover,
    Color? popoverForeground,
    Color? muted,
    Color? mutedForeground,
    Color? accent,
    Color? accentForeground,
    Color? primary,
    Color? primaryForeground,
    Color? secondary,
    Color? secondaryForeground,
    Color? destructive,
    Color? destructiveForeground,
    Color? success,
    Color? successForeground,
    Color? warning,
    Color? warningForeground,
    Color? border,
    Color? input,
    Color? ring,
    Color? overlay,
    Color? sidebar,
    Color? sidebarForeground,
    Color? sidebarAccent,
    Color? sidebarAccentForeground,
  }) =>
      MemosThemeTokens(
        background: background ?? this.background,
        foreground: foreground ?? this.foreground,
        card: card ?? this.card,
        cardForeground: cardForeground ?? this.cardForeground,
        popover: popover ?? this.popover,
        popoverForeground: popoverForeground ?? this.popoverForeground,
        muted: muted ?? this.muted,
        mutedForeground: mutedForeground ?? this.mutedForeground,
        accent: accent ?? this.accent,
        accentForeground: accentForeground ?? this.accentForeground,
        primary: primary ?? this.primary,
        primaryForeground: primaryForeground ?? this.primaryForeground,
        secondary: secondary ?? this.secondary,
        secondaryForeground: secondaryForeground ?? this.secondaryForeground,
        destructive: destructive ?? this.destructive,
        destructiveForeground: destructiveForeground ?? this.destructiveForeground,
        success: success ?? this.success,
        successForeground: successForeground ?? this.successForeground,
        warning: warning ?? this.warning,
        warningForeground: warningForeground ?? this.warningForeground,
        border: border ?? this.border,
        input: input ?? this.input,
        ring: ring ?? this.ring,
        overlay: overlay ?? this.overlay,
        sidebar: sidebar ?? this.sidebar,
        sidebarForeground: sidebarForeground ?? this.sidebarForeground,
        sidebarAccent: sidebarAccent ?? this.sidebarAccent,
        sidebarAccentForeground: sidebarAccentForeground ?? this.sidebarAccentForeground,
      );

  @override
  MemosThemeTokens lerp(ThemeExtension<MemosThemeTokens>? other, double t) {
    if (other is! MemosThemeTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return MemosThemeTokens(
      background: mix(background, other.background),
      foreground: mix(foreground, other.foreground),
      card: mix(card, other.card),
      cardForeground: mix(cardForeground, other.cardForeground),
      popover: mix(popover, other.popover),
      popoverForeground: mix(popoverForeground, other.popoverForeground),
      muted: mix(muted, other.muted),
      mutedForeground: mix(mutedForeground, other.mutedForeground),
      accent: mix(accent, other.accent),
      accentForeground: mix(accentForeground, other.accentForeground),
      primary: mix(primary, other.primary),
      primaryForeground: mix(primaryForeground, other.primaryForeground),
      secondary: mix(secondary, other.secondary),
      secondaryForeground: mix(secondaryForeground, other.secondaryForeground),
      destructive: mix(destructive, other.destructive),
      destructiveForeground: mix(destructiveForeground, other.destructiveForeground),
      success: mix(success, other.success),
      successForeground: mix(successForeground, other.successForeground),
      warning: mix(warning, other.warning),
      warningForeground: mix(warningForeground, other.warningForeground),
      border: mix(border, other.border),
      input: mix(input, other.input),
      ring: mix(ring, other.ring),
      overlay: mix(overlay, other.overlay),
      sidebar: mix(sidebar, other.sidebar),
      sidebarForeground: mix(sidebarForeground, other.sidebarForeground),
      sidebarAccent: mix(sidebarAccent, other.sidebarAccent),
      sidebarAccentForeground: mix(sidebarAccentForeground, other.sidebarAccentForeground),
    );
  }
}

/// 便捷访问：`context.tokens.warning`。
extension MemosTokensX on BuildContext {
  MemosThemeTokens get tokens => Theme.of(this).extension<MemosThemeTokens>()!;
}
