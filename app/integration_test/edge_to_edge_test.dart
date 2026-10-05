import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 全面屏（edge-to-edge）适配的真机验证。
///
/// 检查三件事：
/// 1. 窗口确实铺满整块屏幕（`viewPadding` 报告了状态栏/手势条内边距）；
/// 2. `SafeArea` 会把这些内边距转成实际留白（内容不被系统栏/挖孔遮挡）；
/// 3. 应用处于 edge-to-edge 模式（`MediaQuery` 的 padding 非零而不是被系统顶开）。
///
/// 跑法：`flutter test integration_test/edge_to_edge_test.dart -d <deviceId>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('窗口铺满屏幕并报告系统栏内边距', (WidgetTester tester) async {
    late MediaQueryData metrics;
    late EdgeInsets safePadding;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            metrics = MediaQuery.of(context);
            return SafeArea(
              child: Builder(
                builder: (BuildContext context) {
                  // SafeArea 通过 MediaQuery.removePadding 把内边距消掉，
                  // 因此这里读到的 padding 就是"被让出的留白"。
                  safePadding = MediaQuery.of(context).padding;
                  return const SizedBox.expand();
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    // ignore: avoid_print
    print('E2E_LOGICAL_SIZE=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}');
    // ignore: avoid_print
    print('E2E_VIEW_PADDING top=${metrics.viewPadding.top} '
        'bottom=${metrics.viewPadding.bottom} left=${metrics.viewPadding.left} '
        'right=${metrics.viewPadding.right}');
    // ignore: avoid_print
    print('E2E_SAFEAREA_APPLIED top=${safePadding.top} bottom=${safePadding.bottom}');
    // ignore: avoid_print
    print('E2E_DPR=${tester.view.devicePixelRatio}');

    // 1. 状态栏区域必须有内边距（除非设备真的没有状态栏）。
    expect(metrics.viewPadding.top, greaterThan(0),
        reason: '状态栏应当被报告为内边距，否则内容会顶到刘海下面');
    // 2. 全面屏手势条同样应当有内边距。
    expect(metrics.viewPadding.bottom, greaterThan(0),
        reason: '手势条应当被报告为内边距，否则底部内容会被系统手势区覆盖');
    // 3. SafeArea 必须真的把内边距让出来（而不是原样传给子节点）。
    expect(safePadding.top, 0, reason: 'SafeArea 内部应当已经消掉顶部内边距');
    expect(safePadding.bottom, 0, reason: 'SafeArea 内部应当已经消掉底部内边距');
  });

  testWidgets('内容区域尺寸等于屏幕减去安全区（确认真的铺满屏幕）', (WidgetTester tester) async {
    late EdgeInsets viewPadding;
    late Size contentSize;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            viewPadding = MediaQuery.of(context).viewPadding;
            return SafeArea(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  contentSize = constraints.biggest;
                  return const SizedBox.expand();
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Size screen =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    // ignore: avoid_print
    print('E2E_SCREEN=${screen.width.toStringAsFixed(1)}x${screen.height.toStringAsFixed(1)} '
        'CONTENT=${contentSize.width.toStringAsFixed(1)}x${contentSize.height.toStringAsFixed(1)}');

    // 内容高度 = 屏幕高度 − 顶部 − 底部；宽度铺满（手势导航下左右通常为 0）。
    final double expectedHeight =
        screen.height - viewPadding.top - viewPadding.bottom;
    expect(contentSize.height, closeTo(expectedHeight, 1.0),
        reason: '内容高度应当等于屏幕高度减去上下的系统栏内边距');
    expect(contentSize.width, closeTo(screen.width - viewPadding.left - viewPadding.right, 1.0),
        reason: '内容宽度应当铺满（减去左右挖孔内边距）');
  });
}
