import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索历史（上限 20 条，最近搜的排最前）。
///
/// 存 shared_preferences 而不是 sqflite：搜索历史就是"最近用过的 20 个短字符串"，
/// 没有查询、没有关联、不需要事务，用键值存储更轻。sqflite 留给阶段 6 的
/// 收藏/笔记/最近查看（那些需要按外设分组、按时间排序、可全文检索）。
///
/// 需求 5.4 要求"搜索历史"；条数上限 20 是避免历史无限增长淹没输入框。
class SearchHistoryStore {
  /// shared_preferences 里的键
  static const String prefsKey = 'search_history_v1';

  /// 历史条数上限
  static const int maxEntries = 20;

  /// 单条关键词的长度上限。搜索框本身不限制输入长度，
  /// 但历史里存一个几百字的串没有意义，还会把 prefs 撑大。
  static const int maxKeywordLength = 64;

  /// 读取历史（最近的在最前）。
  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(prefsKey) ?? const <String>[];
  }

  /// 写入一条历史，返回更新后的完整列表。
  ///
  /// 去重规则：同一个关键词（忽略大小写与首尾空白）只保留最近一次，
  /// 这样反复搜同一个词不会把历史刷满。
  Future<List<String>> add(String keyword) async {
    final k = normalize(keyword);
    if (k.isEmpty) return load();

    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(prefsKey) ?? <String>[];

    // 先移除已存在的同名词（忽略大小写），再插到最前
    list.removeWhere((e) => e.toLowerCase() == k.toLowerCase());
    list.insert(0, k);

    // 超出上限时丢掉最旧的
    final trimmed = list.length > maxEntries
        ? list.sublist(0, maxEntries)
        : list;

    await prefs.setStringList(prefsKey, trimmed);
    return trimmed;
  }

  /// 删除一条历史，返回更新后的列表。
  Future<List<String>> remove(String keyword) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(prefsKey) ?? <String>[];
    list.removeWhere((e) => e.toLowerCase() == keyword.toLowerCase());
    await prefs.setStringList(prefsKey, list);
    return list;
  }

  /// 清空历史。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }

  /// 归一化关键词：去首尾空白、压缩中间连续空白、截断超长输入。
  ///
  /// 压缩空白是因为用户可能粘贴 `GPIO_Init  ` 这种带尾空格的串，
  /// 存原样会让"看起来一样"的两条历史并存。
  static String normalize(String keyword) {
    final collapsed = keyword.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.length <= maxKeywordLength) return collapsed;
    return collapsed.substring(0, maxKeywordLength);
  }
}

/// 搜索历史仓库单例。
final searchHistoryStoreProvider = Provider<SearchHistoryStore>((ref) {
  return SearchHistoryStore();
});

/// 搜索历史状态。
///
/// 用 AsyncNotifier 而不是 FutureProvider：历史会被"添加/删除/清空"修改，
/// 需要主动刷新 UI。AsyncNotifier 的 state 改变会自动通知监听者。
class SearchHistoryNotifier extends AsyncNotifier<List<String>> {
  SearchHistoryStore get _store => ref.read(searchHistoryStoreProvider);

  @override
  Future<List<String>> build() => _store.load();

  /// 记录一次搜索（在用户真正提交/跳转结果时调用，不是每敲一个字都记）。
  Future<void> record(String keyword) async {
    final updated = await _store.add(keyword);
    state = AsyncData(updated);
  }

  /// 删除单条。
  Future<void> remove(String keyword) async {
    final updated = await _store.remove(keyword);
    state = AsyncData(updated);
  }

  /// 清空全部。
  Future<void> clear() async {
    await _store.clear();
    state = const AsyncData(<String>[]);
  }
}

/// 搜索历史 provider。
final searchHistoryProvider =
    AsyncNotifierProvider<SearchHistoryNotifier, List<String>>(
  SearchHistoryNotifier.new,
);
