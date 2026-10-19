#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SPL V3.5.0 解析器。

输入：STM32F10x 标准外设库根目录（自动识别规范布局与 Keil 扁平布局）
输出：assets/data/ 下的基础 JSON（不含中文，中文由 merge_overlay.py 合并）

用法：
    python parse_spl.py --spl-root "D:\\Keil5 MDK\\32固件库\\STM32F10x_StdPeriph_Lib_V3.5.0" \\
                        --out "D:\\project\\stm32_spl_helper\\build\\base"

设计原则：
1. 只做搬运与结构化，不做任何推测。拿不到就留空并打警告。
2. 所有警告走 stderr 并计数，结尾汇总；异常格式不静默跳过。
3. 输出稳定：同一输入两次运行结果完全一致（键序固定、无时间戳随机性）。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
SPL_VERSION = "STM32F10x_StdPeriph_Lib_V3.5.0"

# ---------------------------------------------------------------------------
# 警告收集
# ---------------------------------------------------------------------------


class WarningLog:
    """收集解析警告，结尾统一输出，避免静默跳过。"""

    def __init__(self) -> None:
        self.items: list[str] = []

    def warn(self, where: str, message: str) -> None:
        self.items.append(f"[{where}] {message}")

    def dump(self) -> None:
        if not self.items:
            print("[parse_spl] 无警告。", file=sys.stderr)
            return
        print(f"\n[parse_spl] 共 {len(self.items)} 条警告：", file=sys.stderr)
        for it in self.items:
            print(f"  ! {it}", file=sys.stderr)


LOG = WarningLog()

# ---------------------------------------------------------------------------
# 常量表
# ---------------------------------------------------------------------------

# 非 stm32f10x_xxx.h 命名的文件对应的虚拟外设 id
SPECIAL_FILES = {
    "misc": ("MISC", "MISC", "嵌套向量中断控制器与 SysTick 配置"),
    # stm32f10x.h 是 CMSIS 器件头文件，定义了所有外设寄存器结构体
    # （GPIO_TypeDef、USART_TypeDef…）、外设基址指针（GPIOA、USART1…）、
    # 通用枚举（FunctionalState、FlagStatus、ErrorStatus）与位定义宏。
    # 这些符号在函数参数里高频出现，必须收录，否则关键词跳转会断链。
    "stm32f10x": ("CMSIS", "CMSIS", "器件头文件：寄存器结构体、外设指针与通用枚举"),
    "system_stm32f10x": ("CMSIS", "CMSIS", "系统时钟初始化"),
    "core_cm3": ("CORTEX", "Cortex-M3", "Cortex-M3 内核外设访问接口"),
}

# 外设 id → 中文名。首期先给全量表，overlay 可覆盖。
PERIPHERAL_NAMES_ZH = {
    "ADC": "模数转换",
    "BKP": "备份寄存器",
    "CAN": "控制器局域网",
    "CEC": "消费电子控制",
    "CRC": "循环冗余校验",
    "DAC": "数模转换",
    "DBGMCU": "调试支持",
    "DMA": "直接存储器访问",
    "EXTI": "外部中断",
    "FLASH": "闪存",
    "FSMC": "灵活静态存储控制器",
    "GPIO": "通用输入输出",
    "I2C": "I2C 总线",
    "IWDG": "独立看门狗",
    "MISC": "内核外设与中断",
    "PWR": "电源控制",
    "RCC": "复位与时钟控制",
    "RTC": "实时时钟",
    "SDIO": "SD 卡接口",
    "SPI": "串行外设接口",
    "TIM": "定时器",
    "USART": "通用同步异步收发器",
    "WWDG": "窗口看门狗",
    "CORTEX": "Cortex-M3 内核",
}

# 首页排序权重：越常用越靠前。未列出的按 1000 + 字母序。
PERIPHERAL_ORDER = {
    "GPIO": 1,
    "RCC": 2,
    "USART": 3,
    "TIM": 4,
    "MISC": 5,
    "NVIC": 6,
    "EXTI": 7,
    "SPI": 8,
    "I2C": 9,
    "ADC": 10,
    "DMA": 11,
    "FLASH": 12,
    "PWR": 13,
    "BKP": 14,
    "IWDG": 15,
    "WWDG": 16,
    "RTC": 17,
    "CRC": 18,
    "DBGMCU": 19,
    "CAN": 20,
}

# C8T6（LQFP48）实际没有的外设
UNSUPPORTED_ON_C8T6 = {
    "DAC": "C8T6 无 DAC 外设",
    "FSMC": "C8T6 无外部存储控制器",
    "SDIO": "C8T6 无 SDIO 接口",
    "CEC": "C8T6 无 CEC 外设",
}

# 分节标题中英对照。SPL 源码里只有 CAN 头文件带分节注释，
# 其余外设按 Doxygen 的 @defgroup 语义与 UM0427 章节习惯归类，
# 归类规则见 build_sections()。这张表只负责把英文标题翻成中文。
SECTION_TITLE_ZH = {
    "Initialization and Configuration functions": "初始化与配置函数",
    "Function used to set the CAN configuration to the default reset state":
        "恢复默认配置",
    "Transmit functions": "发送函数",
    "Receive functions": "接收函数",
    "Operation modes functions": "工作模式函数",
    "Error management functions": "错误管理函数",
    "Interrupts and flags management functions": "中断与标志管理函数",
    "Data transfers functions": "数据传输函数",
    "Data transfer functions": "数据传输函数",
    "Flags management functions": "标志管理函数",
    "Interrupts management functions": "中断管理函数",
    "Power management functions": "电源管理函数",
    "Low Power modes configuration functions": "低功耗模式配置函数",
    "Time and Date configuration functions": "时间与日期配置函数",
    "Configuration functions": "配置函数",
    "Get functions": "读取函数",
    "Command functions": "使能/失能函数",
    "Control functions": "控制函数",
    "Other functions": "其它函数",
}

# 未分组函数的兜底分组标题
FALLBACK_SECTION_TITLE = "其它函数"

