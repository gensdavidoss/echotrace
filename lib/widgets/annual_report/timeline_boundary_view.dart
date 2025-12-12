import 'package:flutter/material.dart';
import '../../models/advanced_analytics_data.dart';
import '../../config/annual_report_texts.dart';
import 'warm_theme.dart';
import 'animated_components.dart';

class TimelineBoundaryView extends StatelessWidget {
  final YearBoundaryStats stats;
  final int year;

  const TimelineBoundaryView({
    super.key, 
    required this.stats,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    if (stats.firstMessage == null || stats.lastMessage == null) {
      return const Center(child: Text(AnnualReportTexts.noData));
    }

    final first = stats.firstMessage!;
    final last = stats.lastMessage!;
    // 彩蛋判断：是否是同一个人
    final isSamePerson = first['username'] == last['username'];

    return Stack(
      children: [
        // 1. 背景渐变：上晨(橙黄) -> 下夜(深蓝灰)
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF3E0), Color(0xFFE8EAF6)], 
            ),
          ),
        ),

        // 2. 左侧时间轴连接线
        Positioned(
          left: 40,
          top: 120,
          bottom: 120,
          child: Container(
            width: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.orange.withOpacity(0.5), 
                  Colors.indigo.withOpacity(0.5)
                ],
              ),
            ),
          ),
        ),

        // 3. 内容区域
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FadeInText(
                  text: AnnualReportTexts.boundaryTitle,
                  style: WarmTheme.getTitleStyle(color: Colors.black87),
                ),
                const SizedBox(height: 8),
                FadeInText(
                  text: AnnualReportTexts.boundarySubtitle,
                  delay: const Duration(milliseconds: 200),
                  style: WarmTheme.getSubtitleStyle(),
                ),
                
                const Spacer(),

                // === 敲门人 (上半部) ===
                _buildMessageCard(
                  title: '$year的第一束光',
                  data: first,
                  isMorning: true,
                  delayMs: 400,
                ),

                // === 彩蛋徽章 (中间) ===
                if (isSamePerson)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: SlideInCard(
                        delay: const Duration(milliseconds: 1000),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: WarmTheme.warmPink, width: 1),
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.white,
                          ),
                          child: const Text(
                            AnnualReportTexts.boundaryBonus, // "始于TA，终于TA"
                            style: TextStyle(
                              fontSize: 12,
                              color: WarmTheme.warmPink,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),

                // === 守夜人 (下半部) ===
                _buildMessageCard(
                  title: AnnualReportTexts.boundaryEnd,
                  data: last,
                  isMorning: false,
                  delayMs: 600,
                ),

                const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageCard({
    required String title,
    required Map<String, dynamic> data,
    required bool isMorning,
    required int delayMs,
  }) {
    final dateStr = data['date'] as String;
    final date = DateTime.parse(dateStr);
    // 格式化时间 08:30
    final timeStr = '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    final dateLabel = '${date.month}月${date.day}日';
    
    // 获取颜色主题
    final themeColor = isMorning ? Colors.orange : Colors.indigo;
    final icon = isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded;

    return SlideInCard(
      delay: Duration(milliseconds: delayMs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧时间点
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: themeColor, width: 2),
                ),
                child: Icon(icon, size: 16, color: themeColor),
              ),
            ],
          ),
          const SizedBox(width: 16),
          
          // 右侧卡片
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: themeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: WarmTheme.getCardDecoration(
                    backgroundColor: Colors.white.withOpacity(0.9),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            data['displayName'],
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            '$dateLabel $timeStr',
                            style: TextStyle(color: Colors.grey[400], fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data['content'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
