// 高级分析的数据模型

/// 作息热力图数据
class ActivityHeatmap {
  final Map<int, Map<int, int>> data; // 小时 -> 星期几 -> 消息数量
  final int maxCount; // 最大消息数，用于数据归一化

  ActivityHeatmap({required this.data, required this.maxCount});

  /// 获取指定时间的消息数
  int getCount(int hour, int weekday) {
    return data[hour]?[weekday] ?? 0;
  }

  /// 获取归一化值 (0-1)
  double getNormalizedValue(int hour, int weekday) {
    if (maxCount == 0) return 0;
    return getCount(hour, weekday) / maxCount;
  }

  /// 获取最活跃时段
  Map<String, int> getMostActiveTime() {
    int maxHour = 0;
    int maxWeekday = 1;
    int maxVal = 0;

    data.forEach((hour, weekdayMap) {
      weekdayMap.forEach((weekday, count) {
        if (count > maxVal) {
          maxVal = count;
          maxHour = hour;
          maxWeekday = weekday;
        }
      });
    });

    return {'hour': maxHour, 'weekday': maxWeekday, 'count': maxVal};
  }

  Map<String, dynamic> toJson() => {
    'data': data.map(
      (k, v) => MapEntry(
        k.toString(),
        v.map((k2, v2) => MapEntry(k2.toString(), v2)),
      ),
    ),
    'maxCount': maxCount,
  };

  factory ActivityHeatmap.fromJson(Map<String, dynamic> json) =>
      ActivityHeatmap(
        data: (json['data'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(
            int.parse(k),
            (v as Map<String, dynamic>).map(
              (k2, v2) => MapEntry(int.parse(k2), v2 as int),
            ),
          ),
        ),
        maxCount: json['maxCount'],
      );
}

/// 亲密度日历数据
class IntimacyCalendar {
  final String username;
  final Map<DateTime, int> dailyMessages; // 日期 -> 消息数
  final DateTime startDate;
  final DateTime endDate;
  final int maxDailyCount;

  IntimacyCalendar({
    required this.username,
    required this.dailyMessages,
    required this.startDate,
    required this.endDate,
    required this.maxDailyCount,
  });

  /// 获取指定日期的消息数
  int getMessageCount(DateTime date) {
    final dateKey = DateTime(date.year, date.month, date.day);
    return dailyMessages[dateKey] ?? 0;
  }

  /// 获取热度等级 (0-5)
  int getHeatLevel(DateTime date) {
    if (maxDailyCount == 0) return 0;
    final count = getMessageCount(date);
    final ratio = count / maxDailyCount;

    if (ratio == 0) return 0;
    if (ratio < 0.2) return 1;
    if (ratio < 0.4) return 2;
    if (ratio < 0.6) return 3;
    if (ratio < 0.8) return 4;
    return 5;
  }

  /// 获取最热聊天日
  DateTime? getHottestDay() {
    if (dailyMessages.isEmpty) return null;
    return dailyMessages.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  /// 获取按月统计的消息数
  Map<String, int> get monthlyData {
    final result = <String, int>{};
    for (final entry in dailyMessages.entries) {
      final key =
          '${entry.key.year}-${entry.key.month.toString().padLeft(2, '0')}';
      result[key] = (result[key] ?? 0) + entry.value;
    }
    return result;
  }

  Map<String, dynamic> toJson() {
    final dailyMessagesJson = <String, int>{};
    for (final entry in dailyMessages.entries) {
      dailyMessagesJson[entry.key.toIso8601String()] = entry.value;
    }

    return {
      'username': username,
      'dailyMessages': dailyMessagesJson,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'maxDailyCount': maxDailyCount,
    };
  }

  factory IntimacyCalendar.fromJson(Map<String, dynamic> json) {
    final dailyMessagesJson = json['dailyMessages'] as Map<String, dynamic>;
    final dailyMessages = <DateTime, int>{};
    for (final entry in dailyMessagesJson.entries) {
      dailyMessages[DateTime.parse(entry.key)] = entry.value as int;
    }

    return IntimacyCalendar(
      username: json['username'] as String,
      dailyMessages: dailyMessages,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      maxDailyCount: json['maxDailyCount'] as int,
    );
  }
}

/// 对话天平数据
class ConversationBalance {
  final String username;
  final int sentCount; // 我发送的
  final int receivedCount; // 收到的
  final int sentWords; // 我发送的字数
  final int receivedWords; // 收到的字数
  final int initiatedByMe; // 我发起的对话次数
  final int initiatedByOther; // 对方发起的对话次数
  final int conversationSegments; // 对话段数（超过20分钟算新段）
  final int segmentsInitiatedByMe; // 我发起的对话段数
  final int segmentsInitiatedByOther; // 对方发起的对话段数