# 视为"返回类型"的词
VOID_TYPE = "void"

# 参数方向标记（@param[in] 等）
PARAM_DIR_RE = re.compile(r"^\[(in|out|in,\s*out|out,\s*in)\]\s*", re.I)

# 函数定义（用于 .c 文件里定位实现与关联注释）
# 形如 "void GPIO_Init(GPIO_TypeDef* GPIOx, GPIO_InitTypeDef* GPIO_InitStruct)\n{"
DEF_RE = re.compile(
    r"^[ \t]*([A-Za-z_][\w\s\*]*?)\s+"       # 1 返回类型
    r"([A-Za-z_]\w*)\s*"                      # 2 函数名
    r"\(([^;{)]*)\)\s*"                       # 3 参数表
    r"\{",                                    # 左花括号
    re.M,
)


# ---------------------------------------------------------------------------
# 通用工具
# ---------------------------------------------------------------------------


def read_text(path: Path) -> str:
    """读源码文件。SPL 全为 UTF-8 无 BOM，但容忍 GBK 兜底。"""
    raw = path.read_bytes()
    for enc in ("utf-8", "utf-8-sig", "gbk", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    LOG.warn(path.name, "无法解码，按 latin-1 强制读取")
    return raw.decode("latin-1", errors="replace")


def strip_comments_preserve_lines(text: str) -> str:
    """去掉注释但保留行号（注释内容替换为等量空格）。

    用于定位函数定义体，避免把注释里的括号当成代码。
    """
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            chunk = text[i:j]
            out.append("".join("\n" if c == "\n" else " " for c in chunk))
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def line_of(text: str, index: int) -> int:
    """返回 index 所在的 1-based 行号。"""
    return text.count("\n", 0, index) + 1


def normalize_ws(s: str) -> str:
    """折叠空白为单空格并去首尾。"""
    return re.sub(r"\s+", " ", s).strip()


def split_top_level(s: str, sep: str = ",") -> list[str]:
    """按 sep 切分，忽略括号内的分隔符（参数类型里可能有函数指针）。"""
    parts, depth, cur = [], 0, []
    for ch in s:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if cur:
        parts.append("".join(cur))
    return parts


def value_kind_of(value: str) -> str | None:
    """判断值的形态，用于前端着色。"""
    v = value.strip()
    if not v:
        return None
    if re.fullmatch(r"0[xX][0-9a-fA-F]+", v):
        return "hex"
    if re.fullmatch(r"\d+", v):
        return "dec"
    if re.fullmatch(r'"[^"]*"', v):
        return "string"
    return "expression"


# ---------------------------------------------------------------------------
# Doxygen 注释解析
# ---------------------------------------------------------------------------


@dataclass
class DoxygenBlock:
    """一个 doxygen 注释块的结构化内容。"""

    brief: str = ""
    params: dict[str, str] = field(default_factory=dict)  # 参数名 → 说明
    retval: str = ""
    notes: list[str] = field(default_factory=list)
    warns: list[str] = field(default_factory=list)
    others: list[str] = field(default_factory=list)


# 注释块里各标签的起始位置
_TAG_RE = re.compile(
    r"@(brief|param|retval|return|note|warning|arg|attention)\b", re.I
)


def parse_doxygen(comment_body: str) -> DoxygenBlock:
    """解析一个 doxygen 注释块。

    处理 ST 的典型写法：
        @brief 一句话说明（可能续行）
        @param  NAME: 说明（可能续行，缩进续行属于上一参数）
        @retval 说明
        @note   说明
    """
    block = DoxygenBlock()
    # 去掉每行行首的 "*" 与多余空白，保留缩进层级信息
    lines = []
    for raw in comment_body.splitlines():
        s = raw.strip()
        if s.startswith("*"):
            s = s[1:]
        lines.append(s.rstrip())

    # 按标签切段
    segments: list[tuple[str, list[str]]] = []
    current_tag = ""
    current_lines: list[str] = []
    for line in lines:
        m = _TAG_RE.match(line.strip())
        if m:
            if current_tag or current_lines:
                segments.append((current_tag, current_lines))
            current_tag = m.group(1).lower()
            current_lines = [line.strip()[len(m.group(0)):].strip()]
        else:
            current_lines.append(line)
    if current_tag or current_lines:
        segments.append((current_tag, current_lines))

    for tag, body_lines in segments:
        # 过滤掉分隔线与空行
        text_lines = [
            ln for ln in body_lines
            if ln.strip() and not re.fullmatch(r"[*=\-_]{3,}", ln.strip())
        ]
        if not text_lines:
            continue
        text = normalize_ws(" ".join(text_lines))
        if tag == "brief":
            block.brief = (block.brief + " " + text).strip() if block.brief else text
        elif tag == "param":
            # "NAME: 说明" 或 "NAME 说明"
            m = re.match(r"^([A-Za-z_]\w*)\s*:?\s*(.*)$", text)
            if m:
                name = m.group(1)
                # 方向标记可能出现在名字前
                desc = m.group(2).strip()
                block.params[name] = desc
            else:
                block.others.append(f"@param {text}")
        elif tag in ("retval", "return"):
            block.retval = (block.retval + " " + text).strip() if block.retval else text
        elif tag == "note":
            block.notes.append(text)
        elif tag == "warning":
            block.warns.append(text)
        elif tag == "attention":
            block.others.append(f"@attention {text}")
        elif tag == "arg":
            block.others.append(f"@arg {text}")
        else:
            block.others.append(text)
    return block


def extract_doxygen_blocks(text: str) -> list[tuple[int, int, DoxygenBlock]]:
    """提取所有 /** ... */ 注释块，返回 (起始偏移, 结束偏移, 解析结果)。"""
    result = []
    for m in re.finditer(r"/\*\*(.*?)\*/", text, re.S):
        result.append((m.start(), m.end(), parse_doxygen(m.group(1))))
    return result


# ---------------------------------------------------------------------------
# 头文件解析：函数原型
# ---------------------------------------------------------------------------

# 形如 "void GPIO_Init(GPIO_TypeDef* GPIOx, GPIO_InitTypeDef* GPIO_InitStruct);"
PROTO_RE = re.compile(
    r"^\s*((?:static\s+|inline\s+)*)"          # 1 存储类
    r"([A-Za-z_][\w\s\*]*?)\s+"                # 2 返回类型
    r"([A-Za-z_]\w*)\s*"                       # 3 函数名
    r"\(([^;{)]*)\)\s*;\s*$",                  # 4 参数表
    re.M,
)


@dataclass
class RawFunction:
    """从头文件原型区解析出的函数（未与 .c 合并）。"""

    name: str
    return_type: str
    prototype: str
    params_raw: str
    header_line: int
    section_title_en: str  # 该原型之前最近的分节注释标题，无则为空


@dataclass
class SourceComment:
    """从 .c 文件里提取的函数注释块。

    ST 的惯例是：头文件只放裸原型，@brief/@param/@retval 全写在 .c 里
    对应函数定义的上方。所以注释必须从源文件取。
    """

    name: str
    line: int
    block: DoxygenBlock


def parse_source_comments(source_text: str) -> dict[str, SourceComment]:
    """从 .c 文件提取 函数名 → 其定义上方的 doxygen 注释块。"""
    result: dict[str, SourceComment] = {}
    clean = strip_comments_preserve_lines(source_text)
    comments = extract_doxygen_blocks(source_text)

    for m in DEF_RE.finditer(clean):
        ret_type = normalize_ws(m.group(1))
        name = m.group(2)
        if ret_type in ("", "typedef", "return", "else", "if", "while", "for"):
            continue
        if name in result:
            continue
        # 找该定义之前最近的注释块，且两者之间没有别的函数定义
        best: DoxygenBlock | None = None
        for c_start, c_end, c_block in comments:
            if c_end <= m.start():
                between = clean[c_end:m.start()]
                # 注释与函数体之间只允许有空白
                if between.strip() == "":
                    best = c_block
            else:
                break
        if best is not None:
            result[name] = SourceComment(
                name=name, line=line_of(source_text, m.start()), block=best
            )
    return result


def find_functions_region(header_text: str, periph: str) -> tuple[int, int]:
    """定位头文件里的"导出函数"区域。

    优先用 @defgroup Xxx_Exported_Functions 定位；找不到则退化为
    文件末尾到 #endif 之间的部分。
    """
    m = re.search(r"@defgroup\s+\w*_?Exported_Functions\b", header_text)
    if m:
        start = m.start()
        # 区域结束于 #ifdef __cplusplus 或文件末尾的 #endif
        tail = header_text[start:]
        endm = re.search(r"#ifdef\s+__cplusplus", tail)
        end = start + (endm.start() if endm else len(tail))
        return start, end
    LOG.warn(f"{periph}.h", "未找到 @defgroup *_Exported_Functions，退化为全文扫描")
    return 0, len(header_text)


def parse_header_functions(
    header_text: str, periph: str, header_name: str
) -> list[RawFunction]:
    """从头文件解析函数原型与分节注释。

    注意：ST 的头文件只放裸原型，@brief/@param 全在 .c 里，
    所以这里不解析注释，注释由 parse_source_comments() 从源文件取。
    """
    start, end = find_functions_region(header_text, periph)
    region = header_text[start:end]

    # 收集分节注释：形如 /*  Initialization and Configuration functions *****/
    section_marks: list[tuple[int, str]] = []
    for m in re.finditer(r"/\*([^*][^*]*?)\*{3,}\s*\*/", region):
        title = normalize_ws(m.group(1))
        # 去掉尾部残留的星号与分隔符
        title = re.sub(r"[\s*=\-_]+$", "", title).strip()
        if title and len(title) > 4:
            section_marks.append((m.start(), title))

    functions: list[RawFunction] = []
    for m in PROTO_RE.finditer(region):
        storage, ret_type, name, params_raw = m.groups()
        ret_type = normalize_ws(ret_type)
        # 过滤明显不是函数的东西
        if ret_type in ("", "typedef", "extern"):
            continue
        if name in ("if", "for", "while", "switch", "sizeof", "return"):
            continue

        abs_pos = start + m.start()
        header_line = line_of(header_text, abs_pos)

        # 关联分节标题：取该原型之前最近的分节注释
        section_title_en = ""
        for s_pos, s_title in section_marks:
            if s_pos < m.start():
                section_title_en = s_title
            else:
                break

        prototype = f"{ret_type} {name}({normalize_ws(params_raw)});"
        functions.append(
            RawFunction(
                name=name,
                return_type=ret_type,
                prototype=prototype,
                params_raw=params_raw,
                header_line=header_line,
                section_title_en=section_title_en,
            )
        )
    return functions


# ---------------------------------------------------------------------------
# 头文件解析：符号（宏 / 枚举 / 结构体 / typedef）
# ---------------------------------------------------------------------------

# 单行 #define（含函数式宏）
DEFINE_RE = re.compile(
    r"^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)"      # 1 名字
    r"(\([^)\n]*\))?"                                 # 2 函数式宏参数
    r"[ \t]*(.*?)[ \t]*$",                            # 3 值
    re.M,
)

# 多行 #define 续行
DEFINE_MULTILINE_RE = re.compile(
    r"^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)"
    r"(\([^)\n]*\))?"
    r"((?:[^\n\\]|\\(?:\n|$))*?)(?<!\\)$",
    re.M,
)

# typedef enum { ... } Name;
# 注意：ST 里有单行紧凑写法，如
#   typedef enum {RESET = 0, SET = !RESET} FlagStatus, ITStatus;
# 结尾可能有多个逗号分隔的名字。这里只取第一个作为类型名，
# 并把其余名字也登记为 typedef 别名，避免丢失 ITStatus。
ENUM_RE = re.compile(
    r"typedef\s+enum\s*(?:[A-Za-z_]\w*\s*)?\{([^{}]*)\}\s*"
    r"([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*;",
    re.S,
)

# typedef struct { ... } Name;
STRUCT_RE = re.compile(
    r"typedef\s+struct\s*(?:[A-Za-z_]\w*\s*)?\{([^{}]*)\}\s*"
    r"([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*;",
    re.S,
)

# 普通 typedef：typedef unsigned int foo; / typedef void (*cb)(void);
TYPEDEF_RE = re.compile(
    r"^[ \t]*typedef\s+(?!enum|struct|union)([^;{}]+?)\s*;\s*$", re.M
)

# 枚举成员：NAME = value 或 NAME
ENUM_MEMBER_RE = re.compile(
    r"(?:^|,)\s*([A-Za-z_]\w*)\s*(?:=\s*([^,}]+?))?\s*(?=,|$)", re.S
)

# 结构体成员：type name;  （可能带 /*!< 说明 */）
STRUCT_MEMBER_RE = re.compile(
    r"^\s*([A-Za-z_][\w\s\*]*?)\s+"        # 1 类型
    r"([A-Za-z_]\w*)\s*"                   # 2 成员名
    r"(?:\[[^\]]*\])?\s*;"                 # 可选数组
    r"(?:\s*/\*!?<([^*]*(?:\*(?!/)[^*]*)*)\*/)?",  # 3 说明
    re.M,
)


def parse_defines(text: str, header_name: str) -> list[dict[str, Any]]:
    """解析所有 #define，含多行续行。

    stm32f10x.h 里用形如
        /***  Bit definition for GPIO_CRL register  ***/
    的分节注释把寄存器位定义宏分组。这里跟踪最近的分节注释，
    给每个宏标注 registerName，供"寄存器位域展开"功能使用。
    """
    symbols: list[dict[str, Any]] = []
    seen: set[str] = set()

    # 寄存器分节注释：记录 (行号, 寄存器名)
    reg_marks: list[tuple[int, str]] = []
    for rm in re.finditer(
        r"/\*+\s*Bit definition for ([A-Za-z0-9_]+) register\s*\*+/", text
    ):
        reg_marks.append((line_of(text, rm.start()), rm.group(1)))

    def register_of(line_no: int) -> str | None:
        """取该行之前最近的分节注释所声明的寄存器名。"""
        found = None
        for mark_line, reg_name in reg_marks:
            if mark_line < line_no:
                found = reg_name
            else:
                break
        return found

    # 先把续行拼接成逻辑行，同时记录起始行号
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)(\([^)\n]*\))?[ \t]*(.*)$", line)
        if not m:
            i += 1
            continue
        name, fn_params, value = m.group(1), m.group(2), m.group(3)
        start_line = i + 1
        # 续行
        while value.rstrip().endswith("\\") and i + 1 < len(lines):
            i += 1
            value = value.rstrip()[:-1] + " " + lines[i].strip()
        i += 1

        if name in seen:
            continue
        seen.add(name)

        # 去掉值里的尾随注释
        value_clean = re.sub(r"/\*.*?\*/", "", value, flags=re.S)
        value_clean = re.sub(r"//.*$", "", value_clean).strip()

        # 取同一行（原始行）上的 /*!< 说明
        desc_en = ""
        dm = re.search(r"/\*!?<([^*]*(?:\*(?!/)[^*]*)*)\*/", line)
        if dm:
            desc_en = normalize_ws(dm.group(1))

        symbols.append(
            {
                # id 与 name 同值：id 是全局唯一主键（SymbolItem.fromJson 读的是 id），
                # 缺少 id 会导致运行期 symbolById 索引为空、所有符号都提示"未收录符号"。
                "id": name,
                "name": name,
                "kind": "macro",
                "value": value_clean or None,
                "valueKind": value_kind_of(value_clean),
                "functionLike": fn_params is not None,
                "params": (
                    [p.strip() for p in fn_params[1:-1].split(",") if p.strip()]
                    if fn_params
                    else []
                ),
                "briefEn": desc_en,
                "definedIn": header_name,
                "definedLine": start_line,
                "registerName": register_of(start_line),
                # ST 的断言宏统一视为内部符号
                "visibility": "internal" if name.startswith("IS_") else "public",
            }
        )
    return symbols


