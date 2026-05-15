import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 深度思考卡片组件
///
/// 展示 Agent 的思考过程，支持流式文本渐显、计时、折叠/展开。
/// 借鉴 OpenOmniBot DeepThinkingCard 的设计。
class DeepThinkingCard extends StatefulWidget {
  const DeepThinkingCard({
    super.key,
    required this.thinkingText,
    this.isLoading = true,
    this.maxHeight = 210.0,
    this.stage = 1,
    this.startTime,
    this.endTime,
    this.isCollapsible = false,
    this.autoCollapseOnComplete = true,
    this.textColor = const Color(0x80353E53),
  });

  /// 思考内容文本（已格式化）
  final String thinkingText;

  /// 是否正在加载中
  final bool isLoading;

  /// 卡片最大高度
  final double maxHeight;

  /// 思考阶段：1-正在思考，2-规划任务中，3-正在帮你规划任务，4-完成思考，5-已取消
  final int stage;

  /// 开始时间（毫秒时间戳）
  final int? startTime;

  /// 结束时间（毫秒时间戳）
  final int? endTime;

  /// 是否允许点击折叠/展开思考内容
  final bool isCollapsible;

  /// 是否在思考完成后自动折叠内容
  final bool autoCollapseOnComplete;

  final Color textColor;

  @override
  State<DeepThinkingCard> createState() => _DeepThinkingCardState();
}

