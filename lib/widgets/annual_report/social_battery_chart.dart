import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/advanced_analytics_data.dart';
import '../../config/annual_report_texts.dart';
import 'warm_theme.dart';
import 'animated_components.dart';

class SocialBatteryChart extends StatelessWidget {
  final SocialBatteryStats stats;

  const SocialBatteryChart({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    // 构造数据点 (x: 月份 1-12, y: 计数)
    final spots = List.generate(stats.monthlyCounts.length, (index) {
      return FlSpot((index + 1).toDouble(), stats.monthlyCounts[index].toDouble());
    });
    
    // 计算Y轴最大值，用于图表缩放
    double maxY = 100;
    if (stats.monthlyCounts.isNotEmpty) {
       final maxCount = stats.monthlyCounts.reduce((curr, next) => curr > next ? curr : next);
       maxY = maxCount.toDouble() * 1.2; // 留出顶部空间给气泡
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeInText(
              text: AnnualReportTexts.batteryTitle,
              style: WarmTheme.getTitleStyle(color: WarmTheme.warmBlue),
            ),
            const SizedBox(height: 8),
            FadeInText(
              text: AnnualReportTexts.batterySubtitle,
              delay: const Duration(milliseconds: 200),
              style: WarmTheme.getSubtitleStyle(),
            ),
            const SizedBox(height: 60),

            // 图表区域
            SizedBox(
              height: 300,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false), // 不显示网格
                  titlesData: const FlTitlesData(show: false), // 不显示坐标轴文字
                  borderData: FlBorderData(show: false), // 不显示边框
                  minX: 1,
                  maxX: 12,
                  minY: 0,
                  maxY: maxY,
                  
                  // 曲线配置
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true, // 平滑曲线
                      curveSmoothness: 0.35,
                      color: WarmTheme.warmBlue,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false), // 默认隐藏所有点，下面单独画波峰波谷
                      
                      // 曲线下方填充渐变色
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            WarmTheme.warmBlue.withOpacity(0.4),
                            WarmTheme.warmBlue.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // 强制显示波峰和波谷的气泡
                  showingTooltipIndicators: [
                    ShowingTooltipIndicators([
                      LineBarSpot(
                          LineChartBarData(spots: spots), 
                          0, 
                          spots[stats.peakMonth - 1] // 波峰
                      ),
                    ]),
                    ShowingTooltipIndicators([
                      LineBarSpot(
                          LineChartBarData(spots: spots), 
                          0, 
                          spots[stats.lowMonth - 1] // 波谷
                      ),
                    ]),
                  ],

                  // 触摸与气泡配置
                  lineTouchData: LineTouchData(
                    enabled: false, // 禁止用户手动点击，固定显示
                    getTouchedSpotIndicator: (barData, spotIndexes) {
                      return spotIndexes.map((index) {
                        // 波峰实心点，波谷空心点
                        bool isPeak = (index + 1) == stats.peakMonth;
                        return TouchedSpotIndicatorData(
                          const FlLine(color: Colors.transparent), // 不显示垂直指示线
                          FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) {
                              return FlDotCirclePainter(
                                radius: 6,
                                color: isPeak ? WarmTheme.warmBlue : Colors.white,
                                strokeWidth: 3,
                                strokeColor: WarmTheme.warmBlue,
                              );
                            },
                          ),
                        );
                      }).toList();
                    },
                    
                    // 气泡样式
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (spot) => Colors.transparent, // 气泡背景透明
                      tooltipPadding: EdgeInsets.zero,
                      tooltipMargin: 10,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          bool isPeak = (spot.x.toInt()) == stats.peakMonth;
                          final text = isPeak 
                              ? '${spot.x.toInt()}月${AnnualReportTexts.batteryPeak}' 
                              : '${spot.x.toInt()}月${AnnualReportTexts.batteryLow}';
                          
                          return LineTooltipItem(
                            text,
                            TextStyle(
                              color: isPeak ? WarmTheme.warmBlue : Colors.grey[400],
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              fontFamily: 'HarmonyOS Sans SC',
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