def parse_enums(text: str, header_name: str) -> list[dict[str, Any]]:
    """解析 typedef enum。返回枚举类型符号 + 各枚举值符号。

    一个 typedef 可能声明多个名字（如 FlagStatus, ITStatus），
    这里为每个名字都生成一个 enum_type 条目，它们共享同一批成员。
    """
    symbols: list[dict[str, Any]] = []
    for m in ENUM_RE.finditer(text):
        body, names_raw = m.group(1), m.group(2)
        type_names = [n.strip() for n in names_raw.split(",") if n.strip()]
        if not type_names:
            continue
        base_line = line_of(text, m.start())
        brief = _brief_before(text, m.start())

        # 枚举成员
        members: list[dict[str, Any]] = []
        body_offset = m.start(1)
        for em in ENUM_MEMBER_RE.finditer(body):
            member_name = em.group(1)
            if not member_name or member_name in ("typedef",):
                continue
            value = normalize_ws(em.group(2)) if em.group(2) else None
            m_line = line_of(text, body_offset + em.start(1))
            # 成员行尾的 /*!< 说明 */
            line_end = text.find("\n", body_offset + em.end())
            line_text = text[
                body_offset + em.start(): line_end if line_end > 0 else len(text)
            ]
            desc_en = ""
            dm = re.search(r"/\*!?<([^*]*(?:\*(?!/)[^*]*)*)\*/", line_text)
            if dm:
                desc_en = normalize_ws(dm.group(1))
            members.append(
                {
                    "name": member_name,
                    "type": None,
                    "value": value,
                    "descEn": desc_en,
                    "line": m_line,
                }
            )

        # 每个类型名各生成一条 enum_type
        for type_name in type_names:
            symbols.append(
                {
                    "id": type_name,
                    "name": type_name,
                    "kind": "enum_type",
                    "typedefName": type_name,
                    "members": [dict(x) for x in members],
                    "definedIn": header_name,
                    "definedLine": base_line,
                    "visibility": "public",
                    "briefEn": brief,
                }
            )

        # 枚举值挂在第一个类型名下（作为 enumType）
        primary = type_names[0]
        for mem in members:
            symbols.append(
                {
                    "id": mem["name"],
                    "name": mem["name"],
                    "kind": "enum_value",
                    "value": mem["value"],
                    "valueKind": value_kind_of(mem["value"] or ""),
                    "enumType": primary,
                    "memberOf": primary,
                    "definedIn": header_name,
                    "definedLine": mem["line"],
                    "visibility": "public",
                    "briefEn": mem["descEn"],
                }
            )
    return symbols


