import 'package:flutter/material.dart';
import '../../models/advanced_analytics_data.dart';
import '../../config/annual_report_texts.dart';
import 'warm_theme.dart';
import 'animated_components.dart';

class EmojiPersonalityCard extends StatefulWidget {
  final EmojiStats stats;

  const EmojiPersonalityCard({super.key, required this.stats});

  @override
  State<EmojiPersonalityCard> createState() => _EmojiPersonalityCardState();
}

class _EmojiPersonalityCardState extends State<EmojiPersonalityCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 呼吸动画控制器
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true); // 循环播放：放大 -> 缩小
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 根据人格标签获取背景色 (Step 1 中我们在 WarmTheme 定义了这些颜色)
  Color _getBackgroundColor(String tag) {
    if (tag.contains('快乐') || tag.contains('乐天') || tag.contains('烂梗')) return WarmTheme.personalityYellow;
    if (tag.contains('苦瓜') || tag.contains('悲伤') || tag.contains('迷糊')) return WarmTheme.personalityBlue;
    if (tag.contains('炸药') || tag.contains('怒')) return WarmTheme.personalityRed;
    if (tag.contains('社恐') || tag.contains('尴尬')) return WarmTheme.personalityPurple;
    if (tag.contains('社交') || tag.contains('商务') || tag.contains('天使')) return WarmTheme.personalityGreen;
    return WarmTheme.personalityGreen; // 默认
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _getBackgroundColor(widget.stats.personalityTag);
    // 获取 Top 1 表情，如果没有则显示默认
    final topEmoji = widget.stats.topEmojis.isNotEmpty ? widget.stats.topEmojis[0]['emoji'] : '😶';

    return Container(
      color: bgColor, // 全屏动态背景色
      child: Stack(
        children: [
          // 可选：添加噪点纹理增加质感 (如果有图片资源)
          Positioned.fill(
            child: Opacity(
              opacity: 0.05,
              child: Image.asset(
                'assets/images/noise.png',
                repeat: ImageRepeat.repeat,
                errorBuilder: (c, e, s) => const SizedBox(), // 如果没图就不显示，不报错
              ),
            ),
          ),
          
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeInText(
                  text: AnnualReportTexts.emojiTitle,
                  style: WarmTheme.getTitleStyle(color: Colors.black87),
                ),
                const SizedBox(height: 16),
                FadeInText(
                  text: AnnualReportTexts.emojiSubtitle,
                  delay: const Duration(milliseconds: 200),
                  style: WarmTheme.getSubtitleStyle(color: Colors.black54),
                ),
                const SizedBox(height: 60),

                // 核心表情呼吸动画
                ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.2).animate(
                    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
                  ),
                  child: Text(
                    topEmoji,
                    style: const TextStyle(fontSize: 120),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // 人格标签胶囊
                SlideInCard(
                  delay: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: Text(
                      widget.stats.personalityTag,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'HarmonyOS Sans SC',
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 80),

                // 次要表情展示 (Top 2-5)
                if (widget.stats.topEmojis.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: widget.stats.topEmojis.skip(1).take(4).map((e) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          e['emoji'],
                          style: const TextStyle(fontSize: 32),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
