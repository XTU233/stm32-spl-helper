import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pin.dart';
import '../providers/app_providers.dart';
import '../utils/chip_layout.dart';
import '../utils/theme.dart';
import '../widgets/chip_diagram.dart';
import '../widgets/peripheral_pin_view.dart';
import 'function_detail_page.dart';
import 'peripheral_detail_page.dart';
import 'pin_detail_sheet.dart';

/// 引脚速查表的三种视图。
enum PinoutView {
  /// 按外设看引脚："要用 SPI1，接哪几个脚"
  byPeripheral('按外设', Icons.account_tree_outlined),

  /// 封装排布图："这个脚在芯片的什么位置"
  diagram('排布图', Icons.grid_on),

  /// 按引脚号列表："第 30 脚是什么"
  list('列表', Icons.list);

  final String labelZh;
  final IconData icon;

  const PinoutView(this.labelZh, this.icon);
}

/// 引脚速查表。
///
/// 需求 5.6：LQFP48 引脚排布图、可点击查看详情、按功能反查引脚、分组筛选。
///
/// 三种视图回答三个不同的问题：
///   - **按外设**：我想用 SPI1 → 它需要 SCK/MISO/MOSI/NSS，分别在哪几个脚
///   - **排布图**：这个脚在芯片的哪个位置 → 画板子时用
///   - **列表**：第 30 脚是什么 → 手上有板子、看丝印时用
///
/// 默认进"按外设"，因为这是最常见的使用场景（先定外设，再找脚），
/// 而"这是哪个脚"通常已经能从板子上直接看到。
class PinoutPage extends ConsumerStatefulWidget {
  const PinoutPage({super.key});

  @override
  ConsumerState<PinoutPage> createState() => _PinoutPageState();
}

class _PinoutPageState extends ConsumerState<PinoutPage> {
  /// 反查关键词（列表与排布图视图用）
  final TextEditingController _query = TextEditingController();

  /// 当前视图
  PinoutView _view = PinoutView.byPeripheral;

  /// 当前选中的外设实例（"按外设"视图用）
  String? _instance;

