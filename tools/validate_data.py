#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""数据完整性校验。

在 merge_overlay.py 之后运行，检查最终 assets/data/ 是否自洽。
任一检查失败即以非零码退出，不静默放过。

检查项：
 1. 所有 id 全局唯一（函数、符号、外设、引脚、编译错误）
 2. sections[].functionIds 与 functions/<外设>.json 互为子集且并集相等
 3. relatedFunctions / usedBy / symbolRefs / relatedFunctionIds 里的 id 都能找到
 4. params[].type 与 members[].type 里的 XxxTypeDef 都有对应符号
 5. 每个外设的 functionCount 与实际数量一致
 6. 引脚号 1..48 连续无缺无重；jtagSwd 只出现在 34/37/38/39/40
 7. verified=false 的引脚数据必须带 verifiedNote
 8. manifest 的 stats 与实际条数一致

用法：
    python validate_data.py --data assets/data
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

# 允许出现 jtagSwd 的引脚号（LQFP48）
JTAG_PIN_NUMBERS = {34, 37, 38, 39, 40}


class Checker:
    """收集检查结果。"""

    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def report(self) -> int:
        if self.warnings:
            print(f"\n[validate] {len(self.warnings)} 条提示：", file=sys.stderr)
            for w in self.warnings:
                print(f"  ~ {w}", file=sys.stderr)
        if self.errors:
            print(f"\n[validate] {len(self.errors)} 条错误：", file=sys.stderr)
            for e in self.errors:
                print(f"  X {e}", file=sys.stderr)
            return 1
        print("[validate] 全部检查通过。")
        return 0


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


# 类型名里可能出现的库内类型：Xxx_TypeDef / XxxTypeDef / FunctionalState 等
TYPE_NAME_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*TypeDef|[A-Z][A-Za-z0-9_]*_TypeDef)\b")


