# 数据模型定义（阶段 0）

约定：

- 所有 JSON 文件顶层都带 `schemaVersion`（整数），APP 启动时校验，不匹配则在设置页给出提示而不是崩溃。
- 所有 `id` 全局唯一且**稳定**（解析脚本重新生成时不变），收藏 / 笔记 / 最近查看都存 id，不存对象。
- 字段名统一 `lowerCamelCase`；`*En` 为 ST 原文，`*Zh` 为中文（可被 overlay 覆盖）。
- 可空字段在 JSON 中允许缺失或为 `null`，Dart 侧一律用 `lib/utils/json_parse.dart` 的宽松解析兜底，缺字段不会崩。
- `ai` 字段本期恒为 `null`，仅预留。

---

## 1. 总览：文件与模型对应关系

| JSON 文件 | Dart 模型 | 说明 |
|---|---|---|
| `manifest.json` | `DataManifest` / `DataStats` | 版本与统计，启动先读它 |
| `peripherals.json` | `Peripheral` / `PeripheralSection` | 外设 + 函数分组（只存函数 id） |
| `functions/<外设>.json` | `FunctionItem` / `FunctionParam` / `FunctionFlags` | 每个外设一个文件，按需加载 |
| `symbols.json` | `SymbolItem` / `SymbolMember` / `SymbolKind` | 宏 / 枚举值 / 枚举类型 / 结构体 / typedef |
| `pinout_f103c8t6.json` | `PinoutData` / `Pin` / `PinFunction` | 引脚 |
| `compile_errors.json` | `CompileError` / `CompileErrorCategory` / `CodeSnippet` | 编译错误 |
| `chips/stm32f103c8t6.json` | `ChipSpec` | 芯片能力，数据驱动的关键 |
| （聚合） | `SplData` | 内存索引总入口 |

`assets/data/` 的布局与需求第 6 节一致，`functions/` 按外设分文件，原因是：单个外设文件 20–60 KB，首屏只需 `manifest + peripherals + chips`，函数详情按需读取，比一次性读 2 MB 大文件更快，也方便你单独 diff 某个外设。

---

## 2. `manifest.json`

```json
{
  "schemaVersion": 1,
  "dataVersion": "1.0.0",
  "splVersion": "STM32F10x_StdPeriph_Lib_V3.5.0",
  "defaultChipId": "stm32f103c8t6",
  "generatedAt": "2026-01-01T12:00:00+08:00",
  "generator": "tools/parse_spl.py",
  "stats": {
    "peripheralCount": 21,
    "functionCount": 512,
    "symbolCount": 3480,
    "pinCount": 48,
    "compileErrorCount": 14
  },
  "files": {
    "peripherals": "peripherals.json",
    "functions": "functions/",
    "symbols": "symbols.json",
    "pinout": "pinout_f103c8t6.json",
    "compileErrors": "compile_errors.json"
  }
}
```

Dart：`DataManifest`、`DataStats`（`lib/models/manifest.dart`）。

---

## 3. `peripherals.json`

```json
{
  "schemaVersion": 1,
  "peripherals": [
    {
      "id": "GPIO",
      "name": "GPIO",
      "nameZh": "通用输入输出",
      "header": "stm32f10x_gpio.h",
      "source": "stm32f10x_gpio.c",
      "file": "functions/GPIO.json",
      "orderIndex": 1,
      "introZh": "GPIO 是 STM32 最基础的外设……",
      "usageOverviewZh": "使用总览：1) RCC_APB2PeriphClockCmd 使能 GPIOx 时钟；2) 填写 GPIO_InitTypeDef；3) GPIO_Init 配置引脚。",
      "functionCount": 12,
      "symbolCount": 46,
      "tags": ["常用", "基础"],
      "sections": [
        {
          "id": "GPIO#sec1",
          "title": "初始化与配置函数",
          "titleEn": "Initialization and Configuration functions",
          "functionIds": ["GPIO_DeInit", "GPIO_Init", "GPIO_StructInit", "GPIO_ReadInputDataBit"]
        }
      ]
    }
  ]
}
```

