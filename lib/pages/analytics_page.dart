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

/// 数据分析页面
class AnalyticsPage extends StatefulWidget {
  final DatabaseService databaseService;

  const AnalyticsPage({super.key, required this.databaseService});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  late AnalyticsService _analyticsService;
  bool _isLoading = false;
  
  // ==================== 新增：年份筛选状态 ====================
  int? _selectedYear; // null 代表全部年份
  List<int> _availableYears = []; 
  // ========================================================

  ChatStatistics? _overallStats;
  List<ContactRanking>? _contactRankings;
  List<ContactRanking>? _allContactRankings; // 保存所有排名

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
    // 延迟到下一帧执行，避免在 initState 中使用 context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    await logger.debug('AnalyticsPage', '========== 开始加载数据分析 ==========');

    if (!widget.databaseService.isConnected) {
      await logger.warning('AnalyticsPage', '数据库未连接');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先连接数据库')));
      }
      return;
    }

    await logger.debug('AnalyticsPage', '数据库已连接，开始加载数据');

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadingStatus = '正在检查缓存...';
      _processedCount = 0;
      _totalCount = 0;
    });

    try {
      final dbTime = await _getDbModifiedTime();
      // 首次加载，默认分析全部数据
      await _performAnalysis(dbTime);

    } catch (e, stackTrace) {
      await logger.error('AnalyticsPage', '加载数据失败: $e', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载数据失败: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  /// 获取数据库文件修改时间
  Future<int> _getDbModifiedTime() async {
    final dbPath = widget.databaseService.dbPath;
    if (dbPath != null) {
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        final stat = await dbFile.stat();
        return stat.modified.millisecondsSinceEpoch;
      }
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// 计算有哪些年份可选
  void _calculateAvailableYears() {
    final currentYear = DateTime.now().year;
    int startYear = currentYear;

    // 尝试从统计数据中获取最早年份
    if (_overallStats != null && _overallStats!.firstMessageTime != null) {
      startYear = _overallStats!.firstMessageTime!.year;
    }

    if (startYear > currentYear) startYear = currentYear;

    // 生成年份列表
    final years = <int>[];
    for (int y = currentYear; y >= startYear; y--) {
      years.add(y);
    }
    
    if (years.length != _availableYears.length || (years.isNotEmpty && years.first != _availableYears.first)) {
       setState(() => _availableYears = years);
    }
  }

  /// 核心分析逻辑（整合了缓存和高性能计算）
  Future<void> _performAnalysis(int dbModifiedTime) async {
    await logger.debug('AnalyticsPage', '========== 开始执行数据分析 ==========');
    final cacheService = AnalyticsCacheService.instance;

    if (!mounted) return;
    setState(() {
       _isLoading = true;
       _loadingStatus = _selectedYear == null 
           ? '正在分析所有私聊数据...' 
           : '正在分析 $_selectedYear 年数据...';
    });

    try {
      ChatStatistics? stats;
      List<ContactRanking>? rankings;

      // 1. 【缓存检查】
      if (_selectedYear != null) {
        // --- 单年模式：查单年缓存 ---
        final cachedData = await cacheService.loadYearlyData(_selectedYear!, dbModifiedTime);
        if (cachedData != null) {
          stats = cachedData['stats'] as ChatStatistics;
          rankings = cachedData['rankings'] as List<ContactRanking>;
          await logger.info('AnalyticsPage', '命中 $_selectedYear 年缓存，直接显示');
        }
      } else {
        // --- 全部模式：查原有缓存 ---
        final cachedBasic = await cacheService.loadBasicAnalytics();
        if (cachedBasic != null) {
          final isChanged = await cacheService.isDatabaseChanged(dbModifiedTime);
          if (!isChanged) {
             stats = cachedBasic['overallStats'];
             rankings = cachedBasic['contactRankings'];
             await logger.info('AnalyticsPage', '命中全部数据缓存');
          }
        }
      }

      // 2. 【计算逻辑】(如果无缓存)
      if (stats == null) {
        if (_selectedYear == null) {
          // === 方案A：全部年份 (原有逻辑) ===
          stats = await _analyticsService.analyzeAllPrivateChats();
          
          setState(() => _loadingStatus = '正在统计联系人排名...');
          rankings = await _loadRankingsWithProgress(); // 使用原有的进度条加载方式

          // 保存缓存
          await cacheService.saveBasicAnalytics(
            overallStats: stats,
            contactRankings: rankings,
            dbModifiedTime: dbModifiedTime,
          );
        } else {
          // === 方案B：指定年份 (新的高性能逻辑) ===
          // 调用 Service 中新加的 analyzeYearlyData 方法
          // 注意：需要在 AnalyticsService 中确保添加了该方法
          final result = await _analyticsService.analyzeYearlyData(_selectedYear!);
          stats = result['stats'] as ChatStatistics;
          rankings = result['rankings'] as List<ContactRanking>;

          // 保存缓存
          await cacheService.saveYearlyData(
            year: _selectedYear!,
            stats: stats,
            rankings: rankings,
            dbModifiedTime: dbModifiedTime,
          );
        }
      }

      // 3. 【更新界面】
      if (!mounted) return;
      setState(() {
        _overallStats = stats;
        _allContactRankings = rankings;
        // 根据当前的 Top N 截取
        _contactRankings = rankings!.take(_topN).toList();
        _loadingStatus = '完成';
        _isLoading = false;
        // 刷新年份列表
        _calculateAvailableYears();
      });

    } catch (e, stackTrace) {
      await logger.error('AnalyticsPage', '分析失败: $e', e, stackTrace);
      if (mounted) {
         setState(() => _isLoading = false);
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分析失败: $e')));
      }
    }
  }

  // 保留原有的加载排名方法（用于"全部年份"模式）
  Future<List<ContactRanking>> _loadRankingsWithProgress() async {
    await logger.debug('AnalyticsPage', '开始加载联系人排名（带进度）');

    final sessions = await widget.databaseService.getSessions();
    final privateSessions = sessions.where((s) => !s.isGroup).toList();
    await logger.debug('AnalyticsPage', '获取到 ${privateSessions.length} 个私聊会话');

    if (!mounted) return [];
    setState(() {
      _totalCount = privateSessions.length;
      _processedCount = 0;
    });

    final rankings = <ContactRanking>[];
    final displayNames = await widget.databaseService.getDisplayNames(
      privateSessions.map((s) => s.username).toList(),
    );
    
    try {
      final appState = context.read<AppState>();
      await appState.fetchAndCacheAvatars(
        privateSessions.map((s) => s.username).toList(),
      );
    } catch (_) {}

    int skippedCount = 0;

    for (var i = 0; i < privateSessions.length; i++) {
      final session = privateSessions[i];
      if (!mounted) break;
      
      // 更新进度
      setState(() {
        _processedCount = i + 1;
        _loadingStatus = '正在分析: ${displayNames[session.username] ?? session.username}';
      });

      // 防卡死
      if ((i + 1) % 50 == 0) await Future.delayed(Duration.zero);

      try {
        final stats = await widget.databaseService.getSessionMessageStats(session.username);
        final messageCount = stats['total'] as int;
        if (messageCount == 0) {
          skippedCount++;
          continue;
        }

        rankings.add(
          ContactRanking(
            username: session.username,
            displayName: displayNames[session.username] ?? session.username,
            messageCount: messageCount,
            sentCount: stats['sent'] as int,
            receivedCount: stats['received'] as int,
            lastMessageTime: null, 
          ),
        );
      } catch (e) {
        // 忽略错误
      }
    }

    rankings.sort((a, b) => b.messageCount.compareTo(a.messageCount));
    // 原代码这里取了前50，我们也保持一致
    return rankings.take(50).toList();
  }

  Future<bool?> _showDatabaseChangedDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('数据库已更新'),
          ],
        ),
        content: const Text(
          '检测到数据库已发生变化，是否重新分析数据？\n\n'
          '• 重新分析：获取最新的统计结果（需要一些时间）\n'
          '• 使用旧数据：快速加载，但可能不包含最新消息',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('使用旧数据'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重新分析'),
          ),
        ],
      ),
    );
  }

  // ==================== 界面构建 ====================

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
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80, height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                value: _totalCount > 0 ? _processedCount / _totalCount : null,
              ),
            ),
            const SizedBox(height: 32),
            Text(_loadingStatus, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            if (_totalCount > 0)
              Text('$_processedCount / $_totalCount', style: const TextStyle(color: Colors.grey)),
          ],
        ),
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
          const Text('暂无数据'),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. 新增：年份筛选按钮
        _buildYearFilterButton(),

        // 2. 年度报告入口
        _buildAnnualReportEntry(),
        const SizedBox(height: 16),

        // 3. 统计图表 (完全保留原样)
        _buildOverallStatsCard(),
        const SizedBox(height: 16),
        _buildMessageTypeChart(),
        const SizedBox(height: 16),
        _buildSendReceiveChart(),
        const SizedBox(height: 16),
        
        // 4. 联系人排名 (保留 SegmentedButton 和 绿标头像)
        _buildContactRankingCard(),
      ],
    );
  }

  // ==================== 新增 UI 组件 ====================

  Widget _buildYearFilterButton() {
    final text = _selectedYear == null ? '📅  全部年份 (历史累计)' : '📅  $_selectedYear 年数据';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
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
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(text, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showYearSelectionMenu() {
    if (_isLoading) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('选择分析年份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.calendar_view_month),
                      title: const Text('全部年份'),
                      trailing: _selectedYear == null ? const Icon(Icons.check, color: Colors.green) : null,
                      onTap: () async {
                        Navigator.pop(context);
                        if (_selectedYear != null) {
                          setState(() => _selectedYear = null);
                          final dbTime = await _getDbModifiedTime();
                          _performAnalysis(dbTime);
                        }
                      },
                    ),
                    ..._availableYears.map((year) => ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: Text('$year年'),
                      trailing: _selectedYear == year ? const Icon(Icons.check, color: Colors.green) : null,
                      onTap: () async {
                        Navigator.pop(context);
                        if (_selectedYear != year) {
                          setState(() => _selectedYear = year);
                          final dbTime = await _getDbModifiedTime();
                          _performAnalysis(dbTime);
                        }
                      },
                    )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== 原有 UI 组件 (完全保留) ====================
  /// 年度报告入口卡片
  Widget _buildAnnualReportEntry() {
    const wechatGreen = Color(0xFF07C160);
    // 动态调整标题
    final title = _selectedYear == null ? '查看详细年度报告' : '查看 $_selectedYear 年度报告';

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: wechatGreen, width: 1),
      ),
      child: InkWell(
        onTap: _isLoading
            ? null
            : () async {
                 // 显示加载状态
                setState(() {
                  _isLoading = true;
                  _loadingStatus = '正在准备年度报告...';
                });
                try {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AnnualReportDisplayPage(
                        databaseService: widget.databaseService,
                        year: _selectedYear, // 传入年份
                      ),
                    ),
                  );
                } finally {
                   // 隐藏加载状态
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _loadingStatus = '';
                    });
                  }
                }
              },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '深度分析你的聊天数据，发现更多有趣洞察',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              _isLoading
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(wechatGreen)),
                    )
                  : const Icon(Icons.chevron_right, color: Colors.grey, size: 24),
            ],
          ),
        ),
      ),
    );
  }

