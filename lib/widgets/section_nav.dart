import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../utils/theme.dart';

/// 详情页里一个区块的锚点。
///
/// 函数详情页有 10 个区块，长函数（如 TIM_Init）滚到底要好几屏。
/// 顶部目录条点一下就能跳过去，这是对真实使用体验影响最大的改动。
class SectionAnchor {
  /// 目录里显示的标题
  final String title;

  /// 目录里显示的图标
  final IconData icon;

  /// 挂在区块 widget 上的 key
  final GlobalKey key;

  const SectionAnchor({
    required this.title,
    required this.icon,
    required this.key,
  });

  /// 滚动到该锚点。
  ///
  /// 用 `Scrollable.ensureVisible` 而不是 `animateTo(offset)`：
  /// 区块高度是不定的（参数个数、示例代码长度都不同），
  /// 自己累积偏移量在内容变化（比如展开寄存器位域）后会失准。
  void scrollTo() {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppDuration.slow,
      curve: Curves.easeOutCubic,
      alignment: 0,
    );
  }

  /// 该区块顶端在滚动容器里的位置（相对内容顶部的像素偏移）。
  ///
  /// 用于判断"用户现在看到的是哪一块"。返回 null 表示该区块
  /// 尚未布局（还没被构建出来）。
  ///
  /// 用 `RenderAbstractViewport.getOffsetToReveal` 而不是读
  /// `renderObject.localToGlobal`：后者给的是屏幕坐标，
  /// 还要自己减去列表顶部的偏移，而且受 AppBar/目录条高度影响，
  /// 算错了高亮就会串位。
  double? offsetInViewport() {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro == null || !ro.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(ro, 0).offset;
  }
}

/// 顶部粘性目录条（横向滚动的 chip）。
///
/// 只在区块数 ≥ 3 时显示——只有两个区块的话目录比内容还长，反而碍事。
class SectionNavBar extends StatefulWidget {
  /// 全部锚点
  final List<SectionAnchor> anchors;

  /// 当前高亮的区块下标；一般由滚动位置决定
  final int? activeIndex;

  const SectionNavBar({
    super.key,
    required this.anchors,
    this.activeIndex,
  });

  @override
  State<SectionNavBar> createState() => _SectionNavBarState();
}

class _SectionNavBarState extends State<SectionNavBar> {
  /// 每个 chip 的 key，用于把高亮项自动滚进可见区
  final Map<int, GlobalKey> _chipKeys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(SectionNavBar old) {
    super.didUpdateWidget(old);
    if (widget.activeIndex != old.activeIndex) {
      _ensureActiveVisible();
    }
  }

  /// 把当前高亮的 chip 滚进可见区。
  ///
  /// 不加这一步的话，页面滚到"示例"时目录条还停在最左边，
  /// 高亮项在屏幕外——用户看不到"我在哪"，高亮就白做了。
  ///
  /// 用 `alignmentPolicy: keepVisibleAtEnd/Start` 而不是 `explicit`：
  /// 已经在可见区内的 chip 不该被强行居中，否则每次滚动
  /// 目录条都会抖一下。
  void _ensureActiveVisible() {
    final i = widget.activeIndex;
    if (i == null) return;
    final ctx = _chipKeys[i]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppDuration.normal,
      curve: Curves.easeOut,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final anchors = widget.anchors;
    if (anchors.length < 3) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF17191D) : const Color(0xFFFCFCFD),
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: 7,
          ),
          itemCount: anchors.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final a = anchors[i];
            final active = widget.activeIndex == i;
            final chipKey = _chipKeys.putIfAbsent(i, () => GlobalKey());
            return KeyedSubtree(
              key: chipKey,
              child: InkWell(
                onTap: a.scrollTo,
                borderRadius: AppRadius.chip,
                child: AnimatedContainer(
                  duration: AppDuration.fast,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: active
                        ? scheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: AppRadius.chip,
                    border: Border.all(
                      color: active
                          ? scheme.primary.withValues(alpha: 0.4)
                          : scheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        a.icon,
                        size: 13,
                      color:
                          active ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      a.title,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