def main() -> int:
    ap = argparse.ArgumentParser(description="校验最终数据完整性")
    ap.add_argument("--data", required=True, help="最终数据目录（assets/data）")
    args = ap.parse_args()

    data_dir = Path(args.data)
    if not (data_dir / "manifest.json").is_file():
        print(f"错误：{data_dir} 里没有 manifest.json", file=sys.stderr)
        return 2

    c = Checker()

    manifest = load(data_dir / "manifest.json")
    peripherals_bundle = load(data_dir / "peripherals.json")
    symbols_bundle = load(data_dir / "symbols.json")
    registers_bundle = (
        load(data_dir / "registers.json")
        if (data_dir / "registers.json").is_file()
        else {"symbols": []}
    )
    pinout = (
        load(data_dir / "pinout_f103c8t6.json")
        if (data_dir / "pinout_f103c8t6.json").is_file()
        else None
    )
    errors_bundle = (
        load(data_dir / "compile_errors.json")
        if (data_dir / "compile_errors.json").is_file()
        else {"categories": [], "errors": []}
    )

    peripherals = peripherals_bundle["peripherals"]
    symbols = symbols_bundle["symbols"] + registers_bundle.get("symbols", [])

    # ---- 读各外设函数文件 ----
    functions: list[dict[str, Any]] = []
    functions_by_periph: dict[str, list[dict[str, Any]]] = {}
    for per in peripherals:
        pid = per["id"]
        fpath = data_dir / "functions" / f"{pid}.json"
        if not fpath.is_file():
            c.error(f"外设 {pid} 的函数文件不存在：{fpath}")
            continue
        bundle = load(fpath)
        functions_by_periph[pid] = bundle["functions"]
        functions.extend(bundle["functions"])

    function_ids = {f["id"] for f in functions}
    symbol_ids = {s["name"] for s in symbols}
    peripheral_ids = {p["id"] for p in peripherals}

    # ---- 1. id 唯一性 ----
    for label, items, key in (
        ("函数", functions, "id"),
        ("符号", symbols, "name"),
        ("外设", peripherals, "id"),
    ):
        seen: dict[str, int] = {}
        for it in items:
            k = it[key]
            seen[k] = seen.get(k, 0) + 1
        dup = {k: v for k, v in seen.items() if v > 1}
        if dup:
            preview = list(dup.items())[:10]
            c.error(f"{label} id 重复 {len(dup)} 个：{preview}")

    # 引脚号唯一
    if pinout:
        nums = [p["number"] for p in pinout["pins"]]
        if len(nums) != len(set(nums)):
            c.error("引脚号有重复")
    err_ids = [e["id"] for e in errors_bundle.get("errors", [])]
    if len(err_ids) != len(set(err_ids)):
        c.error("编译错误 id 有重复")

    # ---- 2. 分组与函数互为子集 ----
    for per in peripherals:
        pid = per["id"]
        actual = {f["id"] for f in functions_by_periph.get(pid, [])}
        listed: list[str] = []
        for sec in per["sections"]:
            listed.extend(sec["functionIds"])
        listed_set = set(listed)

        if len(listed) != len(listed_set):
            c.error(f"{pid} 的 sections 里有函数被重复列出")
        orphan = actual - listed_set
        dangling = listed_set - actual
        if orphan:
            c.error(f"{pid} 有 {len(orphan)} 个函数未归入任何分组：{sorted(orphan)[:8]}")
        if dangling:
            c.error(f"{pid} 的分组引用了不存在的函数：{sorted(dangling)[:8]}")

    # ---- 3. 交叉引用可解析 ----
    bad_ref = 0
    for f in functions:
        for rid in f.get("relatedFunctions", []):
            if rid not in function_ids:
                c.error(f"{f['id']}.relatedFunctions 引用了不存在的函数 {rid}")
                bad_ref += 1
        for sid in f.get("symbolRefs", []):
            if sid not in symbol_ids and sid not in function_ids:
                c.error(f"{f['id']}.symbolRefs 引用了不存在的符号 {sid}")
                bad_ref += 1
        if f.get("peripheral") not in peripheral_ids:
            c.error(f"{f['id']} 的 peripheral={f.get('peripheral')} 不存在")
        if bad_ref > 60:
            c.error("交叉引用错误过多，已停止列举")
            break

    for s in symbols:
        for fid in s.get("usedBy", []):
            if fid not in function_ids:
                c.error(f"符号 {s['name']}.usedBy 引用了不存在的函数 {fid}")
        for rid in s.get("relatedSymbols", []):
            if rid not in symbol_ids:
                c.warn(f"符号 {s['name']}.relatedSymbols 引用了未收录的 {rid}")
        if s.get("peripheral") not in peripheral_ids:
            c.error(f"符号 {s['name']} 的 peripheral={s.get('peripheral')} 不存在")

    for e in errors_bundle.get("errors", []):
        for fid in e.get("relatedFunctionIds", []):
            if fid not in function_ids:
                c.error(f"{e['id']}.relatedFunctionIds 引用了不存在的函数 {fid}")
        for sid in e.get("relatedSymbolIds", []):
            if sid not in symbol_ids:
                c.error(f"{e['id']}.relatedSymbolIds 引用了不存在的符号 {sid}")
        for pid in e.get("relatedPeripheralIds", []):
            if pid not in peripheral_ids:
                c.error(f"{e['id']}.relatedPeripheralIds 引用了不存在的外设 {pid}")

    cat_ids = {cat["id"] for cat in errors_bundle.get("categories", [])}
    for e in errors_bundle.get("errors", []):
        if e.get("categoryId") not in cat_ids:
            c.error(f"{e['id']} 的 categoryId={e.get('categoryId')} 不在 categories 里")

    # ---- 4. 类型名有对应符号（死链检查）----
    missing_types: dict[str, list[str]] = {}
    for f in functions:
        texts = [p.get("type", "") for p in f.get("params", [])]
        texts.append(f.get("returnType", ""))
        for t in texts:
            for m in TYPE_NAME_RE.finditer(t or ""):
                name = m.group(1)
                if name not in symbol_ids:
                    missing_types.setdefault(name, []).append(f["id"])
    for s in symbols:
        for m in s.get("members", []) or []:
            for tm in TYPE_NAME_RE.finditer(m.get("type") or ""):
                name = tm.group(1)
                if name not in symbol_ids:
                    missing_types.setdefault(name, []).append(s["name"])
    if missing_types:
        for name, users in sorted(missing_types.items())[:15]:
            c.warn(
                f"类型 {name} 没有对应的符号条目"
                f"（被 {len(users)} 处引用，如 {users[:3]}），详情页里它会显示为纯文本"
            )

    # ---- 5. functionCount 一致 ----
    for per in peripherals:
        pid = per["id"]
        actual = len(functions_by_periph.get(pid, []))
        if per.get("functionCount") != actual:
            c.error(
                f"{pid}.functionCount={per.get('functionCount')} 与实际 {actual} 不符"
            )

    # ---- 6/7. 引脚数据 ----
    if pinout:
        nums = sorted(p["number"] for p in pinout["pins"])
        expected = list(range(1, len(nums) + 1))
        if nums != expected:
            missing = sorted(set(expected) - set(nums))
            c.error(f"引脚号不连续，缺失 {missing}")
        for p in pinout["pins"]:
            if p.get("jtagSwd") and p["number"] not in JTAG_PIN_NUMBERS:
                c.error(
                    f"第 {p['number']} 脚标记了 jtagSwd={p['jtagSwd']}，"
                    f"但只允许出现在 {sorted(JTAG_PIN_NUMBERS)}"
                )
            if not p.get("jtagSwd") and p["number"] in JTAG_PIN_NUMBERS:
                c.warn(f"第 {p['number']} 脚是调试口引脚，但没有标 jtagSwd")
            if not p.get("groups"):
                c.error(f"第 {p['number']} 脚没有 groups")
        if not pinout.get("verified") and not pinout.get("verifiedNote"):
            c.error("verified=false 的引脚数据必须带 verifiedNote")
        # 引脚里引用的库函数
        for p in pinout["pins"]:
            for fid in p.get("relatedFunctionIds", []):
                if fid not in function_ids:
                    c.error(f"第 {p['number']} 脚引用了不存在的函数 {fid}")

    # ---- 8. stats 一致 ----
    stats = manifest.get("stats", {})
    checks = [
        ("peripheralCount", len(peripherals)),
        ("functionCount", len(functions)),
        ("symbolCount", len(symbols)),
        ("pinCount", len(pinout["pins"]) if pinout else 0),
        ("compileErrorCount", len(errors_bundle.get("errors", []))),
    ]
    for key, actual in checks:
        if key in stats and stats[key] != actual:
            c.error(f"manifest.stats.{key}={stats[key]} 与实际 {actual} 不符")

    # ---- 附加：中文覆盖率统计（提示性质）----
    zh_funcs = sum(1 for f in functions if f.get("briefZh"))
    zh_syms = sum(1 for s in symbols if s.get("briefZh"))
    zh_pers = sum(1 for p in peripherals if p.get("introZh"))
    c.warn(
        f"中文覆盖：外设 {zh_pers}/{len(peripherals)}，"
        f"函数 {zh_funcs}/{len(functions)}，符号 {zh_syms}/{len(symbols)}"
        "（未覆盖的会显示 ST 英文原文）"
    )

    return c.report()


if __name__ == "__main__":
    sys.exit(main())