def parse_structs(text: str, header_name: str) -> list[dict[str, Any]]:
    """解析 typedef struct。一个 typedef 可声明多个名字。"""
    symbols: list[dict[str, Any]] = []
    for m in STRUCT_RE.finditer(text):
        body, names_raw = m.group(1), m.group(2)
        type_names = [n.strip() for n in names_raw.split(",") if n.strip()]
        if not type_names:
            continue
        base_line = line_of(text, m.start())
        brief = _brief_before(text, m.start())

        members = []
        body_offset = m.start(1)
        for sm in STRUCT_MEMBER_RE.finditer(body):
            mtype = normalize_ws(sm.group(1))
            mname = sm.group(2)
            if mtype in ("typedef", "struct", "union"):
                continue
            desc_en = normalize_ws(sm.group(3)) if sm.group(3) else ""
            members.append(
                {
                    "name": mname,
                    "type": mtype,
                    "value": None,
                    "descEn": desc_en,
                    "line": line_of(text, body_offset + sm.start()),
                }
            )
        for type_name in type_names:
            symbols.append(
                {
                    "id": type_name,
                    "name": type_name,
                    "kind": "struct",
                    "typedefName": type_name,
                    "members": [dict(x) for x in members],
                    "definedIn": header_name,
                    "definedLine": base_line,
                    "visibility": "public",
                    "briefEn": brief,
                }
            )
    return symbols


