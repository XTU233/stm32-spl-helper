import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// 应用入口。
///
/// 全程离线：不初始化任何网络相关组件，不做任何远程配置拉取。
void main() {
  runApp(
    // ProviderScope 是 Riverpod 的根容器，必须包在最外层
    const ProviderScope(child: SplHelperApp()),
  );
}
