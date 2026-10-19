# 阶段 0 待确认问题

> **2026-01-01 更新：A1 / A2 / A4 / A5 已确认，见文末"已确认"节。**
> A3 与 B 类问题仍按推荐项执行，你可随时推翻。

分两类：**A 类会阻塞阶段 1**，**B 类可以边做边定**（我先按推荐项实现，你随时推翻）。

---

## 已确认（用户答复）

**A1 ✅ SPL 库路径**

- 规范布局（首选）：`<SPL_ROOT>`
  - `Libraries\STM32F10x_StdPeriph_Driver\inc` 23 个 .h，`src` 23 个 .c
  - `Libraries\CMSIS\CM3\CoreSupport`（core_cm3.h/.c）
  - `Libraries\CMSIS\CM3\DeviceSupport\ST\STM32F10x`（stm32f10x.h、system_stm32f10x.h/.c）
  - 已核对 `stm32f10x_gpio.h` 头部 `@version V3.5.0`
- 另一份扁平布局（实测存在）：`D:\32 keil project\2-1stm32工程模版`
  - `Library\` 里 inc+src 合并平铺（46 个文件，无 `STM32F10x_StdPeriph_Driver` 层级）
  - `Start\` 放 CMSIS 与启动文件，`User\` 放 main.c / stm32f10x_conf.h
  - **解析脚本必须自动识别两种布局**，不能硬编码目录层级。

**A2 ✅ 引脚数据来源**

`<PINOUT_XLSX>`，Sheet1，A1:H50。
表头：`引脚号 | 引脚名称 | 类型 | I/O口电平 | 主功能 | 默认复用功能 | 重定义功能`，48 行数据齐全。
该表是 DS5319 Table 5 的转录，字段与本项目模型几乎一一对应：

- `I/O口电平` 列填 `FT` 的即为 5V 容忍 → 直接映射 `fiveVoltTolerant`。
  抽查结果与手册一致：PA0–PA7、PB0、PB1、PB5、PC13/14/15 无 FT；PA8–PA15、PB2–PB15 有 FT。
- `主功能` → `defaultFunction`；`默认复用功能` → `functions[]`（`remapRequired: false`）；
  `重定义功能` → `functions[]`（`remapRequired: true`）。
- PA13/PA14/PA15/PB3/PB4 的主功能列就是 `JTMS/SWDIO`、`JTCK/SWCLK`、`JTDI`、`JTDO`、`NJTRST`
  → 直接映射 `jtagSwd`。
- 仍需人工补的只有中文说明（`defaultFunctionZh` / `notesZh` / `remapNoteZh`），放 `data/zh_overlay/pinout_notes.json`。

`verified` 暂定 `false`，并在 `source` 里写明来源是你的 xlsx + DS5319。你抽查几行确认后改 `true`。

**A4 ✅ Flutter 环境**：你自行安装 Flutter + Android SDK + JDK17。
注意本机现有 `java` 是 Java 8（`C:\Program Files (x86)\Common Files\Oracle\Java\java8path`），
Flutter 构建 Android 需要 JDK 17，装好后 `flutter doctor -v` 应无 Android toolchain 报错。

**A5 ✅ Python 运行时**：用 DSH 自带运行时
`<PYTHON>`（已实测可用）。
脚本只依赖标准库（`re` / `json` / `argparse` / `pathlib` / `dataclasses`），零第三方依赖。
引脚 xlsx 的转换脚本会用到 `openpyxl`（该运行时已装 3.1.5），且只在开发机跑，不进 APP。

---

## A 类：阻塞阶段 1

**A1. SPL 库根目录路径**
`tools/parse_spl.py` 需要一个绝对路径，例如 `D:\STM32\STM32F10x_StdPeriph_Lib_V3.5.0`。
在你给出之前，我只能写脚本骨架，无法验证解析结果。

**A2. 引脚数据的来源（这条最重要）**
✅ 已解决，见上方"已确认"节。

**A3. 编译错误速查的中文内容谁来写**
15 条错误的原因与解决步骤属于通用工程经验（不涉及数据手册数据），我可以直接写。请确认，或由你提供要点。
**当前按"我直接写"执行**，写完你审一遍即可。

**A4. Flutter SDK 当前未安装**
✅ 已确认由你自行安装，见上方"已确认"节。

**A5. Python 解释器**
✅ 已确认使用 DSH 自带运行时，见上方"已确认"节。

---

## B 类：不阻塞，先按推荐项实现

**B1. GPIOD 是否算 C8T6 的可用实例**
✅ 已按引脚表确认：48 行里没有任何 `PDx` 引脚，所以 LQFP48 封装上不存在可用 GPIOD。
`peripheralInstances.GPIO` 定为 `["GPIOA", "GPIOB", "GPIOC"]`。

**B2. 主要工具链**
编译错误条目里 Keil 与 GCC 的写法差别较大。我暂定两类都收，`toolchain` 字段区分，默认展示 Keil（因为你的痛点是 Keil + 标准库）。若你实际用 GCC/Makefile，我调整排序。

**B3. 搜索是否包含内部符号**
`IS_GPIO_*` 这类断言宏有上千个。我暂定：默认搜索**不返回** `visibility: internal` 的符号，但详情页可点进去；搜索页给一个"包含内部断言宏"开关。若你希望默认返回，告诉我。

**B4. 笔记导出格式**
暂定：单个 `.md` 文件，按"外设 → 条目类型 → 条目"三级标题组织，每条笔记带 `> 来源：stm32f10x_gpio.h:168` 定位行。导出走系统分享面板。

**B5. 深色模式的代码高亮配色**
暂定用 Material 3 的 `colorScheme` 派生一套（关键字紫、类型青、注释灰绿、字符串橙、预处理棕），不引入额外主题包。若你有偏好配色，阶段 4 再调。

**B6. 数据版本号策略**
`manifest.dataVersion` 暂定手工维护（`1.0.0` 起，每次重新生成由脚本参数 `--version` 指定），不做自动递增，避免每次跑脚本都产生无意义 diff。

**B7. "最近查看"的去重策略**
暂定：同一 `(类型, id)` 只保留最近一次，重复访问更新 `viewed_at` 并置顶；总数上限 100，超出裁剪最旧的。

---

## 已按需求直接确定、不再询问的项

- 状态管理：Riverpod（理由见 `phase0_architecture.md`）
- 代码高亮：自研轻量 C 词法高亮器，不用 `flutter_highlight`
- 路由：`Navigator 1.0` push/pop，保证关键词跳转能返回原位置
- JSON 序列化：手写 `fromJson`，不用 `build_runner`
- 底部导航：外设 / 搜索 / 收藏 / 工具 / 设置（"工具"下挂引脚速查与编译错误速查，因为需求 5.5 指定了 5 个 Tab，而引脚与错误页是工具性质）