def parse_plain_typedefs(text: str, header_name: str) -> list[dict[str, Any]]:
    """解析非 enum/struct 的 typedef。"""
    symbols: list[dict[str, Any]] = []
    for m in TYPEDEF_RE.finditer(text):
        decl = normalize_ws(m.group(1))
        # 取最后一个标识符作为名字
        nm = re.search(r"([A-Za-z_]\w*)\s*$", decl)
        if not nm:
            continue
        name = nm.group(1)
        symbols.append(
            {
                "id": name,
                "name": name,
                "kind": "typedef",
                "value": decl,
                "valueKind": "expression",
                "definedIn": header_name,
                "definedLine": line_of(text, m.start()),
                "visibility": "public",
                "briefEn": _brief_before(text, m.start()),
            }
        )
    return symbols


def _brief_before(text: str, index: int) -> str:
    """取 index 之前最近的 /** @brief ... */ 内容。"""
    window_start = max(0, index - 600)
    window = text[window_start:index]
    blocks = list(re.finditer(r"/\*\*(.*?)\*/", window, re.S))
    if not blocks:
        return ""
    body = blocks[-1].group(1)
    # 只取 @brief 部分
    bm = re.search(r"@brief\s+(.*?)(?=@\w|\Z)", body, re.S)
    if bm:
        return normalize_ws(re.sub(r"^\s*\*", "", bm.group(1), flags=re.M))
    # 无 @brief 时取正文第一段
    txt = re.sub(r"^\s*\*", "", body, flags=re.M)
    txt = re.sub(r"@\w+", "", txt)
    return normalize_ws(txt)[:200]


# ---------------------------------------------------------------------------
# 源文件解析：函数定义（用于取行号与确认实现存在）
# ---------------------------------------------------------------------------


def parse_source_definitions(source_text: str) -> dict[str, int]:
    """返回 函数名 → 定义行号。"""
    clean = strip_comments_preserve_lines(source_text)
    result: dict[str, int] = {}
    for m in DEF_RE.finditer(clean):
        ret_type = normalize_ws(m.group(1))
        name = m.group(2)
        if ret_type in ("", "typedef", "return", "else", "if", "while", "for"):
            continue
        if name in result:
            continue
        result[name] = line_of(source_text, m.start())
    return result


# ---------------------------------------------------------------------------
# 分组构建
# ---------------------------------------------------------------------------

# 按函数名归类分组。规则按顺序匹配，第一条命中的生效。
#
# 说明：SPL 源码里只有 CAN 头文件带分节注释，其余外设的头文件是平铺的。
# 这里按函数名的语义归类，分组标题与 UM0427 手册的章节习惯保持一致，
# 归类只影响"列表怎么分组显示"，不改变任何数据内容。
SECTION_RULES: list[tuple[re.Pattern[str], str, str]] = [
    # ---- 中断与标志 ----
    (re.compile(r"_(ITConfig|GetITStatus|ClearITPendingBit)$"),
     "Interrupts management functions", "中断管理函数"),
    (re.compile(r"_(GetFlagStatus|ClearFlag)$"),
     "Flags management functions", "标志管理函数"),
    # ---- 读取类（放在写入类之前，避免 Read/Write 混淆）----
    (re.compile(r"_Read"), "Data reading functions", "数据读取函数"),
    (re.compile(r"_Get"), "Data reading functions", "数据读取函数"),
    (re.compile(r"_Receive"), "Data receiving functions", "数据接收函数"),
    (re.compile(r"_Is"), "Status checking functions", "状态查询函数"),
    # ---- 发送/写入类 ----
    (re.compile(r"_(Send|Transmit)"), "Data transmitting functions",
     "数据发送函数"),
    (re.compile(r"_(Set|Reset|Write)"), "Data writing functions", "数据写入函数"),
    # ---- 使能与控制 ----
    # 不锚定下划线：GPIO_EventOutputCmd、TIM_Cmd 都要命中
    (re.compile(r"Cmd$"), "Command functions", "使能/失能函数"),
    # ---- 初始化与配置 ----
    # 不锚定下划线：GPIO_AFIODeInit 这类带前缀的也要命中
    (re.compile(r"DeInit$"), "Initialization and Configuration functions",
     "初始化与配置函数"),
    (re.compile(r"_(Init|StructInit)$"),
     "Initialization and Configuration functions", "初始化与配置函数"),
    # GPIO_PinLockConfig / GPIO_EXTILineConfig / GPIO_ETH_MediaInterfaceConfig
    (re.compile(r"Config$"), "Configuration functions", "配置函数"),
]