字段说明：

- `orderIndex`：首页"按使用频率排序"的依据，由 overlay 的 `peripherals.json` 给出；缺省时按 1000 + 字母序兜底。
- `sections[].titleEn` 取自 ST 头文件里的分节注释原文（如 `/*  Initialization and Configuration functions ***/`），`title` 是它的中文翻译，翻译表在 `data/zh_overlay/peripherals.json` 的 `sectionTitles` 里，可随时改。
- `sections[].functionIds` 与 `functions/<外设>.json` 里的顺序一致，解析脚本保证不漏函数：**任何未落入任何 section 的函数会被自动放进"未分组函数" section 并在日志里告警**。

Dart：`Peripheral`、`PeripheralSection`（`lib/models/peripheral.dart`）。

---

## 4. `functions/<外设>.json`

```json
{
  "schemaVersion": 1,
  "peripheral": "GPIO",
  "functions": [
    {
      "id": "GPIO_Init",
      "name": "GPIO_Init",
      "peripheral": "GPIO",
      "sectionId": "GPIO#sec1",
      "prototype": "void GPIO_Init(GPIO_TypeDef* GPIOx, GPIO_InitTypeDef* GPIO_InitStruct)",
      "returnType": "void",
      "params": [
        {
          "name": "GPIOx",
          "type": "GPIO_TypeDef*",
          "descEn": "where x can be (A..G depending on device used) to select the GPIO peripheral",
          "descZh": "选择 GPIO 端口，取值 GPIOA..GPIOG（C8T6 只有 GPIOA/GPIOB/GPIOC）"
        },
        {
          "name": "GPIO_InitStruct",
          "type": "GPIO_InitTypeDef*",
          "descEn": "pointer to a GPIO_InitTypeDef structure that contains the configuration information for the specified GPIO peripheral.",
          "descZh": "指向配置结构体的指针，其各字段含义见结构体说明"
        }
      ],
      "returnDescEn": "None",
      "returnDescZh": "无返回值",
      "briefEn": "Initializes the GPIOx peripheral according to the specified parameters in the GPIO_InitStruct.",
      "briefZh": "按结构体配置初始化指定 GPIO 端口的一个或多个引脚。",
      "usageZh": "配置引脚方向/模式/速度的唯一入口。调用前必须先使能对应 GPIO 端口时钟，否则配置无效（写入不生效且不报错，是新手最常见的坑）。一次可同时配置多个引脚：把它们的位或起来赋给 GPIO_Pin。",
      "prerequisites": [
        "已调用 RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOx, ENABLE) 使能端口时钟",
        "GPIO_InitStruct 的 GPIO_Pin / GPIO_Mode / GPIO_Speed 三个字段必须全部赋值"
      ],
      "registers": ["GPIOx_CRL", "GPIOx_CRH"],
      "relatedFunctions": ["GPIO_StructInit", "GPIO_DeInit", "RCC_APB2PeriphClockCmd"],
      "remarks": [
        "GPIO_Pin 可以是多个引脚的按位或，一次配置多个引脚时它们共用同一套 Mode/Speed",
        "配置为输入模式时 GPIO_Speed 无效但仍必须赋值"
      ],
      "notesZh": [
        "PA13/PA14 默认被 SWD 占用，配置成普通 GPIO 会导致下载器连不上芯片",
        "复用功能（如 USART1_TX）要配成 GPIO_Mode_AF_PP，配成 Out_PP 收不到数据"
      ],
      "exampleCode": "GPIO_InitTypeDef GPIO_InitStructure;\n\nRCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOC, ENABLE);\n\nGPIO_InitStructure.GPIO_Pin = GPIO_Pin_13;\nGPIO_InitStructure.GPIO_Mode = GPIO_Mode_Out_PP;\nGPIO_InitStructure.GPIO_Speed = GPIO_Speed_50MHz;\nGPIO_Init(GPIOC, &GPIO_InitStructure);",
      "exampleLanguage": "c",
      "symbolRefs": ["GPIO_TypeDef", "GPIO_InitTypeDef", "RCC_APB2Periph_GPIOC", "ENABLE", "GPIO_Pin_13", "GPIO_Mode_Out_PP", "GPIO_Speed_50MHz", "GPIOC"],
      "headerLine": 168,
      "sourceLine": 156,
      "flags": { "deprecated": false, "isrSafe": false, "inline": false, "macroLike": false },
      "ai": null,
      "zhSource": "overlay"
    }
  ]
}
```

