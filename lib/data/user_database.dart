import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/item_ref.dart';

/// 一条用户数据记录（收藏 / 笔记 / 最近查看）的通用载体。
///
/// 三张表的前几个字段形状一致（item_type + item_id + title + subtitle），
/// 用一个类承载可以少写三套解析代码。
class UserRecord {
  /// 条目类型
  final ItemType type;

  /// 条目 id
  final String id;

  /// 标题快照（冗余存储，列表页不必回查 assets）
  final String title;

  /// 副标题快照（一般是所属外设中文名）
  final String subtitle;

  /// 时间戳（收藏时间 / 笔记更新时间 / 查看时间），毫秒
  final int timestamp;

  /// 笔记正文；收藏与最近查看为 null
  final String? content;

  const UserRecord({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.timestamp,
    this.content,
  });

  /// 转成可跳转的引用
  ItemRef get ref =>
      ItemRef(type: type, id: id, title: title, subtitle: subtitle);

  /// 从数据库行构造。脏数据（item_type 不认识）返回 null，由调用方跳过。
  static UserRecord? fromRow(Map<String, Object?> row) {
    final type = ItemType.fromRaw(row['item_type'] as String? ?? '');
    if (type == null) return null;
    final id = row['item_id'] as String? ?? '';
    if (id.isEmpty) return null;
    return UserRecord(
      type: type,
      id: id,
      title: row['title'] as String? ?? id,
      subtitle: row['subtitle'] as String? ?? '',
      timestamp: (row['created_at'] ??
              row['updated_at'] ??
              row['viewed_at'] ??
              0) as int,
      content: row['content'] as String?,
    );
  }

  @override
  String toString() => '${ref.key}($title)';
}

/// 用户数据仓库的抽象接口。
///
/// 抽出接口是为了可测：sqflite 在单元测试里没有可用的实现
/// （`sqflite_common_ffi` 需要联网拉包，与"完全离线"的项目约束冲突），
/// 所以测试用 [InMemoryUserStore] 这份同接口的内存实现来跑，
/// 业务逻辑（上限裁剪、去重、排序）在两边共用同一套调用约定。
abstract class UserStore {
  /// 收藏：加入（已存在则更新时间与快照）
  Future<void> addFavorite(ItemRef ref);

  /// 收藏：移除
  Future<void> removeFavorite(ItemRef ref);

  /// 收藏：是否已收藏
  Future<bool> isFavorite(ItemRef ref);

  /// 收藏：全部（按收藏时间倒序）
  Future<List<UserRecord>> favorites();

  /// 收藏：清空
  Future<void> clearFavorites();

  /// 笔记：写入或更新（内容为空视为删除）
  Future<void> saveNote(ItemRef ref, String content);

  /// 笔记：取某条
  Future<String?> note(ItemRef ref);

  /// 笔记：全部（按更新时间倒序）
  Future<List<UserRecord>> notes();

  /// 笔记：删除
  Future<void> deleteNote(ItemRef ref);

  /// 最近查看：记录一次（同一条只保留最近一次）
  Future<void> recordView(ItemRef ref);

  /// 最近查看：列表（按时间倒序，上限 [recentLimit]）
  Future<List<UserRecord>> recentViews();

  /// 最近查看：清空
  Future<void> clearRecentViews();

  /// 清理全部用户数据（设置页用）
  Future<void> clearAll();
}

/// 最近查看条数上限。
///
/// 需求定的是 100 条。超出后按时间裁剪，避免表无限增长——
/// 详情页每进一次就写一条，用久了会积累到几万行。
const int recentLimit = 100;

/// 基于 sqflite 的实现。
class SqfliteUserStore implements UserStore {
  /// 数据库文件名
  static const String dbName = 'stm32_spl_user.db';

  /// 当前库版本，改表结构时 +1 并在 [_onUpgrade] 里补迁移
  static const int dbVersion = 1;

  Database? _db;

