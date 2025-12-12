import 'dart:ui';
import 'package:flutter/material.dart';
import '../../config/annual_report_texts.dart';
import 'warm_theme.dart';
import 'animated_components.dart';

class BlurredLetterView extends StatefulWidget {
  final String content;
  final String sentTo;
  final DateTime? time;
  final int length;

  const BlurredLetterView({
    super.key,
    required this.content,
    required this.sentTo,
    this.time,
    required this.length,
  });

  @override
  State<BlurredLetterView> createState() => _BlurredLetterViewState();
}

class _BlurredLetterViewState extends State<BlurredLetterView> {
  bool _isRevealed = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeInText(
            text: AnnualReportTexts.longMsgTitle,
            style: WarmTheme.getTitleStyle(),
          ),
          const SizedBox(height: 8),
          FadeInText(
            text: AnnualReportTexts.longMsgSubtitle,
            delay: const Duration(milliseconds: 200),
            style: WarmTheme.getSubtitleStyle(),
          ),
          const SizedBox(height: 40),

          // 信纸区域 - 核心交互
          GestureDetector(
            // 按下显示
            onLongPressStart: (_) => setState(() => _isRevealed = true),
            // 松开模糊
            onLongPressEnd: (_) => setState(() => _isRevealed = false),
            // 点击也可以切换状态（方便桌面端用户）
            onTapDown: (_) => setState(() => _isRevealed = true),
            onTapUp: (_) => setState(() => _isRevealed = false),
            onTapCancel: () => setState(() => _isRevealed = false),
            
            child: SlideInCard(
              delay: const Duration(milliseconds: 400),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 320,
                height: 450,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDFBF7), // 米色信纸
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: WarmTheme.getSoftShadow(),
                  // 如果有纹理图就显示，没有就纯色
                  image: const DecorationImage(
                    image: AssetImage('assets/images/paper_texture.png'),
                    fit: BoxFit.cover,
                    opacity: 0.3, // 淡淡的纹理
                  ),
                ),
                child: Stack(
                  children: [
                    // 底层：真实的文字内容
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'To: ${widget.sentTo}',
                          style: TextStyle(
                            fontFamily: 'HarmonyOS Sans SC',
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Text(
                            widget.content,
                            style: const TextStyle(
                              fontFamily: 'HarmonyOS Sans SC',
                              fontSize: 15,
                              height: 1.8,
                              color: Colors.black87,
                            ),
                            overflow: TextOverflow.fade, // 超出渐变消失
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.time != null 
                             ? '${widget.time!.year}.${widget.time!.month}.${widget.time!.day} ${widget.time!.hour}:${widget.time!.minute.toString().padLeft(2,'0')}' 
                             : '',
                          style: TextStyle(
                            fontFamily: 'HarmonyOS Sans SC',
                            fontSize: 12,
                            color: Colors.grey[400],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),

                    // 顶层：模糊遮罩 (当 _isRevealed 为 false 时显示)
                    IgnorePointer(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _isRevealed ? 0.0 : 1.0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), // 强力模糊，看不清字形
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.1),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 指纹图标
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: WarmTheme.primaryGreen.withOpacity(0.5), width: 2),
                                    ),
                                    child: Icon(Icons.fingerprint, size: 48, color: WarmTheme.primaryGreen.withOpacity(0.8)),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    AnnualReportTexts.longMsgHint,
                                    style: TextStyle(
                                      color: WarmTheme.primaryGreen.withOpacity(0.8),
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          FadeInText(
            text: '${AnnualReportTexts.longMsgLengthPrefix}${widget.length}${AnnualReportTexts.longMsgLengthSuffix}',
            delay: const Duration(milliseconds: 600),
            style: WarmTheme.getSubtitleStyle(),
          ),
        ],
      ),
    );
  }
}
