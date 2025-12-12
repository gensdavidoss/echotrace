import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../../config/annual_report_texts.dart';
import 'warm_theme.dart';
import 'animated_components.dart';

class LaughterParticleView extends StatefulWidget {
  final int totalHaha;
  final int longestHaha;
  final String longestHahaText;

  const LaughterParticleView({
    super.key,
    required this.totalHaha,
    required this.longestHaha,
    required this.longestHahaText,
  });

  @override
  State<LaughterParticleView> createState() => _LaughterParticleViewState();
}

class _LaughterParticleViewState extends State<LaughterParticleView> {
  late ConfettiController _confettiController;
  final Random _random = Random();
  
  // 模拟弹幕词库
  final List<String> _danmakuTexts = [
    '哈哈哈哈', 'xswl', '红红火火', '笑死', 'hhhhhh', '23333', 
    '笑出猪叫', '哈哈哈哈哈哈哈哈', '救命', '好家伙', 'Lol', 'ROFL'
  ];

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    // 页面进入后延迟播放爆炸效果
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _confettiController.play();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. 弹幕层 (生成8条随机轨道的弹幕)
        ...List.generate(8, (index) => _buildDanmakuItem(index)),

        // 2. 核心内容层
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FadeInText(
                text: AnnualReportTexts.laughterTitle,
                style: WarmTheme.getTitleStyle(color: WarmTheme.warmOrange),
              ),
              const SizedBox(height: 16),
              FadeInText(
                text: AnnualReportTexts.laughterSubtitle,
                delay: const Duration(milliseconds: 200),
                style: WarmTheme.getSubtitleStyle(),
              ),
              const SizedBox(height: 40),
              
              // 粒子爆炸源与数字展示
              Stack(
                alignment: Alignment.center,
                children: [
                  ConfettiWidget(
                    confettiController: _confettiController,
                    blastDirectionality: BlastDirectionality.explosive,
                    shouldLoop: false,
                    colors: const [
                      WarmTheme.warmOrange,
                      WarmTheme.warmOrangeLight,
                      Colors.redAccent,
                      Colors.yellow,
                    ],
                    gravity: 0.2,
                  ),
                  SlideInCard(
                    delay: const Duration(milliseconds: 300),
                    child: Text(
                      '${widget.totalHaha}',
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        color: WarmTheme.warmOrange,
                        fontFamily: 'HarmonyOS Sans SC',
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              FadeInText(
                text: '${AnnualReportTexts.laughterTotalPrefix}${AnnualReportTexts.laughterTotalSuffix}',
                delay: const Duration(milliseconds: 500),
                style: WarmTheme.getSubtitleStyle(),
              ),

              const SizedBox(height: 60),

              // 最长笑声展示区
              _buildLongestHahaCard(),
            ],
          ),
        ),
      ],
    );
  }

  // 构建单条弹幕
  Widget _buildDanmakuItem(int index) {
    // 随机参数
    final duration = 5 + _random.nextInt(5); // 5-10秒
    final top = 50.0 + _random.nextInt(600); // 随机高度
    final text = _danmakuTexts[_random.nextInt(_danmakuTexts.length)];
    final fontSize = 14.0 + _random.nextInt(10);
    final delay = _random.nextInt(2000); // 随机延迟启动
    
    return Positioned(
      top: top,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.2, end: -0.5), // 从屏幕右侧外(1.2)到左侧外(-0.5)
        duration: Duration(seconds: duration),
        curve: Curves.linear,
        builder: (context, value, child) {
          // 获取屏幕宽度进行偏移计算
          final screenWidth = MediaQuery.of(context).size.width;
          return Transform.translate(
            offset: Offset(value * screenWidth, 0),
            child: Opacity(
              opacity: 0.2, // 淡淡的背景效果
              child: Text(
                text,
                style: TextStyle(
                  fontSize: fontSize,
                  color: WarmTheme.warmOrange,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'HarmonyOS Sans SC',
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 最长笑声卡片
  Widget _buildLongestHahaCard() {
    return SlideInCard(
      delay: const Duration(milliseconds: 800),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(20),
        decoration: WarmTheme.getCardDecoration(backgroundColor: Colors.white.withValues(alpha: 0.9)),
        child: Column(
          children: [
             Text(
              '${AnnualReportTexts.laughterLongestPrefix}${widget.longestHaha}${AnnualReportTexts.laughterLongestSuffix}',
              textAlign: TextAlign.center,
              style: WarmTheme.getWarmTextStyle(fontSize: 14, color: WarmTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: WarmTheme.warmOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill, color: WarmTheme.warmOrange, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.longestHahaText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WarmTheme.warmOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