  ConversationBalance({
    required this.username,
    required this.sentCount,
    required this.receivedCount,
    required this.sentWords,
    required this.receivedWords,
    required this.initiatedByMe,
    required this.initiatedByOther,
    required this.conversationSegments,
    required this.segmentsInitiatedByMe,
    required this.segmentsInitiatedByOther,
  });

  /// 获取消息数比例 (我/对方)
  double get messageRatio {
    if (receivedCount == 0) return double.infinity;
    return sentCount / receivedCount;
  }

  /// 获取字数比例
  double get wordRatio {
    if (receivedWords == 0) return double.infinity;
    return sentWords / receivedWords;
  }

  /// 获取主动性比例（基于对话段）
  double get initiativeRatio {
    if (segmentsInitiatedByOther == 0) return double.infinity;
    return segmentsInitiatedByMe / segmentsInitiatedByOther;
  }

  /// 判断谁更主动
  String get moreActive {
    if (initiativeRatio > 1.2) return 'me';
    if (initiativeRatio < 0.8) return 'other';
    return 'balanced';
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'sentCount': sentCount,
    'receivedCount': receivedCount,
    'sentWords': sentWords,
    'receivedWords': receivedWords,
    'initiatedByMe': initiatedByMe,
    'initiatedByOther': initiatedByOther,
    'conversationSegments': conversationSegments,
    'segmentsInitiatedByMe': segmentsInitiatedByMe,
    'segmentsInitiatedByOther': segmentsInitiatedByOther,
  };

  factory ConversationBalance.fromJson(Map<String, dynamic> json) {
    return ConversationBalance(
      username: json['username'] as String,
      sentCount: json['sentCount'] as int,
      receivedCount: json['receivedCount'] as int,
      sentWords: json['sentWords'] as int,
      receivedWords: json['receivedWords'] as int,
      initiatedByMe: json['initiatedByMe'] as int,
      initiatedByOther: json['initiatedByOther'] as int,
      conversationSegments: json['conversationSegments'] as int,
      segmentsInitiatedByMe: json['segmentsInitiatedByMe'] as int,
      segmentsInitiatedByOther: json['segmentsInitiatedByOther'] as int,
    );
  }
}

/// "第一次"记录
class FirstTimeRecord {
  final String keyword;
  final DateTime time;
  final String messageContent;
  final bool isSentByMe;

  FirstTimeRecord({
    required this.keyword,
    required this.time,
    required this.messageContent,
    required this.isSentByMe,
  });

/// 新增代码，为“FirstTimeRecord”添加序列化支持。
  Map<String, dynamic> toJson() => {
    'keyword': keyword,
    'time': time.toIso8601String(),
    'messageContent': messageContent,
    'isSentByMe': isSentByMe,
  };

  factory FirstTimeRecord.fromJson(Map<String, dynamic> json) =>
      FirstTimeRecord(
        keyword: json['keyword'],
        time: DateTime.parse(json['time']),
        messageContent: json['messageContent'],
        isSentByMe: json['isSentByMe'],
      );
}
/// 趣味统计数据
class FunStats {
  // 笑点报告
  final int totalHaha; // 总共发了多少个"哈"
  final int longestHaha; // 最长连续"哈"字数
  final String longestHahaText; // 最长的哈哈哈文本

  // 深夜活跃榜
  final String? midnightChatKing; // 深夜最爱聊天的人
  final int midnightMessageCount; // 深夜总消息数

  // 连击王者
  final String? longestStreakFriend; // 连聊最久的朋友
  final int longestStreakDays; // 最长连续聊天天数
  final DateTime? streakStartDate;
  final DateTime? streakEndDate;

  FunStats({
    required this.totalHaha,
    required this.longestHaha,
    required this.longestHahaText,
    this.midnightChatKing,
    required this.midnightMessageCount,
    this.longestStreakFriend,
    required this.longestStreakDays,
    this.streakStartDate,
    this.streakEndDate,
  });

/// 为“趣味统计”添加序列化支持
  Map<String, dynamic> toJson() => {
    'totalHaha': totalHaha,
    'longestHaha': longestHaha,
    'longestHahaText': longestHahaText,
    'midnightChatKing': midnightChatKing,
    'midnightMessageCount': midnightMessageCount,
    'longestStreakFriend': longestStreakFriend,
    'longestStreakDays': longestStreakDays,
    'streakStartDate': streakStartDate?.toIso8601String(),
    'streakEndDate': streakEndDate?.toIso8601String(),
  };