  /// 当前选中的功能类别筛选（排布图与列表用）；null 表示不筛选
  PinCategory? _category;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(splDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('引脚速查表'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<PinoutView>(
              segments: <ButtonSegment<PinoutView>>[
                for (final v in PinoutView.values)
                  ButtonSegment<PinoutView>(
                    value: v,
                    label: Text(v.labelZh, style: const TextStyle(fontSize: 12)),
                    icon: Icon(v.icon, size: 16),
                  ),
              ],
              selected: <PinoutView>{_view},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
        ),
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (data) {
          final pinout = data.pinout;
          if (pinout.pins.isEmpty) {
            return const Center(child: Text('引脚数据缺失'));
          }

          return Column(
            children: <Widget>[
              _SourceBanner(pinout: pinout),
              Expanded(child: _buildBody(pinout)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(PinoutData pinout) {
    switch (_view) {
      case PinoutView.byPeripheral:
        return _buildByPeripheral(pinout);
      case PinoutView.diagram:
      case PinoutView.list:
        return _buildPinCentric(pinout);
    }
  }

  // -------------------------------------------------------------------
  // 按外设视图
  // -------------------------------------------------------------------

  Widget _buildByPeripheral(PinoutData pinout) {
    final instances = pinout.peripheralInstances;
    // 首次进入没有选中项时，默认选第一个"真实外设"（跳过"其它"）
    final selected = _instance ??
        instances.firstWhere(
          (i) => i != otherPeripheralId,
          orElse: () => instances.isEmpty ? '' : instances.first,
        );
    final current = pinout.peripheralPinout(selected);

    if (current == null) {
      return const Center(child: Text('没有可用的外设引脚数据'));
    }

    return Column(
      children: <Widget>[
        PeripheralSelector(
          instances: instances,
          selected: selected,
          pinCountOf: (inst) =>
              pinout.peripheralPinout(inst)?.pins.length ?? 0,
          onSelect: (inst) => setState(() => _instance = inst),
        ),
        Expanded(
          child: PeripheralPinView(
            instance: selected,
            pinout: current,
            onTapPin: _openPinDetail,
            // "其它"没有对应外设页，不给跳转入口
            onOpenPeripheral: selected == otherPeripheralId ||
                    current.peripheralId == otherPeripheralId
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PeripheralDetailPage(
                          peripheralId: current.peripheralId,
                        ),
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // 引脚为主的两个视图（排布图 + 列表）：反查 + 分类筛选
  // -------------------------------------------------------------------

  Widget _buildPinCentric(PinoutData pinout) {
    final scheme = Theme.of(context).colorScheme;
    final keyword = _query.text.trim();
    final matched =
        keyword.isEmpty ? const <Pin>[] : pinout.searchByFunction(keyword);
    final categoryPins = _category == null
        ? const <Pin>[]
        : pinout.pins.where((p) => PinCategory.of(p) == _category).toList();

    final Set<int> highlighted;
    if (keyword.isNotEmpty) {
      highlighted = matched.map((p) => p.number).toSet();
    } else if (_category != null) {
      highlighted = categoryPins.map((p) => p.number).toSet();
    } else {
      highlighted = const <int>{};
    }

    final visiblePins = keyword.isNotEmpty
        ? matched
        : (_category == null ? pinout.pins : categoryPins);

    final counts = <PinCategory, int>{};
    for (final p in pinout.pins) {
      final c = PinCategory.of(p);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final present =
        PinCategory.values.where((c) => (counts[c] ?? 0) > 0).toList();

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: '按功能反查引脚，如 USART1_TX、ADC12_IN0、PA9',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: keyword.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 19),
                      onPressed: () {
                        _query.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
        ),
        PinLegend(
          categories: present,
          counts: counts,
          selected: _category,
          onSelect: (c) => setState(() => _category = c),
        ),
        if (keyword.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Row(
              children: <Widget>[
                Icon(
                  matched.isEmpty ? Icons.search_off : Icons.check_circle_outline,
                  size: 15,
                  color: matched.isEmpty ? scheme.error : scheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    matched.isEmpty
                        ? '没有引脚支持「$keyword」'
                        : '「$keyword」可用于 ${matched.length} 个引脚：'
                            '${matched.map((p) => p.name).join('、')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: matched.isEmpty ? scheme.error : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _view == PinoutView.diagram
              ? SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: ChipDiagram(
                          pins: pinout.pins,
                          highlighted: highlighted,
                          onTapPin: _openPinDetail,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DiagramHint(hasHighlight: highlighted.isNotEmpty),
                      const SizedBox(height: 24),
                    ],
                  ),
                )
              : ListView(
                  children: <Widget>[
                    if (visiblePins.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: Text('没有匹配的引脚')),
                      ),
                    for (final pin in visiblePins)
                      _PinTile(pin: pin, onTap: () => _openPinDetail(pin)),
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ],
    );
  }

  void _openPinDetail(Pin pin) {
    showPinDetail(
      context,
      pin.number,
      onOpenFunction: (fid) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FunctionDetailPage(functionId: fid),
        ),
      ),
    );
  }
}

/// 数据来源横幅。已核对时用中性绿，未核对时用警示黄。
class _SourceBanner extends StatelessWidget {
  final PinoutData pinout;

  const _SourceBanner({required this.pinout});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = pinout.verified;
    final color = ok ? const Color(0xFF4C9A5B) : scheme.error;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            ok ? Icons.verified_outlined : Icons.warning_amber_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pinout.verifiedNote.isEmpty
                  ? (ok ? '引脚数据已核对。' : '引脚数据尚未核对，请对照数据手册确认。')
                  : pinout.verifiedNote,
              style: const TextStyle(fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 排布图下方的操作提示。
class _DiagramHint extends StatelessWidget {
  final bool hasHighlight;

  const _DiagramHint({required this.hasHighlight});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        hasHighlight
            ? '高亮的引脚支持当前筛选/反查条件，灰色的不支持。点击任意引脚查看详情。'
            : '引脚号按逆时针排列（左上第 1 脚）。块内小字是引脚号，'
                '主文字是引脚名与第一个复用功能。点击任意引脚查看详情。',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          height: 1.55,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 列表视图里的引脚条目。
class _PinTile extends StatelessWidget {
  final Pin pin;
  final VoidCallback onTap;

  const _PinTile({required this.pin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = PinCategory.of(pin);

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: category.color.withValues(alpha: 0.18),
        child: Text(
          '${pin.number}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: category.color,
          ),
        ),
      ),
      title: Row(
        children: <Widget>[
          Text(
            pin.name,
            style: const TextStyle(
              fontFamilyFallback: AppFonts.mono,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              category.labelZh,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: category.color,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        pin.functions.map((f) => f.name).join(' / '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: pin.jtagSwd != null
          ? Icon(Icons.bug_report, size: 16, color: scheme.error)
          : (pin.fiveVoltTolerant
              ? Text(
                  'FT',
                  style: TextStyle(fontSize: 10, color: scheme.tertiary),
                )
              : null),
      onTap: onTap,
    );
  }
}
