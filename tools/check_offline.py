#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""离线约束自检。

在每次发布前运行，确认 APP 没有引入任何网络能力。
任一检查失败即以非零码退出。

用法：
    python tools/check_offline.py
    # 或带 APK 路径做产物级检查：
    python tools/check_offline.py --apk build/app/outputs/flutter-apk/app-release.apk
"""

from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 禁止出现在 Dart 非注释代码里的网络 API
FORBIDDEN_DART = [
    "package:http",
    "package:dio",
    "HttpClient",
    "WebSocket",
    "package:webview",
    "package:google_fonts",
    "package:url_launcher",
    "package:connectivity_plus",
]

# 禁止出现在 pubspec 直接依赖里的包
FORBIDDEN_DEPS = [
    "http",
    "dio",
    "google_fonts",
    "url_launcher",
    "webview_flutter",
    "connectivity_plus",
    "firebase_core",
    "sentry_flutter",
]

# 只允许这些权限出现在 main manifest（实际应为空）
ALLOWED_PERMISSIONS: list[str] = []

COMMENT_LINE = re.compile(r"^\s*(//|///|\*|/\*)")


class Check:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.passes: list[str] = []

    def ok(self, msg: str) -> None:
        self.passes.append(msg)

    def fail(self, msg: str) -> None:
        self.failures.append(msg)

    def report(self) -> int:
        for p in self.passes:
            print(f"  [OK]   {p}")
        for f in self.failures:
            print(f"  [FAIL] {f}", file=sys.stderr)
        if self.failures:
            print(
                f"\n离线自检未通过：{len(self.failures)} 项失败。",
                file=sys.stderr,
            )
            return 1
        print(f"\n离线自检全部通过（{len(self.passes)} 项）。")
        return 0


def check_dart_sources(c: Check) -> None:
    """Dart 非注释代码里不得出现网络 API。"""
    lib = ROOT / "lib"
    hits: list[str] = []
    for f in lib.rglob("*.dart"):
        for i, line in enumerate(
            f.read_text(encoding="utf-8", errors="replace").splitlines(), 1
        ):
            if COMMENT_LINE.match(line):
                continue
            for bad in FORBIDDEN_DART:
                if bad in line:
                    hits.append(f"{f.relative_to(ROOT)}:{i} 引用 {bad}")
    if hits:
        for h in hits:
            c.fail(h)
    else:
        c.ok("lib/ 非注释代码中无任何网络 API 引用")


def check_pubspec(c: Check) -> None:
    """pubspec 的直接依赖里不得出现网络包。"""
    pub = ROOT / "pubspec.yaml"
    if not pub.is_file():
        c.fail("找不到 pubspec.yaml")
        return
    text = pub.read_text(encoding="utf-8")
    # 只检查 dependencies 段（dev_dependencies 不进 APK）
    m = re.search(r"^dependencies:(.*?)^dev_dependencies:", text, re.S | re.M)
    if not m:
        m = re.search(r"^dependencies:(.*)", text, re.S | re.M)
    section = m.group(1) if m else ""
    hits = []
    for dep in FORBIDDEN_DEPS:
        for line in section.splitlines():
            if COMMENT_LINE.match(line):
                continue
            if re.match(rf"^\s+{re.escape(dep)}\s*:", line):
                hits.append(dep)
    if hits:
        for h in hits:
            c.fail(f"pubspec dependencies 含网络包：{h}")
    else:
        c.ok("pubspec 直接依赖不含任何网络包")


def strip_xml_comments(text: str) -> str:
    """去掉 XML 注释，避免把注释里提到的权限名误判为真实声明。"""
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def check_manifest(c: Check) -> None:
    """main manifest 不得声明 INTERNET，且必须禁止明文流量。"""
    mf = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not mf.is_file():
        c.fail("找不到 main AndroidManifest.xml")
        return
    raw = mf.read_text(encoding="utf-8", errors="replace")
    # 只在实际生效的 XML 上判断，注释里提到权限名不算声明
    text = strip_xml_comments(raw)

    if "android.permission.INTERNET" in text:
        c.fail("main manifest 声明了 INTERNET 权限")
    else:
        c.ok("main manifest 未声明 INTERNET 权限")

    # 找出所有实际生效的 uses-permission
    perms = re.findall(r'<uses-permission\s+android:name="([^"]+)"', text)
    unexpected = [p for p in perms if p not in ALLOWED_PERMISSIONS]
    if unexpected:
        c.fail(f"main manifest 声明了未预期权限：{unexpected}")
    else:
        c.ok("main manifest 未声明任何其它权限")

    if 'android:usesCleartextTraffic="false"' in text:
        c.ok("已禁用明文流量（usesCleartextTraffic=false）")
    else:
        c.fail("未设置 usesCleartextTraffic=false")

    if 'android:networkSecurityConfig="@xml/network_security_config"' in text:
        c.ok("已配置 networkSecurityConfig")
    else:
        c.fail("未配置 networkSecurityConfig")

    nsc = ROOT / "android/app/src/main/res/xml/network_security_config.xml"
    if nsc.is_file() and 'cleartextTrafficPermitted="false"' in nsc.read_text(
        encoding="utf-8", errors="replace"
    ):
        c.ok("network_security_config 禁止明文流量")
    else:
        c.fail("network_security_config 缺失或未禁止明文流量")


def check_apk(c: Check, apk_path: Path) -> None:
    """产物级检查：APK 权限与是否误打包源文件。"""
    if not apk_path.is_file():
        c.fail(f"APK 不存在：{apk_path}")
        return

    # 用 aapt2 检查权限（若可用）
    import shutil
    import subprocess

    sdk = Path.home() / "AppData/Local/Android/Sdk"
    aapt = None
    bt = sdk / "build-tools"
    if bt.is_dir():
        for d in sorted(bt.iterdir(), reverse=True):
            cand = d / "aapt2.exe"
            if cand.is_file():
                aapt = cand
                break
    if aapt is None:
        aapt = shutil.which("aapt2")

    if aapt:
        try:
            out = subprocess.run(
                [str(aapt), "dump", "permissions", str(apk_path)],
                capture_output=True,
                text=True,
                timeout=60,
            ).stdout
            if "android.permission.INTERNET" in out:
                c.fail("APK 声明了 INTERNET 权限")
            else:
                c.ok("APK 未声明 INTERNET 权限（运行期硬保证成立）")
        except Exception as e:  # pragma: no cover
            c.fail(f"aapt2 检查失败：{e}")
    else:
        print("  [跳过] 未找到 aapt2，跳过 APK 权限检查", file=sys.stderr)

    # 检查 zip 内容
    try:
        with zipfile.ZipFile(apk_path) as z:
            names = z.namelist()

            # 不得打包 overlay 源文件与 build 中间产物
            leaked = [
                n
                for n in names
                if "zh_overlay" in n or "_TIM_part" in n or "/build/base" in n
            ]
            if leaked:
                c.fail(f"APK 误打包了源文件：{leaked[:5]}")
            else:
                c.ok("APK 未打包 overlay 源文件与中间产物")

            # 数据文件应存在
            data_files = [
                n
                for n in names
                if n.startswith("assets/flutter_assets/assets/data/")
            ]
            if len(data_files) >= 30:
                c.ok(f"APK 内含 {len(data_files)} 个数据文件")
            else:
                c.fail(f"APK 内数据文件过少（{len(data_files)} 个）")

            # 不得含 url_launcher 的 Android 实现
            launcher = [n for n in names if "url_launcher" in n.lower()]
            if launcher:
                c.fail(f"APK 含 url_launcher 相关条目：{launcher[:3]}")
            else:
                c.ok("APK 不含 url_launcher 相关类")
    except Exception as e:  # pragma: no cover
        c.fail(f"读取 APK 失败：{e}")


def main() -> int:
    ap = argparse.ArgumentParser(description="离线约束自检")
    ap.add_argument("--apk", help="release APK 路径（可选，做产物级检查）")
    args = ap.parse_args()

    c = Check()
    print("[check_offline] 检查源码与配置…")
    check_dart_sources(c)
    check_pubspec(c)
    check_manifest(c)

    if args.apk:
        print(f"[check_offline] 检查产物 {args.apk} …")
        check_apk(c, Path(args.apk))

    return c.report()


if __name__ == "__main__":
    sys.exit(main())
