# tools 使用说明

## 数据流水线

```
SPL 库源码 ──parse_spl.py──┐
                           ├─→ build/base/  ──merge_overlay.py──→ assets/data/
引脚定义.xlsx ─parse_pinout_xlsx.py─┘                    ↑
                                              data/zh_overlay/
```

`build/base/` 是中间产物（英文基础数据），`assets/data/` 是打包进 APK 的最终数据，
`data/zh_overlay/` 是中文补充源文件（不进 APK）。

## 环境

本机 Python 只有 Microsoft Store 占位程序，**必须用 DSH 自带运行时**：

```powershell
$py = "<PYTHON>"
```

解析脚本只用标准库；`parse_pinout_xlsx.py` 额外需要 `openpyxl`（该运行时已装）。
`pypdf` 仅在需要读 PDF 手册时才用，平时不需要。

## 完整重建（改了 SPL 源码或引脚表时）

```powershell
cd <PROJECT_ROOT>

# 1. 解析 SPL（约 20 秒）
& $py tools\parse_spl.py `
    --spl-root "<SPL_ROOT>" `
    --out build\base

# 2. 转换引脚表
& $py tools\parse_pinout_xlsx.py `
    --xlsx "<PINOUT_XLSX>" `
    --out build\base\pinout_f103c8t6.json

# 3. 合并中文（约 5 秒）
& $py tools\merge_overlay.py `
    --base build\base --overlay data\zh_overlay --out assets\data `
    --data-version 1.0.0

# 4. 校验（必须通过）
& $py tools\validate_data.py --data assets\data
```

## 只改中文（最常用）

改了 `data/zh_overlay/` 下的任何文件，**不需要重新解析库**，只跑第 3、4 步即可。

```powershell
& $py tools\merge_overlay.py --base build\base --overlay data\zh_overlay --out assets\data
& $py tools\validate_data.py --data assets\data
```

## 单外设调试

```powershell
# 只解析 GPIO，输出快、便于看日志
& $py tools\parse_spl.py --spl-root "..." --out build\gpio_only --only GPIO
```

## 输出说明

| 文件 | 大小 | 内容 | 何时加载 |
|---|---|---|---|
| `manifest.json` | 0.7 KB | 版本与统计 | 启动时 |
| `peripherals.json` | 63 KB | 外设列表与函数分组 | 启动时 |
| `chips/*.json` | 2 KB | 芯片能力 | 启动时 |
| `functions/*.json` | 每个 6~124 KB | 各外设函数详情 | 进外设页时按需 |
| `symbols.json` | 1.5 MB | API 符号（宏/枚举/结构体） | 启动时（建索引） |
| `registers.json` | 2.7 MB | 寄存器位定义宏 | 用到"寄存器位域展开"时 |
| `pinout_*.json` | 45 KB | 引脚数据 | 进引脚页时 |
| `compile_errors.json` | 31 KB | 编译错误速查 | 进错误页时 |

**符号为什么要拆两个文件**：`stm32f10x.h` 里有 4887 个寄存器位定义宏
（如 `GPIO_CRL_MODE0`），体量大但平时不用。把它们与 2450 个 API 符号分开，
首屏只需读 1.5 MB 的 `symbols.json`，寄存器位定义推迟到真正要看寄存器时再加载。

## 解析器处理的真实情况

这几个坑是实际跑库文件时踩出来的，改脚本时注意别退化：

1. **头文件里没有注释**。ST 的惯例是头文件只放裸原型，`@brief`/`@param`/`@retval`
   全写在 `.c` 文件里对应函数定义的上方。所以注释必须从源文件取
   （`parse_source_comments`）。
2. **分节注释只有 CAN 有**。需求里举例的 `/*  Initialization and Configuration functions ***/`
   在全库 46 个文件里只出现在 `stm32f10x_can.h`（7 条）。其余外设的头文件是平铺的，
   因此用 `SECTION_RULES` 按函数名语义归类。这是**有意的近似**，
   分组标题与 UM0427 手册的章节习惯一致。
3. **单行紧凑 enum**。`typedef enum {RESET = 0, SET = !RESET} FlagStatus, ITStatus;`
   一行里定义了多个类型名。早期用非贪婪 `.*?` 的正则会跨行错配，
   导致 `DISABLE` 丢失、`ITStatus` 变成枚举成员。现在用 `[^{}]*` 限定在花括号内，
   并支持逗号分隔的多个类型名。