字段与需求 4.3 的对应：需求里的字段一个不少；新增/改名的说明如下。

- `sectionId`：函数所属分组，外设详情页折叠分组直接用它归类，不用再遍历。
- `returnDescEn` / `returnDescZh`：需求只写了"返回值说明"，英文原文来自 `@retval`，中文由 overlay 给；`void` 函数自动填"无返回值"。
- `symbolRefs`：**关键词跳转的索引**。解析时扫描原型 + 注释 + 示例代码，抽出所有命中的库内符号名。`KeywordText` 拿它当白名单，避免把 `for`、`int` 之类的普通词渲染成链接，比"全局符号表匹配"更准也更快。
- `flags.isrSafe`：标注该函数能否在中断里调用（如 `GPIO_ReadInputDataBit` 可以，`GPIO_Init` 不建议），首期由 overlay 手工给，解析脚本留 `false`。
- `headerLine` / `sourceLine`：方便你回到 Keil 里对照原文，详情页会显示成"stm32f10x_gpio.h:168"。
- `zhSource`：`base`（无中文补充）/ `overlay`（有中文补充），设置页可用它统计"还有多少函数没写中文"。
- `ai`：预留，本期恒 `null`。结构见第 9 节。

Dart：`FunctionItem`、`FunctionParam`、`FunctionFlags`（`lib/models/function_item.dart`）。

---

## 5. `symbols.json`

`kind` 取值：`macro` | `enum_value` | `enum_type` | `struct` | `typedef`。

### 5.1 宏

```json
{
  "id": "RCC_APB2Periph_GPIOA",
  "name": "RCC_APB2Periph_GPIOA",
  "kind": "macro",
  "peripheral": "RCC",
  "value": "((uint32_t)0x00000004)",
  "valueKind": "expression",
  "briefEn": "",
  "briefZh": "APB2 总线上 GPIOA 端口的时钟使能位。",
  "usageZh": "传给 RCC_APB2PeriphClockCmd 的第一个参数；多个外设可位或。",
  "definedIn": "stm32f10x_rcc.h",
  "definedLine": 45,
  "visibility": "public",
  "functionLike": false,
  "params": [],
  "usedBy": ["RCC_APB2PeriphClockCmd"],
  "relatedSymbols": ["RCC_APB2Periph_GPIOB", "RCC_APB2PeriphClockCmd"],
  "notesZh": ["GPIOA 挂 APB2；USART1 也挂 APB2，USART2/3 挂 APB1，别搞混"],
  "ai": null
}
```

函数式宏（如断言宏）多两个字段：`"functionLike": true, "params": ["PERIPH"]`，并把 `visibility` 设为 `internal`（名字以 `IS_` 开头的断言宏一律 `internal`）。搜索默认降权展示 `internal`，详情页仍可访问。

### 5.2 枚举类型

```json
{
  "id": "GPIOMode_TypeDef",
  "name": "GPIOMode_TypeDef",
  "kind": "enum_type",
  "peripheral": "GPIO",
  "typedefName": "GPIOMode_TypeDef",
  "value": null,
  "members": [
    { "name": "GPIO_Mode_AIN", "type": null, "value": "0x00", "descEn": "Analog input", "descZh": "模拟输入（ADC 采集时必须用这个）", "line": 60 }
  ],
  "briefZh": "GPIO 工作模式枚举，赋给 GPIO_InitTypeDef.GPIO_Mode。",
  "usedBy": ["GPIO_Init"],
  "definedIn": "stm32f10x_gpio.h",
  "definedLine": 58,
  "notesZh": [],
  "ai": null
}
```

枚举值本身也是独立符号（`kind: "enum_value"`），带 `enumType` 指回所属枚举类型名，详情页里点枚举值能跳到自己那页，也能从枚举类型页跳到各值。

