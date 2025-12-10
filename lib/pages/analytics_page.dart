import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/app_state.dart';
import '../services/analytics_service.dart';
import '../services/database_service.dart';
import '../services/analytics_cache_service.dart';
import '../services/logger_service.dart';
import '../models/analytics_data.dart';
import '../utils/string_utils.dart';
import 'annual_report_display_page.dart';

/// 数据分析页面 - 最终修正版
class AnalyticsPage extends StatefulWidget {
  final DatabaseService databaseService;

  const AnalyticsPage({super.key, required this.databaseService});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  late AnalyticsService _analyticsService;
  bool _isLoading = false;
  
  // ==================== 状态管理 ====================
  // 当前选中的年份 (null 代表全部)
  int? _selectedYear; 
  // 可选的年份列表
  List<int> _availableYears = []; 

  ChatStatistics? _overallStats;
  List<ContactRanking>? _contactRankings;
  List<ContactRanking>? _allContactRankings; 

  // 加载进度状态
  String _loadingStatus = '';
  int _processedCount = 0;
  int _totalCount = 0;

  // Top N 选择
  int _topN = 10;

  @override
  void initState() {
    super.initState();
    _analyticsService = AnalyticsService(widget.databaseService);
    // 延迟到下一帧执行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  /// 初始加载数据
  Future<void> _loadData() async {
    if (!widget.databaseService.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先连接数据库')));
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadingStatus = '正在准备数据...';
      _processedCount = 0;
      _totalCount = 0;
    });

    try {
      // 首次加载，默认分析全部数据，以此来计算时间跨度
      await _performAnalysis(DateTime.now().millisecondsSinceEpoch);
    } catch (e, stackTrace) {
      await logger.error('AnalyticsPage', '加载数据失败: $e', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  /// 计算有哪些年份可选 (基于统计数据)
  void _calculateAvailableYears() {
    final currentYear = DateTime.now().year;
    int startYear = currentYear;

    // 尝试从统计数据中获取最早年份
    if (_overallStats != null && _overallStats!.firstMessageTime != null) {
      startYear = _overallStats!.firstMessageTime!.year;
    }

    if (startYear > currentYear) startYear = currentYear;

    // 生成年份列表 (从今年倒推到最早年份)
    final years = <int>[];
    for (int y = currentYear; y >= startYear; y--) {
      years.add(y);
    }
    
    // 只有当列表真正变化时才更新状态
    if (years.length != _availableYears.length || (years.isNotEmpty && years.first != _availableYears.first)) {
       setState(() {
         _availableYears = years;
       });
    }
  }

  /// 核心分析逻辑：执行数据分析
  Future<void> _performAnalysis(int dbModifiedTime) async {
    final cacheService = AnalyticsCacheService.instance;

    if (!mounted) return;
    setState(() {
        _isLoading = true;
        _loadingStatus = _selectedYear == null 
            ? '正在分析全部历史数据...' 
            : '正在分析 $_selectedYear 年数据...';
    });

    try {
      // 1. 获取总体统计
      ChatStatistics stats;
      
      // 根据是否选择了年份，调用不同的 Service 方法
      if (_selectedYear == null) {
        // === 查全部 ===
        stats = await _analyticsService.analyzeAllPrivateChats();
      } else {
        // === 查特定年份 ===
        stats = await _analyticsService.analyzeYearlyPrivateChats(_selectedYear!);
      }

      if (!mounted) return;
      setState(() {
        _overallStats = stats;
        // 每次分析完都重新确认一下年份列表（防止首次加载时列表为空）
        _calculateAvailableYears();
      });

      // 2. 获取联系人排名 (这一步非常关键，数据量大时会比较慢)
      setState(() => _loadingStatus = '正在统计联系人排名...');
      
      final rankings = await _loadRankingsWithProgress();

      // 3. 只有在“查全部”模式下才保存全局缓存，避免单年数据覆盖了全局缓存
      if (_selectedYear == null) {
        await cacheService.saveBasicAnalytics(
          overallStats: _overallStats,
          contactRankings: rankings,
          dbModifiedTime: dbModifiedTime,
        );
      }

      if (!mounted) return;
      setState(() {
        _allContactRankings = rankings;
        _contactRankings = rankings.take(_topN).toList();
        _loadingStatus = '完成';
        _isLoading = false;
      });
      
    } catch (e) {
       // 错误处理
       if (mounted) setState(() => _isLoading = false);
       rethrow;
    }
  }

  /// 加载联系人排名 (支持年份筛选)
  Future<List<ContactRanking>> _loadRankingsWithProgress() async {
    final sessions = await widget.databaseService.getSessions();
    final privateSessions = sessions.where((s) => !s.isGroup).toList();

    if (!mounted) return [];
    setState(() {
      _totalCount = privateSessions.length;
      _processedCount = 0;
    });

    final rankings = <ContactRanking>[];
    final displayNames = await widget.databaseService.getDisplayNames(
      privateSessions.map((s) => s.username).toList(),
    );

    // 预取头像
    try {
      if (mounted) {
        final appState = context.read<AppState>();
        await appState.fetchAndCacheAvatars(privateSessions.map((s) => s.username).toList());
      }
    } catch (_) {}

    // 如果选了年份，先算出起止时间戳
    DateTime? startDate;
    DateTime? endDate;
    if (_selectedYear != null) {
      startDate = DateTime(_selectedYear!, 1, 1);
      endDate = DateTime(_selectedYear!, 12, 31, 23, 59, 59);
    }

    for (var i = 0; i < privateSessions.length; i++) {
      if (!mounted) break;
      final session = privateSessions[i];
      
      setState(() {
        _processedCount = i + 1;
        _loadingStatus = '正在分析: ${displayNames[session.username] ?? session.username}';
      });

      // 防止界面卡死，每处理20个暂停一下
      if (i % 20 == 0) await Future.delayed(Duration.zero);

      try {
        int messageCount = 0;
        int sentCount = 0;
        int receivedCount = 0;

        // === 分支逻辑 ===
        if (_selectedYear == null) {
            // A. 全部年份：直接查数据库统计表（极快）
            final stats = await widget.databaseService.getSessionMessageStats(session.username);
            messageCount = stats['total'] as int;
            sentCount = stats['sent'] as int;
            receivedCount = stats['received'] as int;
        } else {
            // B. 指定年份：必须查具体消息表（较慢，但准确）
            // 先粗略判断总数，如果总数是0就别查了
            final globalStats = await widget.databaseService.getSessionMessageStats(session.username);
            if ((globalStats['total'] as int) == 0) continue;

            // 调用 Service 获取该时间段消息
            final msgs = await _analyticsService.getMessagesByDateRange(
                session.username, 
                startDate!, 
                endDate!
            );
            
            messageCount = msgs.length;
            if (messageCount > 0) {
               sentCount = msgs.where((m) => m.isSend == 1).length;
               receivedCount = messageCount - sentCount;
            }
        }

        if (messageCount == 0) continue;

        rankings.add(
          ContactRanking(
            username: session.username,
            displayName: displayNames[session.username] ?? session.username,
            messageCount: messageCount,
            sentCount: sentCount,
            receivedCount: receivedCount,
            lastMessageTime: null, // 简化处理
          ),
        );
      } catch (e) {
        // 忽略单个错误
      }
    }

    // 排序
    rankings.sort((a, b) => b.messageCount.compareTo(a.messageCount));
    
    // 只取前 50 名，避免内存爆炸
    return rankings.take(50).toList();
  }

  // ==================== 界面交互逻辑 ====================

  /// 弹出年份选择菜单
  void _showYearSelectionMenu() {
    if (_isLoading) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('选择分析年份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    // 选项：全部年份
                    ListTile(
                      leading: const Icon(Icons.calendar_view_month),
                      title: const Text('全部年份 (历史累计)'),
                      trailing: _selectedYear == null ? const Icon(Icons.check, color: Colors.green) : null,
                      onTap: () {
                        Navigator.pop(context);
                        if (_selectedYear != null) {
                          setState(() => _selectedYear = null);
                          // 触发重新分析
                          _performAnalysis(DateTime.now().millisecondsSinceEpoch);
                        }
                      },
                    ),
                    // 选项：具体年份列表
                    ..._availableYears.map((year) {
                      return ListTile(
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: Text('$year年'),
                        trailing: _selectedYear == year ? const Icon(Icons.check, color: Colors.green) : null,
                        onTap: () {
                          Navigator.pop(context);
                          if (_selectedYear != year) {
                            setState(() => _selectedYear = year);
                            // 触发重新分析
                            _performAnalysis(DateTime.now().millisecondsSinceEpoch);
                          }
                        },
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 跳转到年度报告页面
  Future<void> _navigateToReport(int? year) async {
    if (_isLoading) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnnualReportDisplayPage(
          databaseService: widget.databaseService,
          year: year,
        ),
      ),
    );
  }

  // ==================== UI 构建部分 ====================

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? _buildLoadingView()
                : _overallStats == null
                ? _buildEmptyView()
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics_outlined, size: 28, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            '数据分析',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _performAnalysis(DateTime.now().millisecondsSinceEpoch),
              tooltip: '刷新数据',
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            value: _totalCount > 0 ? _processedCount / _totalCount : null,
          ),
          const SizedBox(height: 16),
          Text(
            _loadingStatus,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_totalCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '进度: $_processedCount / $_totalCount',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('暂无数据', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. 年份筛选按钮 (这是你要的新交互)
        _buildYearFilterButton(),
        
        // 2. 年度报告入口卡片
        _buildAnnualReportEntry(),
        const SizedBox(height: 16),

        // 3. 总体统计 (会随年份变化)
        _buildOverallStatsCard(),
        const SizedBox(height: 16),
        _buildMessageTypeChart(),
        const SizedBox(height: 16),
        
        // 4. 发送接收比例
        _buildSendReceiveChart(),
        const SizedBox(height: 16),
        
        // 5. 联系人排名 (会随年份变化)
        _buildContactRankingCard(),
      ],
    );
  }

  /// 构建年份筛选按钮 (替换原来的横向列表)
  Widget _buildYearFilterButton() {
    final text = _selectedYear == null ? '📅  全部年份 (历史累计)' : '📅  $_selectedYear 年数据';
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showYearSelectionMenu,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          // 右侧显示提示
          Text(
            '点击左侧按钮切换年份',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// 年度报告入口卡片
  Widget _buildAnnualReportEntry() {
    const wechatGreen = Color(0xFF07C160);
    // 动态标题
    final title = _selectedYear == null 
        ? '生成详细年度报告' 
        : '生成 $_selectedYear 年度报告';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: wechatGreen, width: 1),
      ),
      child: InkWell(
        onTap: () => _navigateToReport(_selectedYear),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [Colors.white, wechatGreen.withValues(alpha: 0.05)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: wechatGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.description_outlined, color: wechatGreen),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点击查看深度分析，发现更多有趣洞察',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverallStatsCard() {
    final stats = _overallStats!;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  _selectedYear == null ? '私聊总体统计' : '$_selectedYear 年数据统计',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildStatRow('总消息数', stats.totalMessages.toString()),
            _buildStatRow('活跃天数', stats.activeDays.toString()),
            _buildStatRow('平均每天', stats.averageMessagesPerDay.toStringAsFixed(1)),
            if (stats.firstMessageTime != null)
              _buildStatRow('时间跨度', '${_formatDateTime(stats.firstMessageTime!)} 至 ${_formatDateTime(stats.lastMessageTime ?? DateTime.now())}'),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageTypeChart() {
    final stats = _overallStats!;
    final distribution = stats.messageTypeDistribution;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
              children: [
                const Icon(Icons.pie_chart, size: 20, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('消息类型分布', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            ...distribution.entries.map((entry) {
              final percentage = stats.totalMessages > 0
                  ? (entry.value / stats.totalMessages * 100).toStringAsFixed(1)
                  : '0.0';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 50, child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w500))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: stats.totalMessages > 0 ? entry.value / stats.totalMessages : 0,
                          backgroundColor: Colors.grey[100],
                          minHeight: 8,
                          valueColor: AlwaysStoppedAnimation<Color>(_getColorForType(entry.key)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100, 
                      child: Text(
                        '${entry.value} ($percentage%)', 
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      )
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _getColorForType(String type) {
    switch (type) {
      case '文本': return const Color(0xFF07C160);
      case '图片': return Colors.blue;
      case '语音': return Colors.orange;
      case '视频': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildSendReceiveChart() {
    final stats = _overallStats!;
    final ratio = stats.sendReceiveRatio;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows, size: 20, color: Colors.purple),
                const SizedBox(width: 8),
                const Text('发送/接收比例', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            ...ratio.entries.map((entry) {
               final percentage = stats.totalMessages > 0
                  ? (entry.value / stats.totalMessages * 100).toStringAsFixed(1)
                  : '0.0';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 50, child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w500))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: stats.totalMessages > 0 ? entry.value / stats.totalMessages : 0,
                          backgroundColor: Colors.grey[100],
                          minHeight: 8,
                          color: entry.key == '发送' ? Colors.blueAccent : Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100, 
                      child: Text(
                        '${entry.value} ($percentage%)', 
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      )
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildContactRankingCard() {
    if (_contactRankings == null || _contactRankings!.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.leaderboard, size: 20, color: Colors.amber),
                    const SizedBox(width: 8),
                    Text('Top $_topN 联系人', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                // 简单的 Top N 切换
                DropdownButton<int>(
                  value: _topN,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 10, child: Text("Top 10")),
                    DropdownMenuItem(value: 20, child: Text("Top 20")),
                    DropdownMenuItem(value: 50, child: Text("Top 50")),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _topN = val;
                        _contactRankings = _allContactRankings?.take(_topN).toList();
                      });
                    }
                  }
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _contactRankings!.length,
              separatorBuilder: (ctx, index) => const Divider(height: 1),
              itemBuilder: (ctx, index) {
                final ranking = _contactRankings![index];
                final appState = Provider.of<AppState>(context);
                final avatarUrl = appState.getAvatarUrl(ranking.username);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _AvatarWithRank(
                    avatarUrl: avatarUrl,
                    rank: index + 1,
                    displayName: ranking.displayName,
                  ),
                  title: Text(
                    StringUtils.cleanOrDefault(ranking.displayName, ranking.username),
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '发送: ${ranking.sentCount} | 接收: ${ranking.receivedCount}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${ranking.messageCount}', 
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }
}

// 独立的头像组件，样式美观
class _AvatarWithRank extends StatelessWidget {
  final String? avatarUrl;
  final int rank;
  final String displayName;

  const _AvatarWithRank({
    required this.avatarUrl,
    required this.rank,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    final fallbackText = StringUtils.getFirstChar(displayName, defaultChar: '聊');

    Color rankColor;
    if (rank == 1) rankColor = const Color(0xFFFFD700); // 金
    else if (rank == 2) rankColor = const Color(0xFFC0C0C0); // 银
    else if (rank == 3) rankColor = const Color(0xFFCD7F32); // 铜
    else rankColor = Theme.of(context).colorScheme.primary;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
          ),
          child: hasAvatar
            ? CachedNetworkImage(
                imageUrl: avatarUrl!,
                imageBuilder: (context, imageProvider) => CircleAvatar(
                  backgroundImage: imageProvider,
                ),
                placeholder: (context, url) => CircleAvatar(backgroundColor: Colors.grey[200], child: Text(fallbackText)),
                errorWidget: (context, url, error) => CircleAvatar(backgroundColor: Colors.grey[200], child: Text(fallbackText)),
              )
            : CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                child: Text(
                  fallbackText,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
        ),
        Positioned(
          bottom: -2, right: -2,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: rankColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                 BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2),
              ]
            ),
            child: Center(
              child: Text(
                '$rank', 
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