/// 总体统计卡片
  Widget _buildOverallStatsCard() {
    final stats = _overallStats!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '私聊总体统计',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStatRow('总消息数', stats.totalMessages.toString()),
            _buildStatRow('活跃天数', stats.activeDays.toString()),
            _buildStatRow('平均每天', stats.averageMessagesPerDay.toStringAsFixed(1)),
            _buildStatRow('聊天时长', '${stats.chatDurationDays} 天'),
            if (stats.firstMessageTime != null)
              _buildStatRow('首条消息', _formatDateTime(stats.firstMessageTime!)),
            if (stats.lastMessageTime != null)
              _buildStatRow('最新消息', _formatDateTime(stats.lastMessageTime!)),
          ],
        ),
      ),
    );
  }

  /// 消息类型分布
  Widget _buildMessageTypeChart() {
    final stats = _overallStats!;
    final distribution = stats.messageTypeDistribution;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '消息类型分布',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...distribution.entries.map((entry) {
              final percentage = stats.totalMessages > 0
                  ? (entry.value / stats.totalMessages * 100).toStringAsFixed(1)
                  : '0.0';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 60, child: Text(entry.key)),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: stats.totalMessages > 0 ? entry.value / stats.totalMessages : 0,
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 80, child: Text('${entry.value} ($percentage%)', textAlign: TextAlign.right)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 发送/接收比例
  Widget _buildSendReceiveChart() {
    final stats = _overallStats!;
    final ratio = stats.sendReceiveRatio;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '发送/接收比例',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...ratio.entries.map((entry) {
              final percentage = stats.totalMessages > 0
                  ? (entry.value / stats.totalMessages * 100).toStringAsFixed(1)
                  : '0.0';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 60, child: Text(entry.key)),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: stats.totalMessages > 0 ? entry.value / stats.totalMessages : 0,
                        backgroundColor: Colors.grey[200],
                        color: entry.key == '发送' ? Colors.blue : Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 80, child: Text('${entry.value} ($percentage%)', textAlign: TextAlign.right)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 联系人排名卡片
  Widget _buildContactRankingCard() {
    if (_contactRankings == null || _contactRankings!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '聊天最多的联系人 Top $_topN',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                // 保留原有的 SegmentedButton
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(value: 10, label: Text('Top 10')),
                    ButtonSegment<int>(value: 20, label: Text('Top 20')),
                    ButtonSegment<int>(value: 50, label: Text('Top 50')),
                  ],
                  selected: {_topN},
                  onSelectionChanged: (Set<int> newSelection) {
                    final newTopN = newSelection.first;
                    setState(() {
                      _topN = newTopN;
                      _contactRankings = _allContactRankings?.take(_topN).toList();
                    });
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (context) {
                return Column(
                  children: _contactRankings!.asMap().entries.map((entry) {
                    final index = entry.key;
                    final ranking = entry.value;
                    final appState = Provider.of<AppState>(context);
                    final avatarUrl = appState.getAvatarUrl(ranking.username);
                    return ListTile(
                      key: ValueKey('${ranking.username}_$index'),
                      leading: _AvatarWithRank(
                        avatarUrl: avatarUrl,
                        rank: index + 1,
                        displayName: ranking.displayName,
                      ),
                      title: Text(
                        StringUtils.cleanOrDefault(ranking.displayName, ranking.username),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '发送: ${ranking.sentCount} | 接收: ${ranking.receivedCount}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                      trailing: Text(
                        '${ranking.messageCount}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }
}

// 独立的类，完全保留原有的绿标头像样式
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

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (hasAvatar)
          CachedNetworkImage(
            imageUrl: avatarUrl!,
            imageBuilder: (context, imageProvider) => CircleAvatar(
              radius: 22,
              backgroundColor: Colors.transparent,
              backgroundImage: imageProvider,
            ),
            placeholder: (context, url) => CircleAvatar(
              radius: 22,
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              child: Text(fallbackText, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
            ),
            errorWidget: (context, url, error) => CircleAvatar(
              radius: 22,
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              child: Text(fallbackText, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
            ),
          )
        else
          CircleAvatar(
            radius: 22,
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            child: Text(fallbackText, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
        Positioned(
          bottom: -4,
          right: -4,
          child: CircleAvatar(
            radius: 10,
            backgroundColor: Colors.white,
            child: CircleAvatar(
              radius: 8,
              backgroundColor: Theme.of(context).colorScheme.primary,
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