### 5.3 结构体 / typedef

```json
{
  "id": "GPIO_InitTypeDef",
  "name": "GPIO_InitTypeDef",
  "kind": "struct",
  "peripheral": "GPIO",
  "typedefName": "GPIO_InitTypeDef",
  "tagName": null,
  "members": [
    { "name": "GPIO_Pin", "type": "uint16_t", "value": null, "descEn": "Specifies the GPIO pins to be configured.", "descZh": "要配置的引脚，取 GPIO_Pin_x 的位或", "line": 100 },
    { "name": "GPIO_Speed", "type": "GPIOSpeed_TypeDef", "value": null, "descEn": "Specifies the speed for the selected pins.", "descZh": "输出速度，取 GPIOSpeed_TypeDef 枚举", "line": 101 },
    { "name": "GPIO_Mode", "type": "GPIOMode_TypeDef", "value": null, "descEn": "Specifies the operating mode for the selected pins.", "descZh": "工作模式，取 GPIOMode_TypeDef 枚举", "line": 102 }
  ],
  "briefZh": "GPIO 初始化结构体，必须先填满再传给 GPIO_Init。",
  "usedBy": ["GPIO_Init", "GPIO_StructInit"],
  "definedIn": "stm32f10x_gpio.h",
  "definedLine": 99,
  "notesZh": ["成员顺序在 SPL 里是 Pin/Speed/Mode，但用字段名赋值就不用管顺序"],
  "ai": null
}
```

`members[].type` 里出现的名字（如 `GPIOSpeed_TypeDef`）在详情页同样可点击跳转。

### 5.4 通用字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` / `name` | string | 符号名，也是跳转用的 key |
| `kind` | string | 见上，未知值解析为 `unknown` 而不是报错 |
| `peripheral` | string | 所属外设 id；`CMSIS`、`CORE`、`MISC` 等非外设头文件的符号归到对应虚拟外设 |
| `value` | string? | 宏的替换体、枚举值的值；结构体/typedef 为 `null` |
| `valueKind` | string? | `hex` / `dec` / `expression` / `string`，仅用于展示着色 |
| `enumType` | string? | 枚举值所属枚举类型名 |
| `memberOf` | string? | 所属结构体/枚举的符号 id（枚举值、结构体成员反查用） |
| `members[]` | array | 结构体成员或枚举成员，字段 `{name, type, value, descEn, descZh, line}` |
| `definedIn` / `definedLine` | string / int | 定义位置 |
| `usedBy[]` | array | **反向索引**：哪些函数的原型/注释/示例里出现过该符号，由 `merge_overlay.py` 统一计算，保证与 `symbolRefs` 双向一致 |
| `relatedSymbols[]` | array | 同族符号，如 `GPIO_Pin_0` → 其它 `GPIO_Pin_x` |
| `visibility` | string | `public` / `internal`（`IS_*` 断言宏为 internal） |
| `functionLike` / `params[]` | bool / array | 函数式宏 |
| `zhSource` | string | 同 FunctionItem |

Dart：`SymbolItem`、`SymbolMember`、`SymbolKind`（`lib/models/symbol_item.dart`）。

---

## 6. `pinout_f103c8t6.json`

**数据来源已确认**：`<PINOUT_XLSX>`（DS5319 Table 5 的转录），
由 `tools/parse_pinout_xlsx.py` 转换，脚本只做搬运不做推测。列到字段的映射：

| xlsx 列 | JSON 字段 | 说明 |
|---|---|---|
| 引脚号 | `number` | 1..48 |
| 引脚名称 | `name` | 取主功能名，如 `PC13-TAMPER-RTC` → `PC13` |
| 类型 | `groups` | `S` + VSS/VSSA → `ground`；`S` + VBAT/VDD/VDDA → `power`；`I/O` 按主功能细分 |
| I/O口电平 | `fiveVoltTolerant` | 值为 `FT` 时为 `true` |
| 主功能 | `defaultFunction` + `jtagSwd` | 主功能是调试信号时同时填 `jtagSwd` |
| 默认复用功能 | `functions[]` | `remapRequired: false`，`/` 拆成多项 |
| 重定义功能 | `functions[]` | `remapRequired: true` |

