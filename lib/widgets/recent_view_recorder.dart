import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item_ref.dart';
import '../providers/user_providers.dart';

/// 记录一次「最近查看」。
///
/// 需求 5.5 要求"最近查看"。五个详情页都要记，逻辑完全一样，
/// 所以抽成一个函数，页面里只需在**数据加载成功后**调用一次。
///
/// 两个刻意的设计：
///   - 在数据加载成功后记，不在 initState 里记。否则加载失败的页面
///     （比如 id 写错）也会留下一条点不开的记录，污染"最近查看"。
///   - 不 await。记录是副作用，不该拖慢详情页首帧。
void recordRecentView(WidgetRef ref, ItemRef item) {
  ref.read(recentProvider.notifier).record(item);
}
