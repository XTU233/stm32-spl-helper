import 'chip.dart';
import 'compile_error.dart';
import 'function_item.dart';
import 'item_ref.dart';
import 'manifest.dart';
import 'peripheral.dart';
import 'pin.dart';
import 'symbol_item.dart';

/// 全部静态数据的聚合对象，加载一次后常驻内存。
///
/// 需求要求"JSON 一次性加载进内存，不要每次进页面都重新读文件"，
/// 因此所有查询接口都走这里的 Map 索引，页面只做 O(1) 查找。
class SplData {
  /// 数据版本信息
  final DataManifest manifest;

  /// 当前芯片能力描述
  final ChipSpec chip;

  /// 全部外设（已按 orderIndex 排序）
  final List<Peripheral> peripherals;

  /// 全部函数（跨外设合并）
  final List<FunctionItem> functions;

  /// 全部符号
  final List<SymbolItem> symbols;

  /// 引脚数据
  final PinoutData pinout;

  /// 编译错误数据
  final CompileErrorBundle compileErrors;

  // ---- 以下为内存索引，构造时建立 ----

  /// 外设 id → 外设
  final Map<String, Peripheral> peripheralById;

  /// 函数 id → 函数
  final Map<String, FunctionItem> functionById;

  /// 符号 id → 符号
  final Map<String, SymbolItem> symbolById;

  /// 外设 id → 该外设的函数列表（顺序与头文件一致）
  final Map<String, List<FunctionItem>> functionsByPeripheral;

  /// 外设 id → 该外设的符号列表
  final Map<String, List<SymbolItem>> symbolsByPeripheral;

  /// 符号 id → 会用到它的函数 id 列表（由 symbols 的 usedBy 反向补齐）
  final Map<String, List<String>> functionsUsingSymbol;

  /// 编译错误 id → 错误条目
  final Map<String, CompileError> compileErrorById;

  /// 全部函数 id（含未加载详情的），由外设的 sections 汇总而来。
  ///
  /// 首屏时 peripherals.json 已加载，所以这个集合是完整的；
  /// 而 [functionById] 只包含已按需加载的外设的函数。
  /// 跳转判断必须用这个集合，否则首屏点函数名会被误判为"未收录"。
  final Set<String> _allFunctionIds;

  /// 函数 id → 所属外设 id，用于按需加载时定位文件。
  final Map<String, String> _functionToPeripheral;

  SplData({
    required this.manifest,
    required this.chip,
    required this.peripherals,
    required this.functions,
    required this.symbols,
    required this.pinout,
    required this.compileErrors,
  })  : peripheralById = {for (final p in peripherals) p.id: p},
        functionById = {for (final f in functions) f.id: f},
        symbolById = {for (final s in symbols) s.id: s},
        functionsByPeripheral = _groupFunctions(functions),
        symbolsByPeripheral = _groupSymbols(symbols),
        functionsUsingSymbol = _invertUsedBy(symbols),
        compileErrorById = {for (final e in compileErrors.errors) e.id: e},
        _allFunctionIds = _collectFunctionIds(peripherals),
        _functionToPeripheral = _mapFunctionToPeripheral(peripherals);

  /// 汇总所有外设的函数 id（首屏即可用，不依赖函数详情是否加载）。
  static Set<String> _collectFunctionIds(List<Peripheral> peripherals) {
    final set = <String>{};
    for (final p in peripherals) {
      set.addAll(p.allFunctionIds);
    }
    return set;
  }

  /// 建立 函数 id → 外设 id 的反查表。
  static Map<String, String> _mapFunctionToPeripheral(
    List<Peripheral> peripherals,
  ) {
    final map = <String, String>{};
    for (final p in peripherals) {
      for (final fid in p.allFunctionIds) {
        map.putIfAbsent(fid, () => p.id);
      }
    }
    return map;
  }

  /// 按外设分组函数，组内保持原始顺序（解析时已按头文件顺序写入）。
  static Map<String, List<FunctionItem>> _groupFunctions(
    List<FunctionItem> functions,
  ) {
    final map = <String, List<FunctionItem>>{};
    for (final f in functions) {
      map.putIfAbsent(f.peripheral, () => <FunctionItem>[]).add(f);
    }
    return map;
  }

  /// 按外设分组符号。
  static Map<String, List<SymbolItem>> _groupSymbols(List<SymbolItem> symbols) {
    final map = <String, List<SymbolItem>>{};
    for (final s in symbols) {
      map.putIfAbsent(s.peripheral, () => <SymbolItem>[]).add(s);
    }
    return map;
  }

