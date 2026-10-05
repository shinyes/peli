import 'dart:math' as math;
import 'dart:ui' show Color;

/// oklch → sRGB 转换。
///
/// 官方前端的主题令牌全部以 **oklch** 定义（`web/src/themes/default.css`），
/// 而 Flutter 的 `Color` 是 sRGB。直接"目测近似"会带来肉眼可见的偏差，
/// 因此这里按 CSS Color 4 的正式算法做一次精确转换：
/// oklch → oklab → LMS → 线性 sRGB → gamma 编码 sRGB。
///
/// 用法：`oklch(0.45, 0.08, 250, 1)` 对应 CSS 的 `oklch(0.45 0.08 250)`。
Color oklch(
  double lightness,
  double chroma,
  double hueDegrees, [
  double alpha = 1.0,
]) {
  final double hueRadians = hueDegrees * math.pi / 180.0;
  final double a = chroma * math.cos(hueRadians);
  final double b = chroma * math.sin(hueRadians);

  // oklab → LMS'
  final double l_ = lightness + 0.3963377774 * a + 0.2158037573 * b;
  final double m_ = lightness - 0.1055613458 * a - 0.0638541728 * b;
  final double s_ = lightness - 0.0894841775 * a - 1.2914855480 * b;

  // LMS' → LMS（立方）
  final double l = l_ * l_ * l_;
  final double m = m_ * m_ * m_;
  final double s = s_ * s_ * s_;

  // LMS → 线性 sRGB
  final double rLin = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  final double gLin = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  final double bLin = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

  return Color.fromARGB(
    (alpha.clamp(0.0, 1.0) * 255).round(),
    _encode(rLin),
    _encode(gLin),
    _encode(bLin),
  );
}

/// 线性分量 → 8 位 sRGB（含 gamma 编码与裁剪）。
int _encode(double linear) {
  final double clamped = linear.clamp(0.0, 1.0);
  final double srgb = clamped <= 0.0031308
      ? 12.92 * clamped
      : 1.055 * math.pow(clamped, 1 / 2.4) - 0.055;
  return (srgb * 255.0).round().clamp(0, 255);
}
