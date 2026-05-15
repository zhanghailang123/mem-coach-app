import 'package:flutter/material.dart';

/// 工具活动条组件
///
/// 显示 Agent 工具调用的实时状态，支持展开/折叠和进度可视化。
/// 借鉴 OpenOmniBot ChatToolActivityStrip 的设计。
class ToolActivityBar extends StatefulWidget {
  const ToolActivityBar({
    super.key,
    required this.toolActivities,
    this.onExpandedChanged,
    this.expanded = false,
  });

  /// 工具活动列表
  final List<ToolActivity> toolActivities;

  /// 展开状态变化回调
  final ValueChanged<bool>? onExpandedChanged;

  /// 是否展开
  final bool expanded;

  @override
  State<ToolActivityBar> createState() => _ToolActivityBarState();
}

class _ToolActivityBarState extends State<ToolActivityBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _heightFactor = _controller.drive(CurveTween(curve: Curves.easeOut));
    _expanded = widget.expanded;
    if (_expanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(ToolActivityBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      _expanded = widget.expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
    widget.onExpandedChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.toolActivities.isEmpty) {
      return const SizedBox.shrink();
    }

    final activeActivity = widget.toolActivities.lastWhere(
      (activity) => activity.status == ToolActivityStatus.running,
      orElse: () => widget.toolActivities.last,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 活动条头部
          _buildHeader(activeActivity),
          // 展开的内容
          SizeTransition(
            axisAlignment: 1.0,
            sizeFactor: _heightFactor,
            child: _buildExpandedContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ToolActivity activeActivity) {
    return GestureDetector(
      onTap: _toggleExpanded,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 工具类型图标
            _buildToolIcon(activeActivity.toolName),
            const SizedBox(width: 12),
            // 工具信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeActivity.toolName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF212121),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (activeActivity.summary != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      activeActivity.summary!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF757575),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // 状态指示器
            _buildStatusIndicator(activeActivity.status),
            const SizedBox(width: 8),
            // 展开/折叠图标
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: Color(0xFF757575),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    if (widget.toolActivities.length <= 1) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: widget.toolActivities.length - 1,
        itemBuilder: (context, index) {
          final activity = widget.toolActivities[index];
          return _buildActivityItem(activity);
        },
      ),
    );
  }

  Widget _buildActivityItem(ToolActivity activity) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _buildToolIcon(activity.toolName, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              activity.toolName,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF757575),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildStatusIndicator(activity.status, size: 12),
        ],
      ),
    );
  }

  Widget _buildToolIcon(String toolName, {double size = 20}) {
    IconData iconData;
    Color color;

    switch (toolName.toLowerCase()) {
      case 'search':
      case 'search_knowledge':
        iconData = Icons.search;
        color = const Color(0xFF2196F3);
        break;
      case 'calculate':
      case 'math':
        iconData = Icons.calculate;
        color = const Color(0xFF4CAF50);
        break;
      case 'pdf':
      case 'read_pdf':
        iconData = Icons.picture_as_pdf;
        color = const Color(0xFFF44336);
        break;
      case 'memory':
      case 'remember':
        iconData = Icons.memory;
        color = const Color(0xFF9C27B0);
        break;
      default:
        iconData = Icons.build;
        color = const Color(0xFFFF9800);
    }

    return Container(
      width: size + 8,
      height: size + 8,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        iconData,
        size: size,
        color: color,
      ),
    );
  }

  Widget _buildStatusIndicator(ToolActivityStatus status, {double size = 14}) {
    Color color;
    IconData iconData;

    switch (status) {
      case ToolActivityStatus.running:
        color = const Color(0xFF2196F3);
        iconData = Icons.sync;
        break;
      case ToolActivityStatus.success:
        color = const Color(0xFF4CAF50);
        iconData = Icons.check_circle;
        break;
      case ToolActivityStatus.error:
        color = const Color(0xFFF44336);
        iconData = Icons.error;
        break;
    }

    return SizedBox(
      width: size,
      height: size,
      child: status == ToolActivityStatus.running
          ? SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          : Icon(
              iconData,
              size: size,
              color: color,
            ),
    );
  }
}

/// 工具活动状态
enum ToolActivityStatus {
  running,
  success,
  error,
}

/// 工具活动数据
class ToolActivity {
  const ToolActivity({
    required this.toolName,
    this.status = ToolActivityStatus.running,
    this.summary,
    this.result,
    this.startTime,
    this.endTime,
  });

  final String toolName;
  final ToolActivityStatus status;
  final String? summary;
  final String? result;
  final DateTime? startTime;
  final DateTime? endTime;

  ToolActivity copyWith({
    String? toolName,
    ToolActivityStatus? status,
    String? summary,
    String? result,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return ToolActivity(
      toolName: toolName ?? this.toolName,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      result: result ?? this.result,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}