  /// 打开（或复用）数据库。
  Future<Database> _open() async {
    final cached = _db;
    if (cached != null) return cached;

    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, dbName),
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _db = db;
    return db;
  }

  /// 建表。字段定义与 docs/data_model.md 第 10 节一致。
  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE favorites (
        item_type  TEXT NOT NULL,
        item_id    TEXT NOT NULL,
        title      TEXT NOT NULL,
        subtitle   TEXT,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (item_type, item_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE notes (
        item_type  TEXT NOT NULL,
        item_id    TEXT NOT NULL,
        title      TEXT NOT NULL,
        subtitle   TEXT,
        content    TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (item_type, item_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE recent_views (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        item_type TEXT NOT NULL,
        item_id   TEXT NOT NULL,
        title     TEXT NOT NULL,
        subtitle  TEXT,
        viewed_at INTEGER NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_recent_time ON recent_views(viewed_at DESC)',
    );
    // 同一条目在"最近查看"里只该有一行，用唯一索引兜住，
    // 这样 recordView 可以直接用 REPLACE 而不必先查后写。
    batch.execute(
      'CREATE UNIQUE INDEX idx_recent_item ON recent_views(item_type, item_id)',
    );
    await batch.commit(noResult: true);
  }

  /// 迁移。首版没有历史版本，留好钩子。
  static Future<void> _onUpgrade(Database db, int from, int to) async {
    debugPrint('[UserStore] 数据库从 v$from 升级到 v$to（暂无迁移步骤）');
  }

  @override
  Future<void> addFavorite(ItemRef ref) async {
    final db = await _open();
    await db.insert(
      'favorites',
      <String, Object?>{
        'item_type': ref.type.raw,
        'item_id': ref.id,
        'title': ref.title,
        'subtitle': ref.subtitle,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      // 重复收藏不该报错，也不该产生两行
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> removeFavorite(ItemRef ref) async {
    final db = await _open();
    await db.delete(
      'favorites',
      where: 'item_type = ? AND item_id = ?',
      whereArgs: <Object?>[ref.type.raw, ref.id],
    );
  }

  @override
  Future<bool> isFavorite(ItemRef ref) async {
    final db = await _open();
    final rows = await db.query(
      'favorites',
      columns: <String>['item_id'],
      where: 'item_type = ? AND item_id = ?',
      whereArgs: <Object?>[ref.type.raw, ref.id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<List<UserRecord>> favorites() async {
    final db = await _open();
    final rows = await db.query('favorites', orderBy: 'created_at DESC');
    return _mapRows(rows);
  }

  @override
  Future<void> clearFavorites() async {
    final db = await _open();
    await db.delete('favorites');
  }

  @override
  Future<void> saveNote(ItemRef ref, String content) async {
    // 内容清空视为删除笔记，避免库里留一堆空笔记
    if (content.trim().isEmpty) {
      await deleteNote(ref);
      return;
    }
    final db = await _open();
    await db.insert(
      'notes',
      <String, Object?>{
        'item_type': ref.type.raw,
        'item_id': ref.id,
        'title': ref.title,
        'subtitle': ref.subtitle,
        'content': content,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<String?> note(ItemRef ref) async {
    final db = await _open();
    final rows = await db.query(
      'notes',
      columns: <String>['content'],
      where: 'item_type = ? AND item_id = ?',
      whereArgs: <Object?>[ref.type.raw, ref.id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['content'] as String?;
  }

  @override
  Future<List<UserRecord>> notes() async {
    final db = await _open();
    final rows = await db.query('notes', orderBy: 'updated_at DESC');
    return _mapRows(rows);
  }

  @override
  Future<void> deleteNote(ItemRef ref) async {
    final db = await _open();
    await db.delete(
      'notes',
      where: 'item_type = ? AND item_id = ?',
      whereArgs: <Object?>[ref.type.raw, ref.id],
    );
  }

  @override
  Future<void> recordView(ItemRef ref) async {
    final db = await _open();
    // REPLACE 配合 (item_type,item_id) 唯一索引：同一条目只留最新一行
    await db.insert(
      'recent_views',
      <String, Object?>{
        'item_type': ref.type.raw,
        'item_id': ref.id,
        'title': ref.title,
        'subtitle': ref.subtitle,
        'viewed_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // 裁剪超出上限的旧记录
    await db.rawDelete(
      'DELETE FROM recent_views WHERE id NOT IN ('
      '  SELECT id FROM recent_views ORDER BY viewed_at DESC LIMIT ?'
      ')',
      <Object?>[recentLimit],
    );
  }

  @override
  Future<List<UserRecord>> recentViews() async {
    final db = await _open();
    final rows = await db.query(
      'recent_views',
      orderBy: 'viewed_at DESC',
      limit: recentLimit,
    );
    return _mapRows(rows);
  }

  @override
  Future<void> clearRecentViews() async {
    final db = await _open();
    await db.delete('recent_views');
  }

  @override
  Future<void> clearAll() async {
    final db = await _open();
    final batch = db.batch();
    batch.delete('favorites');
    batch.delete('notes');
    batch.delete('recent_views');
    await batch.commit(noResult: true);
  }

  /// 行 → 记录，跳过脏数据。
  static List<UserRecord> _mapRows(List<Map<String, Object?>> rows) {
    final out = <UserRecord>[];
    for (final r in rows) {
      final rec = UserRecord.fromRow(r);
      if (rec != null) out.add(rec);
    }
    return out;
  }
}

/// 内存实现（测试用）。
///
/// 与 sqflite 实现共用同一套语义约定：去重、按时间倒序、最近查看裁剪到
/// [recentLimit]。测试跑这个实现来验证**业务规则**，
/// 而 SQL 语句本身由 `validate` 之外的手工真机验证覆盖。
class InMemoryUserStore implements UserStore {
  final Map<String, UserRecord> _favorites = <String, UserRecord>{};
  final Map<String, UserRecord> _notes = <String, UserRecord>{};
  final Map<String, UserRecord> _recent = <String, UserRecord>{};

  /// 递增时钟，保证同一毫秒内多次写入也有稳定顺序
  int _clock = 0;
  int _tick() => ++_clock;

  @override
  Future<void> addFavorite(ItemRef ref) async {
    _favorites[ref.key] = UserRecord(
      type: ref.type,
      id: ref.id,
      title: ref.title,
      subtitle: ref.subtitle,
      timestamp: _tick(),
    );
  }

  @override
  Future<void> removeFavorite(ItemRef ref) async => _favorites.remove(ref.key);

  @override
  Future<bool> isFavorite(ItemRef ref) async =>
      _favorites.containsKey(ref.key);

  @override
  Future<List<UserRecord>> favorites() async => _sorted(_favorites.values);

  @override
  Future<void> clearFavorites() async => _favorites.clear();

  @override
  Future<void> saveNote(ItemRef ref, String content) async {
    if (content.trim().isEmpty) {
      _notes.remove(ref.key);
      return;
    }
    _notes[ref.key] = UserRecord(
      type: ref.type,
      id: ref.id,
      title: ref.title,
      subtitle: ref.subtitle,
      timestamp: _tick(),
      content: content,
    );
  }

  @override
  Future<String?> note(ItemRef ref) async => _notes[ref.key]?.content;

  @override
  Future<List<UserRecord>> notes() async => _sorted(_notes.values);

  @override
  Future<void> deleteNote(ItemRef ref) async => _notes.remove(ref.key);

  @override
  Future<void> recordView(ItemRef ref) async {
    _recent[ref.key] = UserRecord(
      type: ref.type,
      id: ref.id,
      title: ref.title,
      subtitle: ref.subtitle,
      timestamp: _tick(),
    );
    // 裁剪：按时间倒序保留前 recentLimit 条
    if (_recent.length > recentLimit) {
      final keep = _sorted(_recent.values)
          .take(recentLimit)
          .map((r) => r.ref.key)
          .toSet();
      _recent.removeWhere((k, _) => !keep.contains(k));
    }
  }

  @override
  Future<List<UserRecord>> recentViews() async =>
      _sorted(_recent.values).take(recentLimit).toList();

  @override
  Future<void> clearRecentViews() async => _recent.clear();

  @override
  Future<void> clearAll() async {
    _favorites.clear();
    _notes.clear();
    _recent.clear();
  }

  static List<UserRecord> _sorted(Iterable<UserRecord> values) {
    final list = values.toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }
}