`groups` 的细分规则（`I/O` 类型时按主功能判断）：
`NRST` → `reset`；`BOOT0` → `boot`；`OSC_IN`/`OSC_OUT` → `osc`；
`JTMS/SWDIO`/`JTCK/SWCLK`/`JTDI`/`JTDO`/`NJTRST` → `debug`（同时加 `gpio`）；
其余 `PXn` → `gpio`。

真实数据示例（三条，直接来自 xlsx，未做任何推测）：

```json
{
  "schemaVersion": 1,
  "chipId": "stm32f103c8t6",
  "package": "LQFP48",
  "source": "STM32F103C8T6引脚定义.xlsx（DS5319 Table 5 转录）",
  "verified": false,
  "verifiedNote": "引脚复用数据来自本地引脚定义表，尚未逐条对照 DS5319。使用前请核对数据手册。",
  "pins": [
    {
      "number": 1,
      "name": "VBAT",
      "groups": ["power"],
      "defaultFunction": "VBAT",
      "defaultFunctionZh": "备份域供电（接纽扣电池或直接接 VDD）",
      "functions": [],
      "fiveVoltTolerant": false,
      "jtagSwd": null,
      "notesZh": "不接电池时直接连 VDD（3.3V）",
      "relatedFunctionIds": []
    },
    {
      "number": 30,
      "name": "PA9",
      "groups": ["gpio"],
      "defaultFunction": "PA9",
      "defaultFunctionZh": "通用 IO；复用为 USART1_TX 时 GPIO_Mode 必须配 GPIO_Mode_AF_PP",
      "functions": [
        { "name": "USART1_TX", "kind": "af", "remapRequired": false, "peripheralId": "USART" },
        { "name": "TIM1_CH2", "kind": "af", "remapRequired": false, "peripheralId": "TIM" },
        { "name": "GPIO", "kind": "gpio", "remapRequired": false, "peripheralId": "GPIO" }
      ],
      "fiveVoltTolerant": true,
      "jtagSwd": null,
      "notesZh": "",
      "relatedFunctionIds": ["GPIO_Init", "GPIO_PinRemapConfig"]
    },
    {
      "number": 34,
      "name": "PA13",
      "groups": ["debug", "gpio"],
      "defaultFunction": "JTMS/SWDIO",
      "defaultFunctionZh": "SWD 数据线，默认被调试口占用",
      "functions": [
        { "name": "PA13", "kind": "gpio", "remapRequired": false, "peripheralId": "GPIO" }
      ],
      "fiveVoltTolerant": true,
      "jtagSwd": "JTMS/SWDIO",
      "notesZh": "配置成普通 GPIO 会导致下载器连不上芯片；确需使用时先 GPIO_PinRemapConfig(GPIO_Remap_SWJ_JTAGDisable, ENABLE) 关闭 JTAG（SWD 仍可用）",
      "relatedFunctionIds": ["GPIO_PinRemapConfig"]
    }
  ]
}
```

- `groups` 是数组，一个引脚可同时属于 `debug` 和 `gpio`。可选值：`power` `ground` `reset` `boot` `gpio` `osc` `debug` `vref` `other`。顶部筛选按它分组。
- `functions[].kind`：`af`（复用功能）/ `gpio`（普通 IO）/ `power` / `ground` / `debug` / `boot` / `osc` / `reset` / `other`。
- `jtagSwd`：被调试口占用时填 `"JTMS/SWDIO"`、`"JTCK/SWCLK"`、`"JTDI"`、`"JTDO"`、`"NJTRST"`，否则 `null`。LQFP48 上只会出现在 34/37/38/39/40 脚。
- `verified` + `verifiedNote`：**未经人工核对时必须是 `false`**，APP 在引脚页顶部显示黄色提示条。这条是需求 5.6 明确要求的。
- 反查"按功能找引脚"由 `SplData.pinout.functionsIndex` 在内存里建 `Map<String, List<Pin>>` 完成，不需要额外数据。

