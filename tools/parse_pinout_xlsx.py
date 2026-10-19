#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 STM32F103C8T6引脚定义.xlsx 转成 pinout_f103c8t6.json。

输入：用户提供的引脚定义表（DS5319 Table 5 的转录）
输出：assets/data/pinout_f103c8t6.json

本脚本只做搬运与格式转换，**不推测任何电气特性**：
    xlsx 列             → JSON 字段
    引脚号              → number
    引脚名称            → name（取主功能名部分）
    类型                → groups
    I/O口电平           → fiveVoltTolerant（值为 FT 时为 true）
    主功能              → defaultFunction / jtagSwd
    默认复用功能        → functions[]，remapRequired=false
    重定义功能          → functions[]，remapRequired=true

用法：
    python parse_pinout_xlsx.py --xlsx "D:\\...\\STM32F103C8T6引脚定义.xlsx" \\
                                --out  "...\\build\\base\\pinout_f103c8t6.json"
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

try:
    import openpyxl
except ImportError:  # pragma: no cover
    print(
        "错误：需要 openpyxl。请用 DSH 自带 Python 运行时运行本脚本。",
        file=sys.stderr,
    )
    raise SystemExit(2)

SCHEMA_VERSION = 1

# 调试口信号名 → 是否被 JTAG/SWD 占用
DEBUG_SIGNALS = {
    "JTMS/SWDIO",
    "JTCK/SWCLK",
    "JTDI",
    "JTDO",
    "NJTRST",
}

# 复用功能名 → 所属外设 id（用于跳转）。
# 只做前缀归类，不做语义推测。
PERIPHERAL_PREFIXES = [
    ("USART", "USART"),
    ("UART", "USART"),
    ("SPI", "SPI"),
    ("I2C", "I2C"),
    ("I2S", "SPI"),
    ("TIM", "TIM"),
    ("ADC", "ADC"),
    ("CAN", "CAN"),
    ("USB", "USB"),
    ("SDIO", "SDIO"),
    ("ETH", "ETH"),
    ("FSMC", "FSMC"),
    ("DAC", "DAC"),
    ("MCO", "RCC"),
    ("OSC", "RCC"),
    ("TAMPER", "BKP"),
    ("RTC", "BKP"),
    ("WKUP", "PWR"),
    ("TRACESWO", "DBGMCU"),
    ("NJTRST", "GPIO"),
    ("JTDI", "GPIO"),
    ("JTDO", "GPIO"),
    ("JTMS", "GPIO"),
    ("JTCK", "GPIO"),
]


def warn(msg: str) -> None:
    print(f"  ! {msg}", file=sys.stderr)


def peripheral_of(func_name: str) -> str:
    """由复用功能名推断所属外设 id。推不出来时返回空串。"""
    up = func_name.upper()
    for prefix, pid in PERIPHERAL_PREFIXES:
        if up.startswith(prefix):
            return pid
    return ""


def kind_of(func_name: str, is_default_af: bool) -> str:
    """判断功能种类。"""
    up = func_name.upper()
    if up in DEBUG_SIGNALS:
        return "debug"
    if re.fullmatch(r"P[A-G]\d{1,2}", up):
        return "gpio"
    if up.startswith(("OSC", "TAMPER", "WKUP", "BOOT")):
        return "other"
    return "af"


def classify_groups(pin_name: str, main_func: str, type_cell: str) -> list[str]:
    """判断引脚属于哪些分组。

    依据 xlsx 的"类型"列与"主功能"列，不做电气推测。
    """
    groups: list[str] = []
    name_up = pin_name.upper()
    main_up = main_func.upper()
    type_up = (type_cell or "").upper()

    is_power_supply = type_up == "S" or main_up.startswith(("VDD", "VBAT", "VDDA"))
    is_ground = main_up.startswith(("VSS", "VSSA"))
    is_debug = main_up in DEBUG_SIGNALS

    if is_ground:
        groups.append("ground")
    elif is_power_supply:
        groups.append("power")
    elif main_up.startswith("NRST"):
        groups.append("reset")
    elif main_up.startswith("BOOT"):
        groups.append("boot")
    elif main_up.startswith(("OSC_IN", "OSC_OUT", "OSC32")):
        groups.append("osc")
    elif is_debug:
        groups.append("debug")
        groups.append("gpio")
    elif re.match(r"^P[A-G]\d", name_up) or re.match(r"^P[A-G]\d", main_up):
        groups.append("gpio")
    else:
        groups.append("other")

    # 纯 GPIO 引脚若主功能是 PXn，补 gpio 标记（debug 引脚已有）
    if (
        "gpio" not in groups
        and "debug" not in groups
        and re.match(r"^P[A-G]\d", main_up)
    ):
        groups.append("gpio")
    return groups