def build_sections(
    periph: str, functions: list[RawFunction]
) -> list[dict[str, Any]]:
    """为外设构建函数分组。

    优先用头文件里真实存在的分节注释（只有 CAN 有）；
    没有时按 SECTION_RULES 依函数名前缀归类；
    仍归不进去的放进"其它函数"。
    """
    groups: list[tuple[str, str, list[str]]] = []
    index: dict[str, int] = {}

    def ensure(title_en: str, title_zh: str) -> int:
        key = title_en or title_zh
        if key not in index:
            index[key] = len(groups)
            groups.append((title_zh, title_en, []))
        return index[key]

    for fn in functions:
        if fn.section_title_en:
            title_en = fn.section_title_en
            title_zh = SECTION_TITLE_ZH.get(title_en, title_en)
            gi = ensure(title_en, title_zh)
        else:
            gi = -1
            for pattern, title_en, title_zh in SECTION_RULES:
                if pattern.search(fn.name):
                    gi = ensure(title_en, title_zh)
                    break
            if gi < 0:
                gi = ensure("", FALLBACK_SECTION_TITLE)
        groups[gi][2].append(fn.name)

    sections = []
    for i, (title_zh, title_en, fn_ids) in enumerate(groups, 1):
        sections.append(
            {
                "id": f"{periph}#sec{i}",
                "title": title_zh,
                "titleEn": title_en or None,
                "functionIds": fn_ids,
            }
        )
    return sections


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------


@dataclass
class Layout:
    """SPL 目录布局。支持规范布局与 Keil 扁平布局。"""

    inc_dirs: list[Path]
    src_dirs: list[Path]
    root: Path

    @staticmethod
    def detect(root: Path) -> "Layout":
        inc, src = [], []
        # 规范布局
        base = root / "Libraries" / "STM32F10x_StdPeriph_Driver"
        if (base / "inc").is_dir():
            inc.append(base / "inc")
            src.append(base / "src")
        cmsis = root / "Libraries" / "CMSIS" / "CM3"
        if (cmsis / "CoreSupport").is_dir():
            inc.append(cmsis / "CoreSupport")
        dev = cmsis / "DeviceSupport" / "ST" / "STM32F10x"
        if dev.is_dir():
            inc.append(dev)
            src.append(dev)
        # Keil 扁平布局：任何含 stm32f10x_gpio.h 的目录
        if not inc:
            for p in root.rglob("stm32f10x_gpio.h"):
                inc.append(p.parent)
                if (p.parent / "stm32f10x_gpio.c").exists():
                    src.append(p.parent)
                break
            for name in ("core_cm3.h", "stm32f10x.h"):
                for p in root.rglob(name):
                    if p.parent not in inc:
                        inc.append(p.parent)
                    if (p.parent / name.replace(".h", ".c")).exists() and p.parent not in src:
                        src.append(p.parent)
                    break
        if not inc:
            raise SystemExit(f"在 {root} 下找不到 STM32F10x 标准库，请检查路径。")
        return Layout(inc_dirs=inc, src_dirs=src, root=root)


def peripheral_id_from_stem(stem: str) -> str:
    """stm32f10x_gpio → GPIO；misc → MISC。"""
    if stem in SPECIAL_FILES:
        return SPECIAL_FILES[stem][0]
    m = re.match(r"stm32f10x_(\w+)", stem)
    if m:
        return m.group(1).upper()
    return stem.upper()


def collect_headers(layout: Layout) -> dict[str, Path]:
    """外设 id → 头文件路径。"""
    result: dict[str, Path] = {}
    for d in layout.inc_dirs:
        for p in sorted(d.glob("*.h")):
            stem = p.stem
            if stem.startswith("stm32f10x_") or stem in SPECIAL_FILES:
                pid = peripheral_id_from_stem(stem)
                result.setdefault(pid, p)
    return result


def is_symbols_only(periph: str) -> bool:
    """判断该"外设"是否只提供符号、没有库函数。

    stm32f10x.h 里只有寄存器结构体与通用枚举，没有 GPIO_Init 这类库函数，
    所以不解析它的函数区，但仍要解析它的符号。
    """
    return periph in ("CMSIS", "CORTEX")


def collect_sources(layout: Layout) -> dict[str, Path]:
    """外设 id → 源文件路径。"""
    result: dict[str, Path] = {}
    for d in layout.src_dirs:
        for p in sorted(d.glob("*.c")):
            stem = p.stem
            if stem.startswith("stm32f10x_") or stem in SPECIAL_FILES:
                pid = peripheral_id_from_stem(stem)
                result.setdefault(pid, p)
    return result