`tools/validate_data.py` 对引脚数据的额外检查：48 个引脚号连续无缺无重；
`jtagSwd` 只允许出现在 34/37/38/39/40 脚；`verified: false` 必须带 `verifiedNote`。

Dart：`PinoutData`、`Pin`、`PinFunction`、`PinGroup`（`lib/models/pin.dart`）。

---

## 7. `compile_errors.json`

```json
{
  "schemaVersion": 1,
  "categories": [
    { "id": "linker", "nameZh": "链接错误", "nameEn": "Linker", "orderIndex": 2 },
    { "id": "build", "nameZh": "编译/头文件错误", "nameEn": "Compiler", "orderIndex": 1 }
  ],
  "errors": [
    {
      "id": "err.undefined_reference",
      "titleZh": "undefined reference to 'xxx'",
      "categoryId": "linker",
      "toolchain": "gcc-arm",
      "messagePatterns": ["undefined reference to", "Undefined symbol"],
      "messageSample": "(.text+0x1c): undefined reference to `GPIO_Init'",
      "explainZh": "链接器找不到函数或变量的实现体，说明只声明了没定义。",
      "causes": ["对应的 stm32f10x_xxx.c 没有加入工程", "函数名拼写错误（如 GPIO_Init 写成 GPIO_init）", "C 文件被 #ifdef 条件编译掉了"],
      "solutions": ["把 Libraries/STM32F10x_StdPeriph_Driver/src/stm32f10x_gpio.c 添加进工程分组", "检查函数名大小写与头文件声明是否一致", "确认 stm32f10x.h 里对应的 xxx 宏已定义（如 USE_STDPERIPH_DRIVER）"],
      "codeSnippets": [
        { "language": "c", "title": "正确写法", "code": "GPIO_Init(GPIOC, &GPIO_InitStructure);" }
      ],
      "relatedFunctionIds": ["GPIO_Init"],
      "relatedSymbolIds": ["USE_STDPERIPH_DRIVER"],
      "relatedPeripheralIds": ["GPIO"],
      "tags": ["链接", "函数未定义", "Keil", "GCC"]
    }
  ]
}
```

需求 5.7 列的 15 条错误，首期全部落到这个结构里（数据在阶段 8 写，结构现在定死）。`messagePatterns` 用于搜索时用"错误原文片段"命中条目。

Dart：`CompileError`、`CompileErrorCategory`、`CodeSnippet`（`lib/models/compile_error.dart`）。

---

## 8. `chips/stm32f103c8t6.json`

```json
{
  "schemaVersion": 1,
  "id": "stm32f103c8t6",
  "name": "STM32F103C8T6",
  "nameZh": "STM32F103C8T6（LQFP48，蓝板/最小系统板常用）",
  "package": "LQFP48",
  "core": "ARM Cortex-M3",
  "flashKb": 64,
  "ramKb": 20,
  "maxFreqMhz": 72,
  "voltageRange": "2.0V ~ 3.6V",
  "dataSheet": "DS5319",
  "pinoutFile": "pinout_f103c8t6.json",
  "supportedPeripherals": ["GPIO", "RCC", "USART", "TIM", "NVIC", "EXTI", "SPI", "I2C", "ADC", "DMA", "BKP", "PWR", "FLASH", "IWDG", "WWDG", "CORTEX", "MISC"],
  "unsupportedPeripherals": ["DAC", "FSMC", "SDIO", "ETH"],
  "unsupportedReasons": {
    "DAC": "C8T6 无 DAC 外设",
    "FSMC": "C8T6 无外部存储控制器",
    "SDIO": "C8T6 无 SDIO",
    "ETH": "C8T6 无以太网 MAC"
  },
  "peripheralInstances": {
    "GPIO": ["GPIOA", "GPIOB", "GPIOC"],
    "USART": ["USART1", "USART2", "USART3"],
    "TIM": ["TIM1", "TIM2", "TIM3", "TIM4"],
    "SPI": ["SPI1", "SPI2"],
    "I2C": ["I2C1", "I2C2"],
    "ADC": ["ADC1", "ADC2"],
    "DMA": ["DMA1"]
  },
  "notesZh": "64KB Flash / 20KB RAM，写满前留意 Flash 溢出错误（见编译错误速查）。",
  "ai": null
}
```

**这是"以后加 F4 只加数据文件"的落点**：新芯片 = `assets/data/chips/stm32f4xxxx.json` + 一份新数据目录 + `manifest.json` 里换 `defaultChipId`，Dart 代码零改动。首页"仅显示 C8T6 支持的外设"开关就是读 `unsupportedPeripherals` 过滤。

`peripheralInstances.GPIO` 已按引脚表确认为 `["GPIOA", "GPIOB", "GPIOC"]`：
xlsx 的 48 行里没有出现任何 `PDx` 引脚，所以 C8T6 的 LQFP48 封装上不存在可用 GPIOD 引脚。
（`notesZh` 里会补一句：SPL 头文件仍有 GPIOD 的定义，但本封装未引出。）

Dart：`ChipSpec`（`lib/models/chip.dart`）。

---

## 9. 预留的 AI 字段

所有 `FunctionItem` / `SymbolItem` / `Pin` / `CompileError` 都有 `ai` 字段，本期恒为 `null`：

```json
{
  "summary": null,
  "qa": [],
  "embeddingRef": null,
  "extra": {}
}
```

Dart：`AiReserved`（`lib/models/ai_reserved.dart`）。`qa` 用 `List<Map<String, dynamic>>` 存，将来加字段不用改模型。

---

## 10. 用户数据（sqflite，不进 assets）

`lib/data/user_database.dart` 阶段 6 实现，表结构现在定下来，避免以后改库：

```sql
CREATE TABLE favorites (
  item_type TEXT NOT NULL,      -- function | symbol | peripheral | pin | compile_error
  item_id   TEXT NOT NULL,
  title     TEXT NOT NULL,      -- 冗余存标题，收藏页不必回查 assets
  subtitle  TEXT,               -- 冗余存"所属外设"
  created_at INTEGER NOT NULL,
  PRIMARY KEY (item_type, item_id)
);