  factory FunStats.fromJson(Map<String, dynamic> json) => FunStats(
    totalHaha: json['totalHaha'],
    longestHaha: json['longestHaha'],
    longestHahaText: json['longestHahaText'],
    midnightChatKing: json['midnightChatKing'],
    midnightMessageCount: json['midnightMessageCount'],
    longestStreakFriend: json['longestStreakFriend'],
    longestStreakDays: json['longestStreakDays'],
    streakStartDate: json['streakStartDate'] != null
        ? DateTime.parse(json['streakStartDate'])
        : null,
    streakEndDate: json['streakEndDate'] != null
        ? DateTime.parse(json['streakEndDate'])
        : null,
  );
}

/// 语言风格数据
class LinguisticStyle {
  final double avgMessageLength; // 平均消息长度
  final Map<String, int> punctuationUsage; // 标点符号使用统计
  final int revokedMessageCount; // 撤回消息次数

  LinguisticStyle({
    required this.avgMessageLength,
    required this.punctuationUsage,
    required this.revokedMessageCount,
  });

  /// 获取最常用标点
  String get mostUsedPunctuation {
    if (punctuationUsage.isEmpty) return '';
    return punctuationUsage.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  /// 判断说话风格
  String get style {
    if (avgMessageLength < 10) return '言简意赅派';
    if (avgMessageLength < 30) return '适度表达型';
    return '长篇大论型';
  }

  Map<String, dynamic> toJson() => {
    'avgMessageLength': avgMessageLength,
    'punctuationUsage': punctuationUsage,
    'revokedMessageCount': revokedMessageCount,
  };

  factory LinguisticStyle.fromJson(Map<String, dynamic> json) =>
      LinguisticStyle(
        avgMessageLength: json['avgMessageLength'],
        punctuationUsage: Map<String, int>.from(json['punctuationUsage']),
        revokedMessageCount: json['revokedMessageCount'],
      );
}

/// 好友排名项（用于挚友榜）
class FriendshipRanking {
  final String username;
  final String displayName;
  final int count; // 数值含义视上下文而定：可能是互动总数、发送量、接收量等
  final double percentage;
  final Map<String, dynamic>? details; // 额外详细信息，比如互动均衡度

  FriendshipRanking({
    required this.username,
    required this.displayName,
    required this.count,
    required this.percentage,
    this.details,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'displayName': displayName,
    'count': count,
    'percentage': percentage,
    'details': details,
  };

  factory FriendshipRanking.fromJson(Map<String, dynamic> json) =>
      FriendshipRanking(
        username: json['username'],
        displayName: json['displayName'],
        count: json['count'],
        percentage: json['percentage'],
        details: json['details'],
      );
}

/// 社交风格数据（主动发起率）
class SocialStyleData {
  final List<FriendshipRanking> initiativeRanking; // 按主动发起率排序

  SocialStyleData({required this.initiativeRanking});

  Map<String, dynamic> toJson() => {
    'initiativeRanking': initiativeRanking.map((e) => e.toJson()).toList(),
  };

  factory SocialStyleData.fromJson(Map<String, dynamic> json) =>
      SocialStyleData(
        initiativeRanking: List<FriendshipRanking>.from(
          (json['initiativeRanking'] as List).map(
            (e) => FriendshipRanking.fromJson(e),
          ),
        ),
      );
}

/// 聊天巅峰日
class ChatPeakDay {
  final DateTime date;
  final int messageCount;
  final String formattedDate;
  final String? topFriendUsername; // 当天聊得最多的好友username
  final String? topFriendDisplayName; // 当天聊得最多的好友显示名
  final int? topFriendMessageCount; // 当天和该好友的消息数
  final double? topFriendPercentage; // 占当天总消息的百分比

  ChatPeakDay({
    required this.date,
    required this.messageCount,
    this.topFriendUsername,
    this.topFriendDisplayName,
    this.topFriendMessageCount,
    this.topFriendPercentage,
  }) : formattedDate =
           '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'messageCount': messageCount,
    'formattedDate': formattedDate,
    'topFriendUsername': topFriendUsername,
    'topFriendDisplayName': topFriendDisplayName,
    'topFriendMessageCount': topFriendMessageCount,
    'topFriendPercentage': topFriendPercentage,
  };

