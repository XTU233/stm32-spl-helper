# STM32 库函数助手 v2.0.2

STM32F103C8T6 离线函数查阅工具。本次版本把项目整理为可直接开源发布的状态，
并修正了包名与若干发布相关的问题。

## 下载

| 文件 | 说明 |
|---|---|
| `stm32-helper-2.0.2.apk` | 安装包（57 MB，Android 7.0+） |
| `SHA256SUMS.txt` | 完整性校验值 |

```powershell
# Windows 核对
Get-FileHash .\stm32-helper-2.0.2.apk -Algorithm SHA256
# macOS / Linux
sha256sum stm32-helper-2.0.2.apk
```

安装时需在系统设置里允许「安装未知来源应用」。

> ⚠️ **包名已变更**：`com.example.stm32_spl_helper` → `io.github.laobinghongcha.stm32helper`。
> 因为 Android 把包名视为应用身份，**本次无法覆盖安装旧版**，
> 需要先卸载再安装。卸载会清掉收藏、笔记与浏览记录，介意的话先导出笔记。
> 从本版起包名固定，后续版本可正常覆盖升级。

## 本版内容

### 四库并存

| 库 | 来源 | 函数数 |
|---|---|---:|
| 标准库 SPL | STM32F10x_StdPeriph_Lib V3.5.0 | 488 |
| HAL 库 | STM32CubeF1 V1.8.7 | 801 |
| LL 库 | STM32CubeF1 V1.8.7 | 1137 |
| 寄存器直驱 | CMSIS `stm32f103xb.h` | 472 |

合计 **2898 个函数**，另有 3167 条位域定义、12830 个符号。

### 查阅体验

- **设置 → 函数库** 可自由勾选显示哪些库，至少保留一个
- 外设页顶部有库切换条，每行行尾有库徽标（SPL 蓝 / HAL 绿 / LL 橙 / REG 紫）
- 「使用总览」按调用顺序**逐条分行、序号顶格**，多行正文悬挂缩进对齐
- HAL 与 LL 共 **1938 个函数全部有中文说明**：简述、用法、参数、示例、踩坑提示
- 寄存器库每个条目就是一个寄存器，给位域表（`GPIO_CRL_MODE0 = bits[1:0]`）与读写示例
- HAL 与 SPL 有 12 个同名但成员不同的结构体（如 `GPIO_InitTypeDef`），
  按当前阅读的库显示对应那份，并可一键切换对比

### 修复

- **修复 HAL / LL / 寄存器三个库函数全为 0**
  `pubspec.yaml` 的 assets 声明不递归子目录，导致三个库的数据文件没打进 APK。
  运行时读不到文件、容错成空列表，界面上每个分组都显示 0。
  已补全声明，并新增资源打包回归测试（`test/asset_bundle_test.dart`
  与走 `rootBundle` 的端到端用例）防止复发。
- **修复 HAL 核心结构体被错误去重**
  `GPIO_InitTypeDef`、`USART_InitTypeDef` 等 12 个类型在 HAL 与 SPL 里
  成员布局完全不同，此前 HAL 那份被丢弃，查 HAL 函数时看到的是 SPL 的字段名。
  现用库限定 id 让两份共存，跳转按上下文选对应版本。
- **补收 HAL 核心模块**
  `stm32f1xx_hal.h/.c` 的文件名不符合模块命名规则被漏扫，
  导致 `HAL_Init`、`HAL_Delay`、`HAL_GetTick` 等基础函数搜不到。
- **补收 SDIO 的 LL 层**
  `stm32f1xx_ll_sdmmc.h` 被误判为「本型号无此功能」而跳过，
  实际 F103C8T6 带 SDIO，且该文件定义了 `SDIO_InitTypeDef` 等结构体。
- 引脚详情里的外设名改为显示中文名

### 其他

- 新增 MIT 开源许可（数据部分版权归 ST，详见 `LICENSE`）
- APK 改为通过 GitHub Releases 分发，不再提交进仓库
- 新增构建与发布脚本：`tools/ci_check.ps1`、`tools/make_github_release.ps1`
- 补充 [`docs/RELEASING.md`](docs/RELEASING.md) 与 [`docs/build_env.md`](docs/build_env.md)

## 完全离线

APP 未申请 `INTERNET` 权限，运行时不发起任何网络请求。
所有数据随 APK 内置，断网可用。

## 数据来源

函数原型与英文注释来自 ST 官方的 STM32F10x 标准外设库 V3.5.0 与
STM32CubeF1 V1.8.7，版权归 STMicroelectronics 所有。
引脚数据转录自数据手册 DS5319 Table 5。
中文说明、示例代码与排错经验为本项目整理。
