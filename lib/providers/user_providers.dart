import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/user_database.dart';
import '../models/item_ref.dart';

/// 用户数据库（收藏 / 笔记 / 最近查看）单例。
///
/// 默认给 sqflite 实现；测试里用 `overrideWithValue(InMemoryUserStore())`
/// 换成内存实现，这样业务逻辑的测试不需要真实数据库。
final userStoreProvider = Provider<UserStore>((ref) {
  return SqfliteUserStore();
});

/// 收藏集合状态。
///
/// 用 AsyncNotifier 而不是 FutureProvider：收藏会被增删，
/// 需要主动变更 state 以刷新所有监听它的 UI（详情页的星标、收藏页的列表）。
class FavoritesNotifier extends AsyncNotifier<List<UserRecord>> {
  UserStore get _store => ref.read(userStoreProvider);

  @override
  Future<List<UserRecord>> build() => _store.favorites();

  /// 切换收藏状态，返回切换后是否已收藏。
  ///
  /// 详情页的星标按钮需要立刻知道新状态来切图标，
  /// 所以这里返回 bool 而不是让调用方再查一次。
  Future<bool> toggle(ItemRef ref) async {
    final current = state.valueOrNull ?? const <UserRecord>[];
    final isFav = current.any((r) => r.ref == ref);
    if (isFav) {
      await _store.removeFavorite(ref);
    } else {
      await _store.addFavorite(ref);
    }
    state = AsyncData(await _store.favorites());
    return !isFav;
  }

  /// 是否已收藏（读当前 state，不查库）。
  bool contains(ItemRef ref) {
    final current = state.valueOrNull ?? const <UserRecord>[];
    return current.any((r) => r.ref == ref);
  }

  /// 清空收藏。
  Future<void> clear() async {
    await _store.clearFavorites();
    state = const AsyncData(<UserRecord>[]);
  }
}

/// 收藏 provider。
final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<UserRecord>>(
  FavoritesNotifier.new,
);

/// 笔记集合状态。
class NotesNotifier extends AsyncNotifier<List<UserRecord>> {
  UserStore get _store => ref.read(userStoreProvider);

  @override
  Future<List<UserRecord>> build() => _store.notes();

  /// 保存笔记；[content] 去空白后为空则删除该条。
  Future<void> save(ItemRef ref, String content) async {
    await _store.saveNote(ref, content);
    state = AsyncData(await _store.notes());
  }

  /// 删除笔记。
  Future<void> remove(ItemRef ref) async {
    await _store.deleteNote(ref);
    state = AsyncData(await _store.notes());
  }

  /// 取某条的笔记内容（读 state，不查库）。
  String? contentOf(ItemRef ref) {
    final current = state.valueOrNull ?? const <UserRecord>[];
    for (final r in current) {
      if (r.ref == ref) return r.content;
    }
    return null;
  }

  /// 清空全部笔记。
  Future<void> clear() async {
    final current = state.valueOrNull ?? const <UserRecord>[];
    for (final r in current) {
      await _store.deleteNote(r.ref);
    }
    state = const AsyncData(<UserRecord>[]);
  }
}

/// 笔记 provider。
final notesProvider =
    AsyncNotifierProvider<NotesNotifier, List<UserRecord>>(NotesNotifier.new);

/// 最近查看状态。
class RecentNotifier extends AsyncNotifier<List<UserRecord>> {
  UserStore get _store => ref.read(userStoreProvider);

  @override
  Future<List<UserRecord>> build() => _store.recentViews();

  /// 记录一次查看。
  ///
  /// 刻意用 `state.valueOrNull` 而不是 await store 后再 setState：
  /// 这个方法在每个详情页 initState 里调用，必须便宜。
  /// 库里写入是异步的，但 UI 只需要最终一致。
  Future<void> record(ItemRef ref) async {
    await _store.recordView(ref);
    state = AsyncData(await _store.recentViews());
  }

  /// 清空最近查看。
  Future<void> clear() async {
    await _store.clearRecentViews();
    state = const AsyncData(<UserRecord>[]);
  }
}

/// 最近查看 provider。
final recentProvider =
    AsyncNotifierProvider<RecentNotifier, List<UserRecord>>(RecentNotifier.new);
