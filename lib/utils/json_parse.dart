/// JSON 宽松解析工具。
///
/// 设计原则：解析脚本产出的数据难免有个别字段缺失或类型不符，
/// 这里所有取值函数都带兜底值，保证"一条数据的小毛病"不会让整页白屏。
/// 所有模型类都通过本文件读取 JSON。
library;

/// 读字符串；非字符串或缺失时返回 [fallback]。
String asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

/// 读可空字符串；空串按 null 处理，方便 UI 判断"有没有内容"。
String? asStringOrNull(dynamic value) {
  final s = asString(value);
  return s.isEmpty ? null : s;
}

/// 读整数；字符串形式的数字（如 "0x10" 之外的 "12"）也能识别。
int asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// 读可空整数。
int? asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// 读布尔值；字符串 "true"/"false" 也识别。
bool asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) {
    final v = value.toLowerCase();
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
  }
  if (value is num) return value != 0;
  return fallback;
}

/// 读字符串数组；元素里的非字符串会被丢弃，null 元素保留为跳过。
List<String> asStringList(dynamic value) {
  if (value is! List) return const <String>[];
  final result = <String>[];
  for (final item in value) {
    if (item == null) continue;
    final s = item is String ? item : item.toString();
    if (s.isNotEmpty) result.add(s);
  }
  return result;
}

/// 读对象数组，每项转成 `Map<String, dynamic>`。
List<Map<String, dynamic>> asMapList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  final result = <Map<String, dynamic>>[];
  for (final item in value) {
    if (item is Map) result.add(asMap(item));
  }
  return result;
}

/// 把任意 Map 规范化成 `Map<String, dynamic>`（JSON 解码后 key 都是 String）。
Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return <String, dynamic>{};
}

/// 读嵌套对象；缺失时返回空 Map 而不是 null，省掉调用处的判空。
Map<String, dynamic> asObject(dynamic value) => asMap(value);