  /// 把每个符号的 usedBy 反过来存一份，供"哪些函数用了这个符号"快速查询。
  static Map<String, List<String>> _invertUsedBy(List<SymbolItem> symbols) {
    final map = <String, List<String>>{};
    for (final s in symbols) {
      for (final fnId in s.usedBy) {
        map.putIfAbsent(fnId, () => <String>[]).add(s.id);
      }
    }
    return map;
  }

  // ---- 查询接口 ----

  /// 取外设；不存在返回 null。
  Peripheral? peripheral(String id) => peripheralById[id];

  /// 取函数；不存在返回 null。
  FunctionItem? function(String id) => functionById[id];

  /// 取符号；不存在返回 null。
  SymbolItem? symbol(String id) => symbolById[id];

  /// 取某外设的全部函数。
  List<FunctionItem> functionsOf(String peripheralId) =>
      functionsByPeripheral[peripheralId] ?? const <FunctionItem>[];

  /// 取某外设的全部符号。
  List<SymbolItem> symbolsOf(String peripheralId) =>
      symbolsByPeripheral[peripheralId] ?? const <SymbolItem>[];

  /// 判断一个名字是否是库内符号（关键词跳转的白名单判断）。
  bool isKnownSymbol(String name) => symbolById.containsKey(name);

  /// 判断一个名字是否是库内函数。
  ///
  /// 注意：函数详情是按需加载的，[functionById] 里只有已加载外设的函数，
  /// 首屏时可能是空的。所以这里回退查外设的 functionIds——
  /// 那些 id 来自 peripherals.json，首屏必然可用。
  ///
  /// 早先只查 functionById，导致首屏点函数名跳转时报"未收录符号"。
  bool isKnownFunction(String name) {
    if (functionById.containsKey(name)) return true;
    return _allFunctionIds.contains(name);
  }

  /// 判断一个名字是否是已知的库内名字（函数或符号）。
  bool isKnownName(String name) =>
      isKnownFunction(name) || isKnownSymbol(name);

  /// 取函数所属的外设 id（按需加载时用来定位文件）。
  String? peripheralIdOfFunction(String functionId) {
    final f = functionById[functionId];
    if (f != null) return f.peripheral;
    return _functionToPeripheral[functionId];
  }

  /// 该外设是否被当前芯片支持。
  bool isPeripheralSupported(String peripheralId) =>
      chip.supportsPeripheral(peripheralId);

  /// 按 [ItemRef] 取标题，用于最近查看/收藏里补全显示。
  String titleOf(ItemRef ref) {
    switch (ref.type) {
      case ItemType.function:
        return function(ref.id)?.name ?? ref.title;
      case ItemType.symbol:
        return symbol(ref.id)?.name ?? ref.title;
      case ItemType.peripheral:
        return peripheral(ref.id)?.nameZh ?? ref.title;
      case ItemType.pin:
        return pinout.pinByNumber(int.tryParse(ref.id) ?? -1)?.name ?? ref.title;
      case ItemType.compileError:
        return compileErrorById[ref.id]?.titleZh ?? ref.title;
    }
  }

  /// 按 [ItemRef] 取副标题（一般是所属外设中文名）。
  String subtitleOf(ItemRef ref) {
    switch (ref.type) {
      case ItemType.function:
        final f = function(ref.id);
        return f == null ? ref.subtitle : (peripheral(f.peripheral)?.nameZh ?? f.peripheral);
      case ItemType.symbol:
        final s = symbol(ref.id);
        return s == null ? ref.subtitle : (peripheral(s.peripheral)?.nameZh ?? s.peripheral);
      case ItemType.peripheral:
        return '外设';
      case ItemType.pin:
        final p = pinout.pinByNumber(int.tryParse(ref.id) ?? -1);
        return p == null ? ref.subtitle : 'LQFP48 第 ${p.number} 脚';
      case ItemType.compileError:
        final e = compileErrorById[ref.id];
        return e == null ? ref.subtitle : e.toolchain;
    }
  }

  /// 把 [ItemRef] 补全成带标题与副标题的快照（写库前调用）。
  ItemRef enrich(ItemRef ref) => ItemRef(
        type: ref.type,
        id: ref.id,
        title: titleOf(ref),
        subtitle: subtitleOf(ref),
      );
}