def split_functions(cell: str) -> list[str]:
    """把 "WKUP/USART2_CTS/ADC12_IN0/TIM2_CH1_ETR" 拆成列表。"""
    if not cell:
        return []
    parts = [p.strip() for p in str(cell).split("/")]
    return [p for p in parts if p]


def main() -> int:
    ap = argparse.ArgumentParser(description="引脚定义 xlsx → pinout JSON")
    ap.add_argument("--xlsx", required=True, help="引脚定义表路径")
    ap.add_argument("--out", required=True, help="输出 JSON 路径")
    ap.add_argument(
        "--chip-id", default="stm32f103c8t6", help="芯片 id"
    )
    ap.add_argument(
        "--package", default="LQFP48", help="封装名"
    )
    ap.add_argument(
        "--verified",
        action="store_true",
        help="数据已人工对照数据手册核对（默认 false）",
    )
    args = ap.parse_args()

    xlsx = Path(args.xlsx)
    if not xlsx.is_file():
        print(f"错误：找不到引脚定义表：{xlsx}", file=sys.stderr)
        return 2

    wb = openpyxl.load_workbook(xlsx, data_only=True)
    ws = wb.worksheets[0]
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        print("错误：xlsx 为空", file=sys.stderr)
        return 2

    # 定位表头行（含"引脚号"的那一行）
    header_idx = -1
    for i, r in enumerate(rows):
        cells = ["" if c is None else str(c).strip() for c in r]
        if "引脚号" in cells:
            header_idx = i
            header = cells
            break
    if header_idx < 0:
        print("错误：找不到表头行（应含「引脚号」）", file=sys.stderr)
        return 2

    def col(name: str) -> int:
        for j, h in enumerate(header):
            if h == name:
                return j
        return -1

    c_num = col("引脚号")
    c_name = col("引脚名称")
    c_type = col("类型")
    c_level = col("I/O口电平")
    c_main = col("主功能")
    c_af = col("默认复用功能")
    c_remap = col("重定义功能")

    for label, idx in (
        ("引脚号", c_num),
        ("引脚名称", c_name),
        ("类型", c_type),
        ("主功能", c_main),
    ):
        if idx < 0:
            print(f"错误：表头缺少「{label}」列", file=sys.stderr)
            return 2

    pins = []
    for r in rows[header_idx + 1:]:
        cells = ["" if c is None else str(c).strip() for c in r]
        if len(cells) <= max(c_num, c_name):
            continue
        num_raw = cells[c_num]
        if not num_raw:
            continue
        try:
            number = int(float(num_raw))
        except ValueError:
            warn(f"引脚号无法解析：{num_raw!r}，跳过该行")
            continue

        raw_name = cells[c_name] if c_name < len(cells) else ""
        main_func = cells[c_main] if 0 <= c_main < len(cells) else ""
        type_cell = cells[c_type] if 0 <= c_type < len(cells) else ""
        level_cell = cells[c_level] if 0 <= c_level < len(cells) else ""
        af_cell = cells[c_af] if 0 <= c_af < len(cells) else ""
        remap_cell = cells[c_remap] if 0 <= c_remap < len(cells) else ""

        # 引脚名：优先用主功能名，退回 xlsx 的名称列。
        # 调试口引脚（JTMS/SWDIO 等）的主功能列写的是信号名而非引脚名，
        # 此时从"重定义功能"列取回真实引脚名（如 PA13），
        # 这与数据手册里"重映射后 PA13 可作普通 IO"的描述一致。
        main_up = main_func.upper()
        name = main_func or raw_name
        if main_up in DEBUG_SIGNALS:
            # 重定义功能列形如 "PA13" / "TIM2_CH1_ETR/PA15/SPI1_NSS"
            cand = [
                f
                for f in split_functions(remap_cell)
                if re.fullmatch(r"P[A-G]\d{1,2}", f.upper())
            ]
            if cand:
                name = cand[0].upper()
            else:
                # 退回引脚名称列，形如 "PA13"
                nm = re.match(r"^(P[A-G]\d{1,2})", raw_name.upper())
                name = nm.group(1) if nm else raw_name
        m = re.match(r"^(P[A-G]\d{1,2})", name)
        if m:
            name = m.group(1)

        # 5V 容忍：I/O口电平列为 FT
        ft = level_cell.upper() == "FT"

        # 调试口占用
        jtag = main_func if main_func.upper() in DEBUG_SIGNALS else None

        # 功能列表
        functions = []
        seen_fn: set[str] = set()
        for fn in split_functions(af_cell):
            if fn in seen_fn:
                continue
            seen_fn.add(fn)
            functions.append(
                {
                    "name": fn,
                    "kind": kind_of(fn, True),
                    "remapRequired": False,
                    "peripheralId": peripheral_of(fn),
                    "remapNoteZh": "",
                }
            )
        for fn in split_functions(remap_cell):
            if fn in seen_fn:
                continue
            seen_fn.add(fn)
            functions.append(
                {
                    "name": fn,
                    "kind": kind_of(fn, False),
                    "remapRequired": True,
                    "peripheralId": peripheral_of(fn),
                    "remapNoteZh": "",
                }
            )
        # 主功能自身也作为一种功能
        if name and name not in seen_fn:
            if re.match(r"^P[A-G]\d", name):
                fkind = "gpio"
            elif main_up in DEBUG_SIGNALS:
                fkind = "debug"
            elif main_up.startswith(("VSS", "VSSA")):
                fkind = "ground"
            elif main_up.startswith(("VDD", "VBAT", "VDDA")):
                fkind = "power"
            elif main_up.startswith("NRST"):
                fkind = "reset"
            elif main_up.startswith("BOOT"):
                fkind = "boot"
            elif main_up.startswith(("OSC_IN", "OSC_OUT", "OSC32")):
                fkind = "osc"
            else:
                fkind = "other"
            functions.insert(
                0,
                {
                    "name": name,
                    "kind": fkind,
                    "remapRequired": False,
                    "peripheralId": "GPIO" if fkind == "gpio" else "",
                    "remapNoteZh": "",
                },
            )

        groups = classify_groups(raw_name or name, main_func, type_cell)

        pins.append(
            {
                "number": number,
                "name": name,
                "groups": groups,
                "defaultFunction": main_func or name,
                "defaultFunctionZh": "",
                "functions": functions,
                "fiveVoltTolerant": ft,
                "jtagSwd": jtag,
                "notesZh": "",
                "relatedFunctionIds": [],
            }
        )

    # 校验：编号连续
    pins.sort(key=lambda p: p["number"])
    nums = [p["number"] for p in pins]
    expected = list(range(1, len(pins) + 1))
    if nums != expected:
        missing = sorted(set(expected) - set(nums))
        dup = sorted({n for n in nums if nums.count(n) > 1})
        warn(f"引脚编号不连续：缺失 {missing}，重复 {dup}")

    # 校验：调试口只应在固定引脚上
    for p in pins:
        if p["jtagSwd"] and p["number"] not in (34, 37, 38, 39, 40):
            warn(
                f"第 {p['number']} 脚（{p['name']}）标记为调试口 {p['jtagSwd']}，"
                "与 LQFP48 常见排布不符，请核对"
            )

    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "chipId": args.chip_id,
        "package": args.package,
        "source": f"{xlsx.name}（DS5319 Table 5 转录）",
        "verified": bool(args.verified),
        "verifiedNote": (
            ""
            if args.verified
            else "引脚复用数据来自本地引脚定义表，尚未逐条对照 DS5319 数据手册。使用前请核对。"
        ),
        "pins": pins,
    }

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    ft_count = sum(1 for p in pins if p["fiveVoltTolerant"])
    dbg = [p["number"] for p in pins if p["jtagSwd"]]
    print(
        f"[parse_pinout] 写入 {out}\n"
        f"  引脚 {len(pins)} 个，5V 容忍 {ft_count} 个，调试口引脚 {dbg}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
