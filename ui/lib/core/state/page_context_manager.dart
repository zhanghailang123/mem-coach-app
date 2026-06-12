import 'package:flutter/material.dart';

/// 全局页面上下文管理
///
/// 当用户在真题/单词详情页时，该页面设置上下文
/// 全局AI按钮读取此上下文并传递给Agent
class PageContextManager extends ChangeNotifier {
  Map<String, dynamic>? _currentContext;

  Map<String, dynamic>? get currentContext => _currentContext;

  /// 设置当前页面上下文（进入详情页时调用）
  void setContext(Map<String, dynamic> context) {
    _currentContext = context;
    notifyListeners();
  }

  /// 清除上下文（离开详情页时调用）
  void clearContext() {
    _currentContext = null;
    notifyListeners();
  }

  int _refreshRequestCount = 0;
  int get refreshRequestCount => _refreshRequestCount;

  /// 请求全局数据刷新（例如 AI 聊天关闭后触发同步）
  void requestRefresh() {
    _refreshRequestCount++;
    notifyListeners();
  }
  static final PageContextManager _instance = PageContextManager._internal();
  factory PageContextManager() => _instance;
  PageContextManager._internal();
}