def parse_peripheral(
    periph: str,
    header_path: Path,
    source_path: Path | None,
    symbols_global: dict[str, dict[str, Any]],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """解析一个外设，返回 (外设条目, 函数列表)。"""
    header_text = read_text(header_path)
    header_name = header_path.name

    # CMSIS 器件头文件（stm32f10x.h）只提供符号，没有库函数
    symbols_only = is_symbols_only(periph)
    raw_funcs = (
        [] if symbols_only
        else parse_header_functions(header_text, periph, header_name)
    )

    # 源文件里的定义行号与函数注释（ST 把 @brief/@param 写在 .c 里）
    src_lines: dict[str, int] = {}
    src_comments: dict[str, SourceComment] = {}
    source_name = ""
    if source_path and source_path.exists():
        source_name = source_path.name
        source_text = read_text(source_path)
        src_lines = parse_source_definitions(source_text)
        src_comments = parse_source_comments(source_text)

    # 构建函数条目
    functions: list[dict[str, Any]] = []
    for rf in raw_funcs:
        # 只保留在 .c 里有实现的（头文件里的宏式"函数"除外）
        source_line = src_lines.get(rf.name, 0)
        if source_path and not source_line:
            LOG.warn(
                f"{header_name}:{rf.header_line}",
                f"{rf.name} 在 {source_name or '源文件'} 中找不到实现，仍收录但 sourceLine=0",
            )

        # 取源文件里的注释块
        sc = src_comments.get(rf.name)
        comment = sc.block if sc else DoxygenBlock()
        if source_path and sc is None:
            LOG.warn(
                f"{source_name}:{source_line or '?'}",
                f"{rf.name} 上方未找到 doxygen 注释块，briefEn 为空",
            )

        params = parse_params(rf.params_raw, comment)

        functions.append(
            {
                "id": rf.name,
                "name": rf.name,
                "peripheral": periph,
                "sectionId": "",  # 稍后按分组回填
                "prototype": rf.prototype,
                "returnType": rf.return_type,
                "params": params,
                "returnDescEn": comment.retval,
                "returnDescZh": "",
                "briefEn": comment.brief,
                "briefZh": "",
                "usageZh": "",
                "prerequisites": [],
                "registers": [],
                "relatedFunctions": [],
                "remarks": comment.notes + comment.warns,
                "notesZh": [],
                "exampleCode": "",
                "exampleLanguage": "c",
                "symbolRefs": [],
                "headerLine": rf.header_line,
                "sourceLine": source_line,
                "flags": {
                    "deprecated": False,
                    "isrSafe": False,
                    "inline": False,
                    "macroLike": False,
                },
                "ai": None,
                "zhSource": "base",
            }
        )

    # 分组
    sections = build_sections(periph, raw_funcs)
    name_to_section = {}
    for sec in sections:
        for fid in sec["functionIds"]:
            name_to_section[fid] = sec["id"]
    for f in functions:
        f["sectionId"] = name_to_section.get(f["name"], "")

    # 本外设的符号
    syms: list[dict[str, Any]] = []
    syms.extend(parse_defines(header_text, header_name))
    syms.extend(parse_enums(header_text, header_name))
    syms.extend(parse_structs(header_text, header_name))
    syms.extend(parse_plain_typedefs(header_text, header_name))

    for s in syms:
        s["peripheral"] = periph
        s.setdefault("usedBy", [])
        s.setdefault("relatedSymbols", [])
        s.setdefault("notesZh", [])
        s.setdefault("usageZh", "")
        s.setdefault("briefZh", "")
        s.setdefault("ai", None)
        s.setdefault("zhSource", "base")
        if s["name"] in symbols_global:
            LOG.warn(header_name, f"符号 {s['name']} 重复定义，保留首个")
            continue
        symbols_global[s["name"]] = s

    peripheral_entry = {
        "id": periph,
        "name": periph,
        "nameZh": PERIPHERAL_NAMES_ZH.get(periph, periph),
        "header": header_name,
        "source": source_name,
        "file": f"functions/{periph}.json",
        "orderIndex": PERIPHERAL_ORDER.get(periph, 1000),
        "introZh": "",
        "usageOverviewZh": "",
        "functionCount": len(functions),
        "symbolCount": len(syms),
        "tags": [],
        "sections": sections,
    }
    return peripheral_entry, functions


def parse_params(params_raw: str, comment: DoxygenBlock) -> list[dict[str, Any]]:
    """解析参数表，并与 @param 说明关联。

    ST 源码里有少量注释与参数名对不上的情况（例如 FLASH_ReadOutProtection
    的注释写成 @param Newstate，实际参数是 NewState），这里做大小写不敏感
    的二次匹配；仍匹配不上时按"源码注释缺失"记警告，不伪造说明。
    """
    params = []
    # 大小写不敏感的查找表
    lower_map = {k.lower(): v for k, v in comment.params.items()}

    for piece in split_top_level(params_raw):
        p = normalize_ws(piece)
        if not p or p == "void":
            continue
        # 形如 "GPIO_TypeDef* GPIOx" / "uint8_t GPIO_PortSource"
        m = re.match(r"^(.*?)([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?$", p)
        if not m:
            LOG.warn("params", f"无法解析参数：{p!r}")
            params.append({"name": p, "type": "", "descEn": "", "descZh": ""})
            continue
        ptype = normalize_ws(m.group(1))
        pname = m.group(2)

        desc = comment.params.get(pname, "")
        if not desc:
            desc = lower_map.get(pname.lower(), "")
            if desc:
                LOG.warn(
                    "params",
                    f"参数 {pname} 的说明在源码里大小写不一致，已按不区分大小写匹配",
                )
        if not desc and comment.params:
            LOG.warn(
                "params",
                f"参数 {pname} 在源码注释里没有 @param 说明"
                f"（该函数注释里只有 {sorted(comment.params)}）",
            )
        params.append(
            {"name": pname, "type": ptype, "descEn": desc, "descZh": ""}
        )
    return params


def compute_symbol_refs(
    functions: list[dict[str, Any]],
    symbol_names: set[str],
    function_names: set[str],
) -> None:
    """为每个函数计算 symbolRefs（关键词跳转白名单）。

    扫描范围：原型 + 参数类型 + 注释 + 返回说明。
    只收录真实存在于符号表里的名字。
    """
    ident_re = re.compile(r"\b[A-Za-z_]\w*\b")
    for f in functions:
        text_parts = [
            f["prototype"],
            f["returnDescEn"],
            f["briefEn"],
            f["returnType"],
        ]
        for p in f["params"]:
            text_parts.append(p["type"])
            text_parts.append(p["descEn"])
        for r in f["remarks"]:
            text_parts.append(r)
        text = " ".join(text_parts)

        refs: list[str] = []
        seen: set[str] = set()
        for name in ident_re.findall(text):
            if name == f["name"]:
                continue
            if name in seen:
                continue
            if name in symbol_names or name in function_names:
                seen.add(name)
                refs.append(name)
        refs.sort()
        f["symbolRefs"] = refs


def build_used_by(
    functions: list[dict[str, Any]], symbols: dict[str, dict[str, Any]]
) -> None:
    """由 symbolRefs 反向填充 usedBy，保证两者双向一致。"""
    for f in functions:
        for name in f["symbolRefs"]:
            sym = symbols.get(name)
            if sym is not None and f["id"] not in sym["usedBy"]:
                sym["usedBy"].append(f["id"])
    for sym in symbols.values():
        sym["usedBy"].sort()


def main() -> int:
    ap = argparse.ArgumentParser(
        description="解析 STM32F10x 标准外设库 V3.5.0，生成基础 JSON。"
    )
    ap.add_argument("--spl-root", required=True, help="SPL 库根目录")
    ap.add_argument("--out", required=True, help="输出目录（基础数据）")
    ap.add_argument(
        "--data-version", default="1.0.0", help="写入 manifest 的数据版本号"
    )
    ap.add_argument(
        "--only", nargs="*", default=None,
        help="只解析指定外设（调试用），如 --only GPIO RCC",
    )
    args = ap.parse_args()

    root = Path(args.spl_root).resolve()
    if not root.is_dir():
        print(f"错误：SPL 根目录不存在：{root}", file=sys.stderr)
        return 2

    layout = Layout.detect(root)
    print(f"[parse_spl] SPL 根目录：{root}")
    print(f"[parse_spl] inc 目录：{[str(p) for p in layout.inc_dirs]}")
    print(f"[parse_spl] src 目录：{[str(p) for p in layout.src_dirs]}")

    headers = collect_headers(layout)
    sources = collect_sources(layout)
    if args.only:
        wanted = {x.upper() for x in args.only}
        headers = {k: v for k, v in headers.items() if k in wanted}
        sources = {k: v for k, v in sources.items() if k in wanted}

    out_dir = Path(args.out)
    (out_dir / "functions").mkdir(parents=True, exist_ok=True)

    symbols_global: dict[str, dict[str, Any]] = {}
    peripherals: list[dict[str, Any]] = []
    all_functions: list[dict[str, Any]] = []

    for periph in sorted(headers, key=lambda p: (PERIPHERAL_ORDER.get(p, 1000), p)):
        entry, funcs = parse_peripheral(
            periph, headers[periph], sources.get(periph), symbols_global
        )
        peripherals.append(entry)
        all_functions.extend(funcs)
        print(
            f"  {periph:<8} 函数 {len(funcs):>3}  符号 {entry['symbolCount']:>4}"
            f"  分组 {len(entry['sections'])}"
        )

    symbol_names = set(symbols_global.keys())
    function_names = {f["id"] for f in all_functions}
    compute_symbol_refs(all_functions, symbol_names, function_names)
    build_used_by(all_functions, symbols_global)

    # 按外设写函数文件
    for entry in peripherals:
        pid = entry["id"]
        funcs = [f for f in all_functions if f["peripheral"] == pid]
        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "peripheral": pid,
            "functions": funcs,
        }
        write_json(out_dir / "functions" / f"{pid}.json", payload)

    write_json(
        out_dir / "peripherals.json",
        {"schemaVersion": SCHEMA_VERSION, "peripherals": peripherals},
    )

    # ------------------------------------------------------------------
    # 符号分流
    #
    # stm32f10x.h 里有 4000+ 个寄存器位定义宏（如 GPIO_CRL_MODE0）。
    # 它们体量大、平时用不到，但"寄存器位域展开"功能需要它们。
    # 因此拆成两个文件：
    #   symbols.json        —— API 符号（宏/枚举/结构体），首屏必读
    #   registers.json      —— 寄存器位定义宏，按需加载
    # ------------------------------------------------------------------
    api_symbols: list[dict[str, Any]] = []
    reg_symbols: list[dict[str, Any]] = []
    for key in sorted(symbols_global):
        sym = symbols_global[key]
        # 兜底：任何符号都必须带 id，否则 App 端 symbolById 索引会缺失该符号
        if not sym.get("id"):
            sym["id"] = sym["name"]
        if sym.get("registerName"):
            reg_symbols.append(sym)
        else:
            api_symbols.append(sym)

    write_json(
        out_dir / "symbols.json",
        {"schemaVersion": SCHEMA_VERSION, "symbols": api_symbols},
    )
    write_json(
        out_dir / "registers.json",
        {
            "schemaVersion": SCHEMA_VERSION,
            "symbols": reg_symbols,
        },
    )

    symbols_list = api_symbols + reg_symbols
    stats = {
        "peripheralCount": len(peripherals),
        "functionCount": len(all_functions),
        "symbolCount": len(symbols_list),
        "apiSymbolCount": len(api_symbols),
        "registerSymbolCount": len(reg_symbols),
        "pinCount": 0,
        "compileErrorCount": 0,
    }
    write_json(
        out_dir / "manifest.json",
        {
            "schemaVersion": SCHEMA_VERSION,
            "dataVersion": args.data_version,
            "splVersion": SPL_VERSION,
            "defaultChipId": "stm32f103c8t6",
            "generatedAt": "",
            "generator": "tools/parse_spl.py",
            "stats": stats,
            "files": {
                "peripherals": "peripherals.json",
                "functions": "functions/",
                "symbols": "symbols.json",
                "registers": "registers.json",
                "pinout": "pinout_f103c8t6.json",
                "compileErrors": "compile_errors.json",
            },
        },
    )

    print(
        f"\n[parse_spl] 完成：外设 {stats['peripheralCount']}，"
        f"函数 {stats['functionCount']}，"
        f"符号 {stats['symbolCount']}"
        f"（API {stats['apiSymbolCount']} + 寄存器位 {stats['registerSymbolCount']}）"
    )
    LOG.dump()
    return 0


def write_json(path: Path, payload: Any) -> None:
    """写 JSON：UTF-8 无 BOM、缩进 2、键序稳定。"""
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    sys.exit(main())
