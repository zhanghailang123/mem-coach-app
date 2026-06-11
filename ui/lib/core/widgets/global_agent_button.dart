import 'dart:ui';
import 'package:flutter/material.dart';

import '../state/page_context_manager.dart';
import '../../features/coach/widgets/chat_sheet.dart';
import 'ai_sparkle_logo.dart';

/// 全局悬浮 AI Agent 按钮
///
/// 在 MaterialApp.builder 中注入，始终悬浮于所有路由之上。
/// 支持拖拽移动、边缘吸附、读取页面上下文。
class GlobalAgentButton extends StatefulWidget {
  const GlobalAgentButton({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalAgentButton> createState() => _GlobalAgentButtonState();
}

class _GlobalAgentButtonState extends State<GlobalAgentButton>
    with SingleTickerProviderStateMixin {
  // 按钮位置（右下角初始位置，在 didChangeDependencies 中设置）
  double _left = 0;
  double _top = 0;
  bool _positioned = false;

  // 拖拽状态
  bool _isDragging = false;

  // 按钮尺寸
  static const double _buttonSize = 50.0;
  // 距屏幕边缘的安全边距
  static const double _edgePadding = 16.0;

  // 吸附动画
  late final AnimationController _snapController;
  Animation<Offset>? _snapAnimation;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _snapController.addListener(() {
      if (_snapAnimation != null) {
        setState(() {
          _left = _snapAnimation!.value.dx;
          _top = _snapAnimation!.value.dy;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_positioned) {
      final size = MediaQuery.of(context).size;
      final bottomPadding = MediaQuery.of(context).padding.bottom;
      // 初始位置：右下角，避开底部导航栏
      _left = size.width - _buttonSize - _edgePadding;
      _top = size.height - _buttonSize - 100 - bottomPadding;
      _positioned = true;
    }
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  // 吸附到最近的屏幕边缘
  void _snapToEdge() {
    final size = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final topPadding = MediaQuery.of(context).padding.top;

    // 计算按钮中心
    final centerX = _left + _buttonSize / 2;

    // 吸附到左边或右边
    final targetLeft = centerX < size.width / 2
        ? _edgePadding
        : size.width - _buttonSize - _edgePadding;

    // 限制垂直范围
    final minTop = topPadding + _edgePadding;
    final maxTop = size.height - _buttonSize - _edgePadding - bottomPadding;
    final targetTop = _top.clamp(minTop, maxTop);

    _snapAnimation = Tween<Offset>(
      begin: Offset(_left, _top),
      end: Offset(targetLeft, targetTop),
    ).animate(CurvedAnimation(
      parent: _snapController,
      curve: Curves.easeOutBack,
    ));

    _snapController.forward(from: 0);
  }

  void _onTap() {
    final pageContext = PageContextManager().currentContext;
    ChatSheet.show(context, pageContext: pageContext);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: _left,
          top: _top,
          child: GestureDetector(
            onPanStart: (_) {
              _snapController.stop();
              setState(() => _isDragging = true);
            },
            onPanUpdate: (details) {
              setState(() {
                _left += details.delta.dx;
                _top += details.delta.dy;
              });
            },
            onPanEnd: (_) {
              setState(() => _isDragging = false);
              _snapToEdge();
            },
            onTap: _onTap,
            child: AnimatedScale(
              scale: _isDragging ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: AnimatedOpacity(
                opacity: _isDragging ? 0.85 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: _buttonSize,
                  height: _buttonSize,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5B5FEF), Color(0xFF20B486)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.9),
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5B5FEF).withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: const Center(
                        child: AiSparkleLogo(
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