CREATE TABLE notes (
  item_type  TEXT NOT NULL,
  item_id    TEXT NOT NULL,
  content    TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (item_type, item_id)
);

CREATE TABLE recent_views (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  item_type TEXT NOT NULL,
  item_id   TEXT NOT NULL,
  title     TEXT NOT NULL,
  subtitle  TEXT,
  viewed_at INTEGER NOT NULL
);
CREATE INDEX idx_recent_time ON recent_views(viewed_at DESC);

CREATE TABLE search_history (
  keyword    TEXT PRIMARY KEY,
  searched_at INTEGER NOT NULL
);
```

- 最近查看上限 100、搜索历史上限 20：写入后 `DELETE FROM ... WHERE ... NOT IN (SELECT ... ORDER BY ... LIMIT n)` 裁剪。
- 表名与字段用英文；`item_type` 取值与 Dart 的 `ItemType` 枚举一一对应，用同一份常量，避免字符串散落。
- 主题/字号/开关三项存 `shared_preferences`，不进库。

---

## 11. 完整性校验（`tools/validate_data.py`，阶段 1 交付）

合并完成后必须全部通过，任一失败即报错退出（不静默）：

1. `sections[].functionIds` 与 `functions/<外设>.json` 的函数集合互为子集且并集相等（无孤儿函数、无悬空 id）。
2. `relatedFunctions`、`usedBy`、`symbolRefs`、`relatedFunctionIds` 中的每个 id 都能在对应表里找到。
3. 所有 `id` 全局唯一。
4. `params[].type` / `members[].type` 里出现的 `XxxTypeDef` 都有对应符号条目（否则详情页会有死链）。
5. 每个外设的 `functionCount` 与实际数量一致。
6. 引脚号 1..48 连续无缺、无重复；`jtagSwd` 只出现在 PA13/PA14/PA15/PB3/PB4。
7. `verified: false` 的引脚数据必须带 `verifiedNote`。
