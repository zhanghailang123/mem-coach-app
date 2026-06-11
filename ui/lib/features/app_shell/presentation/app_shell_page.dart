import 'dart:ui';
import 'package:flutter/material.dart';

import '../../coach/presentation/coach_home_page.dart';
import '../../exam/presentation/exam_bank_page.dart';
import '../../insight/presentation/insight_page.dart';
import '../../vocabulary/presentation/vocabulary_page.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({super.key});

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  int _currentIndex = 0;

  // 页面列表，保留 4 个主 Tab 页面
  static const _pages = [
    CoachHomePage(),
    ExamBankPage(),
    VocabularyPage(),
    InsightPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      // 使用 Stack 叠加悬浮 Dock 在主页面之上
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 20 + bottomPadding,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.78),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // 弹性滑动背景滑块，跳过正中央的 AI 圆钮位置
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        alignment: Alignment(
                          _currentIndex == 0 ? -1.0 :
                          (_currentIndex == 1 ? -0.33 :
                          (_currentIndex == 2 ? 0.33 : 1.0)),
                          0.0,
                        ),
                        child: FractionallySizedBox(
                          widthFactor: 1 / 4,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 前景导航按钮列表
                      Row(
                        children: [
                          Expanded(
                            child: _buildTabItem(
                              index: 0,
                              icon: Icons.home_outlined,
                              selectedIcon: Icons.home_rounded,
                              label: '首页',
                            ),
                          ),
                          Expanded(
                            child: _buildTabItem(
                              index: 1,
                              icon: Icons.school_outlined,
                              selectedIcon: Icons.school_rounded,
                              label: '真题',
                            ),
                          ),
                          Expanded(
                            child: _buildTabItem(
                              index: 2,
                              icon: Icons.book_outlined,
                              selectedIcon: Icons.book_rounded,
                              label: '单词',
                            ),
                          ),
                          Expanded(
                            child: _buildTabItem(
                              index: 3,
                              icon: Icons.insights_outlined,
                              selectedIcon: Icons.insights_rounded,
                              label: '学情',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Colors.black54;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _currentIndex = index);
      },
      child: Center(
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: isSelected ? 1.05 : 1.0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                color: color,
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