class _DeepThinkingCardState extends State<DeepThinkingCard>
    with SingleTickerProviderStateMixin {
  static const Duration _collapseDuration = Duration(milliseconds: 170);
  Timer? _timer;
  int _elapsedSeconds = 0;
  final ScrollController _scrollController = ScrollController();
  bool _showGradient = false;
  bool _isCollapsed = false;
  bool _autoScrollToLatest = true;
  bool _hasAutoCollapsedForCurrentCompletion = false;
  late final AnimationController _collapseController;
  late Animation<double> _collapseSizeFactor;
  late Animation<double> _collapseOpacity;
  static const double _bottomTolerance = 1.0;

  @override
  void initState() {
    super.initState();
    _hasAutoCollapsedForCurrentCompletion = _shouldAutoCollapse(widget);
    _isCollapsed = _hasAutoCollapsedForCurrentCompletion;
    _collapseController = AnimationController(
      vsync: this,
      duration: _collapseDuration,
      reverseDuration: _collapseDuration,
      value: _isCollapsed ? 0.0 : 1.0,
    );
    _rebuildCollapseAnimations();
    _updateElapsedTime(notify: false);
    // 如果正在进行中（未完成且未取消），启动计时器
    if (widget.stage != 4 && widget.stage != 5) {
      _startTimer();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToLatestIfNeeded(force: true);
      _checkOverflow();
    });
  }

  @override
  void didUpdateWidget(DeepThinkingCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    _updateElapsedTime();

    final becameCompleted =
        !_isCompletedStage(oldWidget.stage) && _isCompletedStage(widget.stage);
    final becameThinking =
        _isCompletedStage(oldWidget.stage) && !_isCompletedStage(widget.stage);
    final completionSettled =
        _shouldAutoCollapse(widget) &&
        (!_shouldAutoCollapse(oldWidget) ||
            oldWidget.isLoading != widget.isLoading ||
            oldWidget.isCollapsible != widget.isCollapsible ||
            oldWidget.autoCollapseOnComplete != widget.autoCollapseOnComplete);

    if (becameCompleted) {
      _stopTimer();
    }

    if (becameThinking) {
      _startTimer();
      _autoScrollToLatest = true;
      _hasAutoCollapsedForCurrentCompletion = false;
    }

    if (completionSettled && !_hasAutoCollapsedForCurrentCompletion) {
      _setCollapsed(true, markCompletionHandled: true);
    } else if (becameThinking && _isCollapsed) {
      _setCollapsed(false);
    }

    final textChanged = widget.thinkingText != oldWidget.thinkingText;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToLatestIfNeeded(force: textChanged);
      _checkOverflow();
    });
  }

  /// 计算已用时间
  void _updateElapsedTime({bool notify = true}) {
    final nextElapsedSeconds = widget.startTime == null
        ? 0
        : (widget.endTime != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                        widget.endTime!,
                      ).difference(
                        DateTime.fromMillisecondsSinceEpoch(widget.startTime!),
                      )
                    : DateTime.now().difference(
                        DateTime.fromMillisecondsSinceEpoch(widget.startTime!),
                      ))
                .inSeconds;

    if (nextElapsedSeconds == _elapsedSeconds) return;

    if (!notify || !mounted) {
      _elapsedSeconds = nextElapsedSeconds;
      return;
    }

    setState(() {
      _elapsedSeconds = nextElapsedSeconds;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateElapsedTime();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _checkOverflow() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    final hasOverflow = maxExtent > 0;
    final distanceToBottom = (maxExtent - position.pixels).clamp(
      0.0,
      maxExtent,
    );
    final isAtBottom = distanceToBottom <= _bottomTolerance;
    final shouldShowGradient = hasOverflow && !isAtBottom;

    if (shouldShowGradient != _showGradient) {
      setState(() => _showGradient = shouldShowGradient);
    }
  }

  void _scrollToLatestIfNeeded({bool force = false}) {
    if (!mounted || !_scrollController.hasClients) return;
    if (_isCollapsed || widget.stage == 5) return;
    if (!force && widget.stage == 4) return;
    if (!_autoScrollToLatest) return;

    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    if (maxExtent <= 0) return;

    final current = position.pixels.clamp(0.0, maxExtent);
    if ((maxExtent - current).abs() <= _bottomTolerance) return;

    _scrollController.jumpTo(maxExtent);
  }

  void _toggleCollapsed() {
    if (!widget.isCollapsible || widget.stage != 4) return;
    _setCollapsed(
      !_isCollapsed,
      markCompletionHandled: _shouldAutoCollapse(widget),
    );
  }

  void _setCollapsed(
    bool collapsed, {
    bool markCompletionHandled = false,
  }) {
    if (_isCollapsed == collapsed) {
      if (markCompletionHandled) {
        _hasAutoCollapsedForCurrentCompletion = true;
      }
      return;
    }

    setState(() {
      _isCollapsed = collapsed;
      if (markCompletionHandled) {
        _hasAutoCollapsedForCurrentCompletion = true;
      }
    });

    _collapseController.stop();
    _rebuildCollapseAnimations();
    if (collapsed) {
      _collapseController.reverse();
    } else {
      _collapseController.forward();
    }

    if (!collapsed && _shouldResetScrollPositionOnExpand()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final position = _scrollController.position;
        final top = position.minScrollExtent;
        if ((position.pixels - top).abs() > _bottomTolerance) {
          _scrollController.jumpTo(top);
        }
        _checkOverflow();
      });
    }
  }

  void _rebuildCollapseAnimations() {
    _collapseSizeFactor = CurvedAnimation(
      parent: _collapseController,
      curve: _isCollapsed
          ? const Cubic(0.22, 1.0, 0.36, 1.0)
          : const Cubic(0.2, 0.8, 0.2, 1.0),
      reverseCurve: const Cubic(0.22, 1.0, 0.36, 1.0),
    );
    _collapseOpacity = CurvedAnimation(
      parent: _collapseController,
      curve: _isCollapsed
          ? const Interval(0.0, 0.72, curve: Curves.easeOut)
          : const Interval(0.16, 1.0, curve: Curves.easeOut),
      reverseCurve: const Interval(0.16, 1.0, curve: Curves.easeOut),
    );
  }

  bool _shouldAutoCollapse(DeepThinkingCard widget) {
    return widget.autoCollapseOnComplete &&
        widget.isCollapsible &&
        widget.stage == 4 &&
        !widget.isLoading;
  }

  bool _shouldResetScrollPositionOnExpand() {
    return widget.stage == 4 && widget.isCollapsible;
  }

  bool _isCompletedStage(int stage) => stage == 4 || stage == 5;

  @override
  void dispose() {
    _timer?.cancel();
    _collapseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    if (seconds < 60) {
      return '$seconds 秒';
    } else {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      return '$minutes 分 $remainingSeconds 秒';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasContent = widget.thinkingText.isNotEmpty;
    final bool canCollapse = widget.isCollapsible && widget.stage == 4;
    final secondaryTextColor = widget.textColor.withValues(alpha: 0.68);

    // 根据阶段显示不同的文案
    String hintText;
    switch (widget.stage) {
      case 1:
      case 2:
      case 3:
        hintText = '正在思考';
        break;
      case 4:
      case 5:
        hintText = '完成思考';
        break;
      default:
        hintText = '正在思考';
    }

    final header = canCollapse && hasContent
        ? InkWell(
            onTap: _toggleCollapsed,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ThinkingStatus(
                      isCompleted: _isCompletedStage(widget.stage),
                      hintText: hintText,
                      costTime: _formatTime(_elapsedSeconds),
                      shimmerText: !_isCompletedStage(widget.stage),
                      textStyle: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 12,
                        fontFamily: 'PingFang SC',
                        fontWeight: FontWeight.w400,
                        height: 1.50,
                        letterSpacing: 0.33,
                      ),
                    ),
                    const SizedBox(width: 2),
                    AnimatedBuilder(
                      animation: _collapseController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: (1 - _collapseController.value) * math.pi,
                          child: child,
                        );
                      },
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        : _ThinkingStatus(
            isCompleted: _isCompletedStage(widget.stage),
            hintText: hintText,
            costTime: _formatTime(_elapsedSeconds),
            shimmerText: !_isCompletedStage(widget.stage),
            textStyle: TextStyle(
              color: secondaryTextColor,
              fontSize: 12,
              fontFamily: 'PingFang SC',
              fontWeight: FontWeight.w400,
              height: 1.50,
              letterSpacing: 0.33,
            ),
          );

    final contentChild = (hasContent && widget.stage != 5)
        ? Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            margin: const EdgeInsets.only(top: 8.0),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: const Color(0x1A000000),
                  width: 1.0,
                ),
              ),
            ),
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    _checkOverflow();
                    final isUserDrivenUpdate =
                        (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null) ||
                        (notification is OverscrollNotification &&
                            notification.dragDetails != null);
                    if (isUserDrivenUpdate) {
                      _autoScrollToLatest =
                          (notification.metrics.maxScrollExtent -
                                  notification.metrics.pixels)
                              .abs() <=
                              _bottomTolerance;
                    } else if (notification is ScrollEndNotification &&
                        (notification.metrics.maxScrollExtent -
                                notification.metrics.pixels)
                            .abs() <=
                            _bottomTolerance) {
                      _autoScrollToLatest = true;
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const ClampingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.thinkingText,
                            style: TextStyle(
                              color: widget.textColor,
                              fontSize: 12,
                              fontFamily: 'PingFang SC',
                              fontWeight: FontWeight.w400,
                              height: 1.50,
                              letterSpacing: 0.33,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_showGradient)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 40,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(4),
                            bottomRight: Radius.circular(4),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xCCF1F8FF).withValues(alpha: 0.0),
                              const Color(0xCCF1F8FF).withValues(alpha: 0.8),
                              const Color(0xCCF1F8FF),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final content = canCollapse
        ? AnimatedBuilder(
            animation: _collapseController,
            child: RepaintBoundary(child: contentChild),
            builder: (context, child) {
              final sizeFactor = _collapseSizeFactor.value.clamp(0.0, 1.0);
              final opacity = _collapseOpacity.value.clamp(0.0, 1.0);
              if (sizeFactor <= 0.001 && !_collapseController.isAnimating) {
                return const SizedBox.shrink();
              }
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: sizeFactor,
                  child: IgnorePointer(
                    ignoring: sizeFactor <= 0.001,
                    child: Opacity(opacity: opacity, child: child),
                  ),
                ),
              );
            },
          )
        : contentChild;

    final footer = widget.stage == 5
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '任务已取消',
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 12,
                fontFamily: 'PingFang SC',
                fontWeight: FontWeight.w500,
                height: 1.83,
              ),
            ),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, content, if (footer != null) footer],
    );
  }
}

/// 思考状态指示器
class _ThinkingStatus extends StatelessWidget {
  const _ThinkingStatus({
    required this.isCompleted,
    required this.hintText,
    required this.costTime,
    required this.shimmerText,
    required this.textStyle,
  });

  final bool isCompleted;
  final String hintText;
  final String costTime;
  final bool shimmerText;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 状态指示点
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: isCompleted
                ? const Color(0xFF4CAF50)
                : const Color(0xFF2196F3),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        // 提示文本
        Text(
          hintText,
          style: textStyle.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),
        // 耗时
        Text(
          costTime,
          style: textStyle.copyWith(
            color: textStyle.color?.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}