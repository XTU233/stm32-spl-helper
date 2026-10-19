/// 可收藏 / 可记笔记 / 可记录"最近查看"的条目类型。
///
/// 取值同时用作 sqflite 里 `item_type` 字段的值，改这里等于改库，
/// 所以集中定义一次，禁止在别处写裸字符串。
enum ItemType {
  function('function', '函数'),
  symbol('symbol', '符号'),
  peripheral('peripheral', '外设'),
  pin('pin', '引脚'),
  compileError('compile_error', '编译错误');

  /// 存库用的字符串
  final String raw;

  /// 中文显示名
  final String labelZh;

  const ItemType(this.raw, this.labelZh);

  /// 从存库字符串还原；无法识别时返回 null（脏数据直接忽略，不崩）。
  static ItemType? fromRaw(String raw) {
    for (final t in ItemType.values) {
      if (t.raw == raw) return t;
    }
    return null;
  }
}

/// 条目引用：收藏、笔记、最近查看、搜索结果统一用这个轻量对象传递。
///
/// [title] / [subtitle] 是冗余存储的快照，这样收藏页和笔记页
/// 不必回查 assets 就能直接渲染列表。
class ItemRef {
  /// 条目类型
  final ItemType type;

  /// 条目 id，如 "GPIO_Init"、"GPIO_Mode_Out_PP"、"GPIO"、"30"（引脚号）
  final String id;

  /// 主标题（函数名 / 符号名 / 引脚名 / 外设名）
  final String title;

  /// 副标题（一般是所属外设的中文名）
  final String subtitle;

  const ItemRef({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle = '',
  });

  /// 收藏/笔记表的主键组合串，形如 "function:GPIO_Init"
  String get key => '${type.raw}:$id';

  /// 从主键组合串还原，格式不合法时返回 null。
  static ItemRef? fromKey(String key, {String title = '', String subtitle = ''}) {
    final index = key.indexOf(':');
    if (index <= 0) return null;
    final type = ItemType.fromRaw(key.substring(0, index));
    if (type == null) return null;
    final id = key.substring(index + 1);
    if (id.isEmpty) return null;
    return ItemRef(type: type, id: id, title: title, subtitle: subtitle);
  }

  @override
  bool operator ==(Object other) =>
      other is ItemRef && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => key;
}
