import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/advanced_analytics_data.dart';
import '../../config/annual_report_texts.dart';
import 'warm_theme.dart';
import 'animated_components.dart';

class ReceiptIngredientCard extends StatelessWidget {
  final List<MessageTypeStats> stats;
  final int totalMessages;

  const ReceiptIngredientCard({
    super.key,
    required this.stats,
    required this.totalMessages,
  });

  @override
  Widget build(BuildContext context) {
    final stampType = _determineStampType();

    return Center(
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          // 购物小票主体
          CustomPaint(
            painter: ReceiptPainter(color: Colors.white),
            child: Container(
              width: 320,
              // 底部留出锯齿空间
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 48), 
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 小票头部
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long, color: Colors.grey[400], size: 32),
                        const SizedBox(height: 8),
                        Text(
                          AnnualReportTexts.ingredientTitle,
                          style: TextStyle(
                            fontFamily: 'HarmonyOS Sans SC',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.grey[800],
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          '2024 SOCIAL RECEIPT',
                          style: TextStyle(
                            fontFamily: 'Courier', // 英文部分用 Courier 更像小票
                            fontSize: 10,
                            color: Colors.grey[400],
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.black12, thickness: 1, height: 1),
                  const SizedBox(height: 4),
                  const Divider(color: Colors.black12, thickness: 1, height: 1),
                  const SizedBox(height: 16),

                  // 列表项
                  ...stats.take(6).map((item) => _buildReceiptItem(item)),

                  const SizedBox(height: 16),
                  const Divider(color: Colors.black12, thickness: 1, height: 1),
                  const SizedBox(height: 12),
                  
                  // 底部合计
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL ITEM', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                      Text('$totalMessages', style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      AnnualReportTexts.ingredientSubtitle,
                      style: TextStyle(fontFamily: 'HarmonyOS Sans SC', fontSize: 10, color: Colors.grey[400]),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 盖章动画
          Positioned(
            bottom: 60,
            right: 20,
            child: SlideInCard( // 复用动画组件做弹出效果
              delay: const Duration(milliseconds: 1000),
              child: Transform.rotate(
                angle: -pi / 6, // 倾斜印章
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red.withOpacity(0.7), width: 3),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white.withOpacity(0.5), // 微微透白，模仿印泥
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stampType,
                        style: TextStyle(
                          color: Colors.red.withOpacity(0.8),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'HarmonyOS Sans SC',
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        'CERTIFIED',
                        style: TextStyle(
                          color: Colors.red.withOpacity(0.6),
                          fontSize: 8,
                          fontFamily: 'Courier',
                          letterSpacing: 4,
                        ),
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

  // 构建单行成分
  Widget _buildReceiptItem(MessageTypeStats item) {
    String label = item.typeName;
    // 简单的文案映射
    if (item.typeName.contains('文本')) label = AnnualReportTexts.labelText;
    if (item.typeName.contains('图片') || item.typeName.contains('视频')) label = AnnualReportTexts.labelImage;
    if (item.typeName.contains('语音')) label = AnnualReportTexts.labelVoice;
    if (item.typeName.contains('表情') || item.typeName.contains('动画')) label = AnnualReportTexts.labelEmoji;
    if (item.typeName.contains('红包') || item.typeName.contains('转账')) label = AnnualReportTexts.labelMoney;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontFamily: 'HarmonyOS Sans SC', fontSize: 14, color: Colors.black87),
          ),
          Row(
            children: [
              Text(
                '${(item.percentage * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontFamily: 'Courier', fontSize: 14, color: Colors.black87),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 判定盖章逻辑（混合双打）
  String _determineStampType() {
    int moneyCount = 0;
    int voiceCount = 0;
    int imageCount = 0;
    int emojiCount = 0;

    for (var s in stats) {
      if (s.typeName.contains('红包') || s.typeName.contains('转账')) moneyCount += s.count;
      if (s.typeName.contains('语音')) voiceCount += s.count;
      if (s.typeName.contains('图片') || s.typeName.contains('视频')) imageCount += s.count;
      if (s.typeName.contains('动画') || s.typeName.contains('表情')) emojiCount += s.count;
    }

    if (totalMessages == 0) return AnnualReportTexts.stampText;

    double moneyPct = moneyCount / totalMessages;
    double voicePct = voiceCount / totalMessages;
    double imagePct = imageCount / totalMessages;
    double emojiPct = emojiCount / totalMessages;

    // 判定逻辑（遵照用户需求）
    // 1. 多财多亿 (红包>0.8% 或 >300个)
    if (moneyPct > 0.008 || moneyCount > 300) return AnnualReportTexts.stampMoney;
    // 2. 语音狂魔 (语音>8% 或 >800个)
    if (voicePct > 0.08 || voiceCount > 800) return AnnualReportTexts.stampVoice;
    // 3. 生活记录员 (图片视频>12% 或 >10000个)
    if (imagePct > 0.12 || imageCount > 10000) return AnnualReportTexts.stampImage;
    // 4. 斗图王者 (表情>10% 或 >4000个)
    if (emojiPct > 0.10 || emojiCount > 4000) return AnnualReportTexts.stampEmoji;
    
    // 5. 键盘钢琴家 (兜底)
    return AnnualReportTexts.stampText; 
  }
}

// 绘制锯齿边缘的 Painter
class ReceiptPainter extends CustomPainter {
  final Color color;
  ReceiptPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    
    // 左上角开始
    path.moveTo(0, 0);
    // 右上角
    path.lineTo(size.width, 0);
    // 右下角（不含锯齿部分）
    path.lineTo(size.width, size.height - 10);
    
    // 绘制底部锯齿
    const toothWidth = 10.0;
    final toothCount = (size.width / toothWidth).ceil();
    for (int i = 0; i < toothCount; i++) {
      double x = size.width - (i * toothWidth);
      path.lineTo(x - toothWidth / 2, size.height); // 齿尖
      path.lineTo(x - toothWidth, size.height - 10); // 齿谷
    }
    
    // 左下角闭合
    path.lineTo(0, size.height - 10);
    path.close();

    // 添加阴影
    canvas.drawShadow(path, Colors.black.withOpacity(0.2), 6.0, false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