4. **ST 源码自身的注释缺陷**（3 处，脚本会告警但不伪造数据）：
   - `FLASH_ReadOutProtection`：注释写 `@param Newstate`，实际参数是 `NewState`
     → 已做大小写不敏感匹配
   - `CAN_OperatingModeRequest`、`I2C_ReadRegister`：只写了第 2 个参数的说明
   - `TIM_ITRxExternalClockConfig`：注释写 `TIM_ITRSource`，实际参数名是
     `TIM_InputTriggerSource`
5. **`stm32f10x.h` 是符号大户**。它定义了 `GPIO_TypeDef`、`FunctionalState`、
   `ENABLE`/`DISABLE`、`GPIOA` 等，这些在函数参数里高频出现。
   不收录它们，详情页的关键词跳转就会断链。它的外设 id 是 `CMSIS`，
   且只解析符号不解析函数（它没有库函数）。

## overlay 编写规则

- `symbols` 里的键**必须**存在于解析产物中，写错会告警。
- `extraSymbols` 用于补充 SPL 源码里没有的符号（工程预定义宏等），会新增条目。
- 空字符串、空数组、`null` 一律视为"未提供"，不覆盖英文基础数据。
  所以只写你关心的字段即可。
- `paramsZh` 按参数名匹配，`membersZh` 按成员名匹配。
- 引脚 overlay 的 `functions` 键格式是 `"引脚号:功能名"`，如 `"42:USART1_TX"`。

### 符号 overlay 为什么拆成多个文件

中文量上来之后（结构体成员、寄存器映射、枚举值各成一类），单文件
`symbols.json` 变得难维护，所以允许 `symbols*.json` **任意多个分文件**：

| 文件 | 内容 |
|---|---|
| `symbols.json` | 骨干：高频宏、`extraSymbols`、少量早期条目 |
| `symbols_<外设>.json` | 各外设的 Init/Config 结构体成员（I2C、SPI、ADC、CAN…） |
| `symbols_regs_*.json` | CMSIS 寄存器映射结构体（`GPIO_TypeDef`、`TIM_TypeDef`…） |
| `symbols_enum_*.json` | 枚举类型成员（`GPIOMode_TypeDef`、`FlagStatus`…） |

`merge_overlay.py` 的 `load_symbol_overlays()` 按文件名排序读入全部
`symbols*.json`，同名符号**逐字段深合并**——所以可以在不同文件里
给同一个符号分别写 `briefZh` 和 `membersZh`，互不覆盖。

新增分文件不需要改脚本，直接放进 `data/zh_overlay/` 即可。

## 已知待办

- **中文覆盖现状**：外设 25/25、函数 488/488（含全部参数）、
  结构体/枚举**成员 663/726（91.3%）**、符号简述 129/7337。
  - 成员里唯一豁免的是 `ETH_TypeDef`：STM32F103 全系没有以太网外设，
    这 63 个寄存器在本型号上永远用不到。
  - 符号简述只覆盖高频符号（其余 2300+ 是未被任何函数引用的位定义宏），
    未覆盖的在界面上显示 ST 英文原文——这是成本收益权衡，不是遗漏。
  - `test/chinese_coverage_test.dart` 会守住上述比例，防止回退。
- 引脚数据已核对（`verified: true`），来源为《STM32F103C8T6引脚定义.xlsx》。
- 编译错误的中文解释由工程经验撰写，非从 ST 文档解析，建议通读复核。

## 其它脚本

| 脚本 | 用途 |
|---|---|
| `release.ps1` | **一键发版**：递增 versionCode/versionName（并同步 `app_info.dart`）→ 构建 → 验签 → 回读 APK 校验版本。升级安装必备。 |
| `sql_check.py` | 用 Python 内置 sqlite3 执行用户数据库的 DDL 与语句，验证 `INSERT OR REPLACE` 去重、最近查看的裁剪语句等。单元测试跑的是内存实现，SQL 本身靠这个脚本兜住。 |
| `make_icons.py` | 用 Pillow 生成 App 图标（5 个密度 + 自适应图标前后景）与启动图。不引入 `flutter_launcher_icons`，避免联网拉包。 |
| `make_keystore.ps1` | 生成 release 签名密钥库并写 `android/key.properties`。注意该文件必须是无 BOM 的 UTF-8（Java 的 `Properties.load` 会把 BOM 当成键名的一部分）。 |

```powershell
$py = "<PYTHON>"
& $py tools\sql_check.py
& $py tools\make_icons.py
```

PowerShell 脚本用 Windows PowerShell 5.1 执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\release.ps1
```

**这两个 .ps1 必须存成带 BOM 的 UTF-8**：Windows PowerShell 5.1 会把
无 BOM 的 UTF-8 当 GBK 读，中文字符串会乱码并导致解析错误
（`key.properties` 则相反，必须**不带** BOM）。

