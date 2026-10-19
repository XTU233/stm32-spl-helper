#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把中文补充（overlay）合并进解析产物，输出最终打包数据。

流程：
    parse_spl.py / parse_pinout_xlsx.py  →  build/base/     （英文基础数据）
    data/zh_overlay/                     →  中文补充
    merge_overlay.py                     →  assets/data/    （最终数据）

设计原则：
1. overlay 是"源文件"，不进 APK；改了中文不用重跑解析。
2. 合并规则：overlay 里非空的值覆盖 base，空值/null 不动 base。
3. overlay 里引用了不存在的 id 时报警告（防止改名后留下死配置）。

用法：
    python merge_overlay.py --base build/base --overlay data/zh_overlay \\
                            --out assets/data --data-version 1.0.0
"""

from __future__ import annotations

import argparse
import copy
import datetime as _dt
import json
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1


class Warn:
    def __init__(self) -> None:
        self.items: list[str] = []

    def add(self, where: str, msg: str) -> None:
        self.items.append(f"[{where}] {msg}")

    def dump(self) -> None:
        if not self.items:
            print("[merge_overlay] 无警告。", file=sys.stderr)
            return
        print(f"\n[merge_overlay] 共 {len(self.items)} 条警告：", file=sys.stderr)
        for it in self.items:
            print(f"  ! {it}", file=sys.stderr)


W = Warn()


def load_json(path: Path) -> Any:
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def load_symbol_overlays(ov_dir: Path) -> dict[str, Any]:
    """加载符号 overlay，支持拆成多个文件。

    早期只有 symbols.json 一个文件，后来中文量上来了（结构体成员、
    寄存器映射、枚举值各成一类），单文件变得难维护，于是允许
    `symbols*.json` 任意多个分文件，这里把它们合并成一份。

    返回结构与单文件一致：`{"symbols": {名字: patch}, "extraSymbols": {...}}`，
    这样 merge_symbols 不用改签名。

    合并规则：按文件名排序依次读取，后读到的同名符号**逐字段深合并**
    （而不是整体覆盖），这样不同文件可以各写同一个符号的不同字段——
    例如旧 symbols.json 写了 briefZh，新的 symbols_enum_*.json 补 membersZh。

    没有 `symbols` 键的文件（比如纯注释）会被跳过。
    """
    merged: dict[str, Any] = {}
    extra: dict[str, Any] = {}
    files = sorted(ov_dir.glob("symbols*.json"))
    for f in files:
        data = load_json(f)
        if not isinstance(data, dict):
            continue
        part = data.get("symbols")
        if isinstance(part, dict):
            for name, patch in part.items():
                if not isinstance(patch, dict):
                    continue
                existing = merged.get(name)
                if existing is None:
                    merged[name] = copy.deepcopy(patch)
                else:
                    _deep_merge(existing, patch)
        # extraSymbols 只应出现在 symbols.json 里，这里也一并收拢
        e = data.get("extraSymbols")
        if isinstance(e, dict):
            for name, spec in e.items():
                extra.setdefault(name, spec)
    return {"symbols": merged, "extraSymbols": extra}


def _deep_merge(target: dict[str, Any], patch: dict[str, Any]) -> None:
    """把 patch 递归合并进 target（用于同一个符号跨文件补字段）。"""
    for k, v in patch.items():
        if isinstance(v, dict) and isinstance(target.get(k), dict):
            _deep_merge(target[k], v)
        else:
            target[k] = v


def merge_dict(target: dict[str, Any], patch: dict[str, Any]) -> None:
    """把 patch 里"有内容"的字段写进 target。

    空字符串、空列表、None 一律视为"未提供"，不覆盖 base 的值。
    这样 overlay 只需写关心的字段。
    """
    for key, value in patch.items():
        if value is None:
            continue
        if isinstance(value, str) and value.strip() == "":
            continue
        if isinstance(value, (list, dict)) and len(value) == 0:
            continue
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge_dict(target[key], value)
        else:
            target[key] = value


# ---------------------------------------------------------------------------
# 各文件的合并
# ---------------------------------------------------------------------------


def merge_peripherals(
    base: dict[str, Any], overlay: dict[str, Any]
) -> dict[str, Any]:
    """合并外设：introZh / usageOverviewZh / orderIndex / tags / sections 标题。"""
    ov_p = overlay.get("peripherals", {}) if overlay else {}
    ov_titles = overlay.get("sectionTitles", {}) if overlay else {}
    ov_order = overlay.get("orderIndex", {}) if overlay else {}

    for per in base.get("peripherals", []):
        pid = per["id"]
        patch = ov_p.get(pid, {})
        merge_dict(per, patch)
        # 排序权重可由 overlay 单独指定
        if pid in ov_order:
            per["orderIndex"] = ov_order[pid]
        # 分节标题中文覆盖
        for sec in per.get("sections", []):
            key = sec.get("titleEn") or sec.get("title")
            if key in ov_titles:
                sec["title"] = ov_titles[key]

    # 检查 overlay 里多余的键
    known = {p["id"] for p in base.get("peripherals", [])}
    for pid in ov_p:
        if pid not in known:
            W.add("peripherals.json", f"overlay 里的外设 {pid} 在基础数据中不存在")
    return base


def merge_functions(
    base_dir: Path, overlay_dir: Path, periph_ids: list[str]
) -> dict[str, dict[str, Any]]:
    """合并各外设的函数文件。返回 {外设: bundle}。"""
    result: dict[str, dict[str, Any]] = {}
    for pid in periph_ids:
        path = base_dir / "functions" / f"{pid}.json"
        bundle = load_json(path)
        if bundle is None:
            W.add("functions", f"基础数据缺少 {pid}.json")
            continue

        ov_path = overlay_dir / "functions" / f"{pid}.json"
        ov = load_json(ov_path) or {}
        ov_funcs = ov.get("functions", {})

        known = {f["id"] for f in bundle["functions"]}
        for fid, patch in ov_funcs.items():
            if fid not in known:
                W.add(f"functions/{pid}.json", f"overlay 里的函数 {fid} 不存在")
                continue
            target = next(f for f in bundle["functions"] if f["id"] == fid)
            # 参数中文说明单独处理：按参数名匹配
            params_zh = patch.pop("paramsZh", None) if isinstance(patch, dict) else None
            merge_dict(target, patch)
            if params_zh:
                for p in target.get("params", []):
                    if p["name"] in params_zh:
                        p["descZh"] = params_zh[p["name"]]
                    else:
                        W.add(
                            f"functions/{pid}.json",
                            f"{fid} 的 paramsZh 里有未知参数 {p['name']}",
                        )
            target["zhSource"] = "overlay"

        result[pid] = bundle
    return result


def recompute_symbol_refs(
    bundles: dict[str, dict[str, Any]],
    symbol_names: set[str],
    function_names: set[str],
) -> int:
    """重新计算每个函数的 symbolRefs。

    为什么要在合并阶段重算：解析脚本算 symbolRefs 时只扫了原型、参数与
    ST 英文注释，那时**中文 overlay 还没合并进来**。而示例代码、中文说明、
    前置条件里出现的库内符号（如示例代码里的 GPIO_Mode_Out_PP）同样是
    用户会点击的目标——需求 5.3 明确要求"示例代码里的 GPIO_Mode_Out_PP
    要能跳转"。所以合并完中文后必须重算一次。

    返回补充了多少条引用。
    """
    ident_re = re.compile(r"\b[A-Za-z_]\w*\b")
    added = 0
    for bundle in bundles.values():
        for f in bundle["functions"]:
            parts = [
                f.get("prototype", ""),
                f.get("returnType", ""),
                f.get("returnDescEn", ""),
                f.get("returnDescZh", ""),
                f.get("briefEn", ""),
                f.get("briefZh", ""),
                f.get("usageZh", ""),
                f.get("exampleCode", ""),
                *f.get("remarks", []),
                *f.get("notesZh", []),
                *f.get("prerequisites", []),
                *f.get("registers", []),
            ]
            for p in f.get("params", []):
                parts.extend([p.get("type", ""), p.get("descEn", ""), p.get("descZh", "")])

            text = " ".join(parts)
            refs = set(f.get("symbolRefs", []))
            before = len(refs)
            for name in ident_re.findall(text):
                if name == f["id"]:
                    continue
                if name in symbol_names or name in function_names:
                    refs.add(name)
            f["symbolRefs"] = sorted(refs)
            added += len(refs) - before
    return added


def merge_symbols(
    base: dict[str, Any], overlay: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    """合并符号中文说明，并支持新增 SPL 源码里没有的符号。

    符号分两个文件：symbols.json（API 符号）与 registers.json（寄存器位定义）。
    overlay 里的中文说明按名字匹配，落到哪个文件就合并到哪个。

    overlay 的 `extraSymbols` 用于补充 SPL 源码里不存在、但查阅时需要的符号，
    主要是工程预定义宏（USE_STDPERIPH_DRIVER、STM32F10X_MD、USE_FULL_ASSERT）
    与工具链概念。它们由用户在工程选项里定义，不属于库文件。
    """
    overlay = overlay or {}
    ov = overlay.get("symbols", {})
    extra = overlay.get("extraSymbols", {})
    reg_bundle = base.pop(
        "_registers", {"schemaVersion": SCHEMA_VERSION, "symbols": []}
    )

    index: dict[str, dict[str, Any]] = {}
    for s in base.get("symbols", []):
        index[s["name"]] = s
    for s in reg_bundle.get("symbols", []):
        index[s["name"]] = s

    for name, patch in ov.items():
        if name not in index:
            W.add("symbols.json", f"overlay 里的符号 {name} 不存在")
            continue
        target = index[name]
        members_zh = patch.pop("membersZh", None) if isinstance(patch, dict) else None
        merge_dict(target, patch)
        if members_zh:
            for m in target.get("members", []):
                if m["name"] in members_zh:
                    m["descZh"] = members_zh[m["name"]]
        target["zhSource"] = "overlay"

    # 新增符号：完整定义由 overlay 提供
    added = 0
    for name, spec in extra.items():
        if name in index:
            W.add("symbols.json", f"extraSymbols 里的 {name} 与已有符号重名，已跳过")
            continue
        entry = {
            "id": name,
            "name": name,
            "kind": spec.get("kind", "macro"),
            "peripheral": spec.get("peripheral", "MISC"),
            "value": spec.get("value"),
            "valueKind": spec.get("valueKind"),
            "enumType": None,
            "memberOf": None,
            "members": spec.get("members", []),
            "briefEn": spec.get("briefEn", ""),
            "briefZh": spec.get("briefZh", ""),
            "usageZh": spec.get("usageZh", ""),
            "definedIn": spec.get("definedIn", "工程预定义宏（不在库文件中）"),
            "definedLine": spec.get("definedLine", 0),
            "visibility": spec.get("visibility", "public"),
            "functionLike": spec.get("functionLike", False),
            "params": spec.get("params", []),
            "usedBy": spec.get("usedBy", []),
            "relatedSymbols": spec.get("relatedSymbols", []),
            "notesZh": spec.get("notesZh", []),
            "ai": None,
            "zhSource": "overlay",
        }
        index[name] = entry
        base["symbols"].append(entry)
        added += 1
    if added:
        base["symbols"].sort(key=lambda s: s["name"])

    # 兜底：所有符号都必须带 id（App 端按 id 建索引）
    for s in list(base.get("symbols", [])) + list(reg_bundle.get("symbols", [])):
        if not s.get("id"):
            s["id"] = s["name"]

    return base, reg_bundle


def merge_pinout(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    """合并引脚中文说明与人工确认标记。"""
    if base is None:
        return {}
    ov = (overlay or {}).get("pins", {})
    ov_meta = (overlay or {}).get("meta", {})
    ov_funcs = (overlay or {}).get("functions", {})

    for pin in base.get("pins", []):
        key = str(pin["number"])
        patch = ov.get(key)
        if patch:
            merge_dict(pin, patch)
        # 复用功能的中文备注
        for fn in pin.get("functions", []):
            fkey = f"{pin['number']}:{fn['name']}"
            if fkey in ov_funcs:
                merge_dict(fn, ov_funcs[fkey])
            elif fn["name"] in ov_funcs and ":" not in fn["name"]:
                merge_dict(fn, ov_funcs[fn["name"]])

    if ov_meta:
        merge_dict(base, ov_meta)

    known = {str(p["number"]) for p in base.get("pins", [])}
    for key in ov:
        if key not in known:
            W.add("pinout_notes.json", f"overlay 里的引脚号 {key} 不存在")
    return base


def merge_compile_errors(base_dir: Path, overlay_dir: Path) -> dict[str, Any]:
    """编译错误数据完全来自 overlay（无解析来源）。"""
    path = overlay_dir / "compile_errors_zh.json"
    data = load_json(path)
    if data is None:
        W.add("compile_errors", f"缺少 {path}，编译错误速查将为空")
        return {"schemaVersion": SCHEMA_VERSION, "categories": [], "errors": []}
    return data


def merge_chips(overlay_dir: Path, default_chip: str) -> dict[str, Any]:
    """芯片能力描述来自 overlay。"""
    path = overlay_dir / "chips" / f"{default_chip}.json"
    data = load_json(path)
    if data is None:
        W.add("chips", f"缺少 {path}")
        return {}
    return data


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="合并中文 overlay，输出最终数据")
    ap.add_argument("--base", required=True, help="基础数据目录（build/base）")
    ap.add_argument("--overlay", required=True, help="中文补充目录（data/zh_overlay）")
    ap.add_argument("--out", required=True, help="最终输出目录（assets/data）")
    ap.add_argument("--data-version", default="1.0.0")
    args = ap.parse_args()

    base_dir = Path(args.base)
    ov_dir = Path(args.overlay)
    out_dir = Path(args.out)

    if not (base_dir / "peripherals.json").is_file():
        print(
            f"错误：{base_dir} 里没有 peripherals.json，请先运行 parse_spl.py",
            file=sys.stderr,
        )
        return 2

    base_peripherals = load_json(base_dir / "peripherals.json")
    base_symbols = load_json(base_dir / "symbols.json")
    base_registers = load_json(base_dir / "registers.json")
    base_pinout = load_json(base_dir / "pinout_f103c8t6.json")

    ov_peripherals = load_json(ov_dir / "peripherals.json")
    ov_symbols = load_symbol_overlays(ov_dir)
    ov_pinout = load_json(ov_dir / "pinout_notes.json")

    # 深拷贝，避免修改 base 对象影响后续统计
    base_peripherals = copy.deepcopy(base_peripherals)
    base_symbols = copy.deepcopy(base_symbols)
    if base_registers:
        # 临时挂在 symbols 上，交给 merge_symbols 一起处理
        base_symbols["_registers"] = copy.deepcopy(base_registers)

    periph_ids = [p["id"] for p in base_peripherals["peripherals"]]

    # 1) 外设
    merged_p = merge_peripherals(base_peripherals, ov_peripherals)
    # 2) 函数
    merged_f = merge_functions(base_dir, ov_dir, periph_ids)
    # 3) 符号
    merged_s, merged_reg = merge_symbols(base_symbols, ov_symbols)
    # 4) 引脚
    merged_pin = merge_pinout(base_pinout, ov_pinout) if base_pinout else {}
    # 5) 编译错误
    merged_err = merge_compile_errors(base_dir, ov_dir)
    # 6) 芯片
    default_chip = "stm32f103c8t6"
    merged_chip = merge_chips(ov_dir, default_chip)

    # 7) 重算 symbolRefs 与 usedBy
    #
    # 解析脚本算 symbolRefs 时中文 overlay 还没合并，示例代码与中文说明里的
    # 库内符号（如 GPIO_Mode_Out_PP）不在白名单里，前端就不会把它们渲染成链接。
    # 需求 5.3 明确要求示例代码里的符号可点击，所以这里重算一次，
    # 并同步重建符号的 usedBy 反向索引，保证两者双向一致。
    symbol_names = {s["name"] for s in merged_s["symbols"]}
    symbol_names |= {s["name"] for s in merged_reg.get("symbols", [])}
    function_names = {
        f["id"] for b in merged_f.values() for f in b["functions"]
    }
    added_refs = recompute_symbol_refs(merged_f, symbol_names, function_names)

    # 清空旧 usedBy 后重建（overlay 可能新增了 extraSymbols）
    symbol_index: dict[str, dict[str, Any]] = {}
    for s in merged_s["symbols"]:
        s["usedBy"] = []
        symbol_index[s["name"]] = s
    for s in merged_reg.get("symbols", []):
        s["usedBy"] = []
        symbol_index[s["name"]] = s
    for bundle in merged_f.values():
        for f in bundle["functions"]:
            for name in f["symbolRefs"]:
                sym = symbol_index.get(name)
                if sym is not None and f["id"] not in sym["usedBy"]:
                    sym["usedBy"].append(f["id"])
    for s in symbol_index.values():
        s["usedBy"].sort()

    # 回填统计
    total_functions = sum(len(b["functions"]) for b in merged_f.values())
    zh_functions = sum(
        1 for b in merged_f.values() for f in b["functions"] if f.get("briefZh")
    )
    for per in merged_p["peripherals"]:
        pid = per["id"]
        if pid in merged_f:
            per["functionCount"] = len(merged_f[pid]["functions"])

    total_symbols = len(merged_s["symbols"]) + len(merged_reg.get("symbols", []))
    stats = {
        "peripheralCount": len(merged_p["peripherals"]),
        "functionCount": total_functions,
        "symbolCount": total_symbols,
        "apiSymbolCount": len(merged_s["symbols"]),
        "registerSymbolCount": len(merged_reg.get("symbols", [])),
        "pinCount": len(merged_pin.get("pins", [])),
        "compileErrorCount": len(merged_err.get("errors", [])),
    }

    # 输出
    write_json(out_dir / "peripherals.json", merged_p)
    for pid, bundle in merged_f.items():
        write_json(out_dir / "functions" / f"{pid}.json", bundle)
    write_json(out_dir / "symbols.json", merged_s)
    if merged_reg.get("symbols"):
        write_json(out_dir / "registers.json", merged_reg)
    if merged_pin:
        write_json(out_dir / "pinout_f103c8t6.json", merged_pin)
    write_json(out_dir / "compile_errors.json", merged_err)
    if merged_chip:
        write_json(out_dir / "chips" / f"{default_chip}.json", merged_chip)

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "dataVersion": args.data_version,
        "splVersion": "STM32F10x_StdPeriph_Lib_V3.5.0",
        "defaultChipId": default_chip,
        "generatedAt": _dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "generator": "tools/merge_overlay.py",
        "stats": stats,
        "files": {
            "peripherals": "peripherals.json",
            "functions": "functions/",
            "symbols": "symbols.json",
            "registers": "registers.json",
            "pinout": "pinout_f103c8t6.json",
            "compileErrors": "compile_errors.json",
            "chips": "chips/",
        },
    }
    write_json(out_dir / "manifest.json", manifest)

    print(
        f"[merge_overlay] 输出到 {out_dir}\n"
        f"  外设 {stats['peripheralCount']}，函数 {stats['functionCount']}"
        f"（其中 {zh_functions} 个有中文简述），"
        f"符号 {stats['symbolCount']}"
        f"（API {stats['apiSymbolCount']} + 寄存器位 {stats['registerSymbolCount']}），"
        f"引脚 {stats['pinCount']}，编译错误 {stats['compileErrorCount']}\n"
        f"  重算 symbolRefs：新增 {added_refs} 条引用"
    )
    W.dump()
    return 0


if __name__ == "__main__":
    sys.exit(main())