  factory ChatPeakDay.fromJson(Map<String, dynamic> json) => ChatPeakDay(
    date: DateTime.parse(json['date']),
    messageCount: json['messageCount'],
    topFriendUsername: json['topFriendUsername'],
    topFriendDisplayName: json['topFriendDisplayName'],
    topFriendMessageCount: json['topFriendMessageCount'],
    topFriendPercentage: json['topFriendPercentage'],
  );
}

/// 消息类型统计
class MessageTypeStats {
  final String typeName;
  final int count;
  final double percentage;

  MessageTypeStats({
    required this.typeName,
    required this.count,
    required this.percentage,
  });

  Map<String, dynamic> toJson() => {
    'typeName': typeName,
    'count': count,
    'percentage': percentage,
  };

  factory MessageTypeStats.fromJson(Map<String, dynamic> json) =>
      MessageTypeStats(
        typeName: json['typeName'],
        count: json['count'],
        percentage: json['percentage'],
      );
}

/// 消息长度分析
class MessageLengthData {
  final double averageLength;
  final int longestLength;
  final String longestContent;
  final String? longestSentTo; // 发送给谁
  final String? longestSentToDisplayName;
  final DateTime? longestMessageTime;
  final int totalTextMessages;

  MessageLengthData({
    required this.averageLength,
    required this.longestLength,
    required this.longestContent,
    this.longestSentTo,
    this.longestSentToDisplayName,
    this.longestMessageTime,
    required this.totalTextMessages,
  });

  Map<String, dynamic> toJson() => {
    'averageLength': averageLength,
    'longestLength': longestLength,
    'longestContent': longestContent,
    'longestSentTo': longestSentTo,
    'longestSentToDisplayName': longestSentToDisplayName,
    'longestMessageTime': longestMessageTime?.toIso8601String(),
    'totalTextMessages': totalTextMessages,
  };

  factory MessageLengthData.fromJson(Map<String, dynamic> json) =>
      MessageLengthData(
        averageLength: json['averageLength'],
        longestLength: json['longestLength'],
        longestContent: json['longestContent'],
        longestSentTo: json['longestSentTo'],
        longestSentToDisplayName: json['longestSentToDisplayName'],
        longestMessageTime: json['longestMessageTime'] != null
            ? DateTime.parse(json['longestMessageTime'])
            : null,
        totalTextMessages: json['totalTextMessages'],
      );
}

// ==========================================
// 以下为本次新增的年度报告数据模型 (Step 1 Added)
// ==========================================

/// 年度 Emoji 统计
class EmojiStats {
  final List<Map<String, dynamic>> topEmojis; // [{'emoji': '😂', 'count': 100}, ...]
  final String personalityTag; // 例如 "乐天派", "阴阳师"

  EmojiStats({required this.topEmojis, required this.personalityTag});

  Map<String, dynamic> toJson() => {
    'topEmojis': topEmojis,
    'personalityTag': personalityTag,
  };

  factory EmojiStats.fromJson(Map<String, dynamic> json) => EmojiStats(
    topEmojis: List<Map<String, dynamic>>.from(json['topEmojis']),
    personalityTag: json['personalityTag'],
  );
}

/// 社交能量曲线 (月度统计)
class SocialBatteryStats {
  final List<int> monthlyCounts; // 1-12月的消息数列表
  final int peakMonth; // 最活跃的月份 (1-12)
  final int lowMonth; // 最安静的月份 (1-12)

  SocialBatteryStats({
    required this.monthlyCounts,
    required this.peakMonth,
    required this.lowMonth,
  });

  Map<String, dynamic> toJson() => {
    'monthlyCounts': monthlyCounts,
    'peakMonth': peakMonth,
    'lowMonth': lowMonth,
  };

  factory SocialBatteryStats.fromJson(Map<String, dynamic> json) =>
      SocialBatteryStats(
        monthlyCounts: List<int>.from(json['monthlyCounts']),
        peakMonth: json['peakMonth'],
        lowMonth: json['lowMonth'],
      );
}

/// 首尾消息记录 (敲门人与守夜人)
class YearBoundaryStats {
  final Map<String, dynamic>? firstMessage; // {content, date, username, displayName}
  final Map<String, dynamic>? lastMessage;

  YearBoundaryStats({this.firstMessage, this.lastMessage});

  Map<String, dynamic> toJson() => {
    'firstMessage': firstMessage,
    'lastMessage': lastMessage,
  };

  factory YearBoundaryStats.fromJson(Map<String, dynamic> json) =>
      YearBoundaryStats(
        firstMessage: json['firstMessage'],
        lastMessage: json['lastMessage'],
      );
}
