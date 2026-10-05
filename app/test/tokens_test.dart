import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peli/ui/tokens/memos_tokens.dart';
import 'package:peli/ui/tokens/oklch.dart';

/// 设计令牌验证。
///
/// 官方主题全部用 **oklch** 定义，Flutter 的 `Color` 是 sRGB，因此必须做精确转换。
/// 这些用例锁住转换的正确性 —— 一旦有人"顺手调一下颜色"，测试会立刻失败。
void main() {
  group('oklch → sRGB 转换', () {
    test('亮度 1 / 色度 0 是纯白', () {
      expect(oklch(1, 0, 0), const Color(0xFFFFFFFF));
    });

    test('亮度 0 / 色度 0 是纯黑', () {
      expect(oklch(0, 0, 0), const Color(0xFF000000));
    });

    test('灰阶（色度 0）三通道相等', () {
      for (final double l in <double>[0.2, 0.4, 0.6, 0.8]) {
        final Color color = oklch(l, 0, 0);
        expect(color.r, closeTo(color.g, 0.005), reason: 'l=$l');
        expect(color.g, closeTo(color.b, 0.005), reason: 'l=$l');
      }
    });

    test('亮度单调递增', () {
      double previous = -1;
      for (final double l in <double>[0.1, 0.3, 0.5, 0.7, 0.9]) {
        final Color color = oklch(l, 0.02, 250);
        final double luminance = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722;
        expect(luminance, greaterThan(previous), reason: 'l=$l');
        previous = luminance;
      }
    });

    test('alpha 被保留', () {
      expect(oklch(0.5, 0.1, 250, 0.5).a, closeTo(0.5, 0.01));
      expect(oklch(0.5, 0.1, 250).a, closeTo(1.0, 0.001));
    });

    test('官方主色（浅色主题）落在深蓝色域', () {
      // web/src/themes/default.css: --primary: oklch(0.45 0.08 250)
      final Color primary = MemosTokens.lightPrimary;
      // hue 250 是蓝色 → 蓝通道应最强、红通道最弱。
      expect(primary.b, greaterThan(primary.r));
      expect(primary.b, greaterThan(primary.g));
      // 亮度 0.45 属中低亮度，不应接近黑或白。
      final double luminance = primary.r * 0.2126 + primary.g * 0.7152 + primary.b * 0.0722;
      expect(luminance, greaterThan(0.05));
      expect(luminance, lessThan(0.35));
    });

    test('官方主色（深色主题）比浅色主题更亮', () {
      double luminance(Color c) => c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722;
      expect(luminance(MemosTokens.darkPrimary), greaterThan(luminance(MemosTokens.lightPrimary)));
    });
  });

  group('主题令牌完整性', () {
    test('浅色与深色的背景/前景对比方向正确', () {
      double luminance(Color c) => c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722;
      // 浅色：背景亮、前景暗
      expect(luminance(MemosTokens.lightBackground), greaterThan(luminance(MemosTokens.lightForeground)));
      // 深色：背景暗、前景亮
      expect(luminance(MemosTokens.darkBackground), lessThan(luminance(MemosTokens.darkForeground)));
    });

    test('浅深主题的 background 不相同（确认真的换主题了）', () {
      expect(MemosTokens.lightBackground, isNot(MemosTokens.darkBackground));
      expect(MemosTokens.lightCard, isNot(MemosTokens.darkCard));
    });

    test('MemosThemeTokens 的 copyWith 与 lerp 可用（ThemeData 动画需要）', () {
      final MemosThemeTokens light = MemosThemeTokens.ofLight();
      final MemosThemeTokens dark = MemosThemeTokens.ofDark();

      final MemosThemeTokens tweaked = light.copyWith(primary: dark.primary);
      expect(tweaked.primary, dark.primary);
      expect(tweaked.background, light.background, reason: '未传的字段应保持不变');

      final MemosThemeTokens mid = light.lerp(dark, 0.5);
      expect(mid.primary, isNot(light.primary));
      expect(mid.primary, isNot(dark.primary));
    });

    test('ColorScheme 组装后 brightness 与关键色正确', () {
      final ColorScheme lightScheme = MemosTokens.lightScheme();
      expect(lightScheme.brightness, Brightness.light);
      expect(lightScheme.primary, MemosTokens.lightPrimary);
      expect(lightScheme.surface, MemosTokens.lightCard);

      final ColorScheme darkScheme = MemosTokens.darkScheme();
      expect(darkScheme.brightness, Brightness.dark);
      expect(darkScheme.primary, MemosTokens.darkPrimary);
    });
  });

  group('几何令牌', () {
    test('圆角体系与官方 --radius 一致（8/6/4/12）', () {
      expect(MemosTokens.radius, 8);
      expect(MemosTokens.radiusLg, 8);
      expect(MemosTokens.radiusMd, 6);
      expect(MemosTokens.radiusSm, 4);
      expect(MemosTokens.radiusXl, 12);
    });

    test('字号与官方 --text-2xs / --text-ui 一致（11/13/16）', () {
      expect(MemosTokens.text2xs, 11);
      expect(MemosTokens.textUi, 13);
      expect(MemosTokens.textBase, 16);
    });

    test('控件尺寸与官方约定一致（icon-sm 24 / icon-compact 28 / icon 32）', () {
      expect(MemosTokens.iconSm, 24);
      expect(MemosTokens.iconCompact, 28);
      expect(MemosTokens.icon, 32);
    });

    test('侧栏宽度范围与官方一致（224–400）', () {
      expect(MemosTokens.sidebarMinWidth, 224);
      expect(MemosTokens.sidebarMaxWidth, 400);
    });

    test('分页大小与官方 DEFAULT_LIST_MEMOS_PAGE_SIZE 一致（16）', () {
      expect(MemosTokens.listPageSize, 16);
    });

    test('折叠阈值与官方 ClampedSection 一致（360 / 420）', () {
      expect(MemosTokens.clampPreviewHeight, 360);
      expect(MemosTokens.clampTriggerHeight, 420);
    });
  });
}
