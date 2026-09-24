/// 儿童模式内容白名单配置
///
/// 本应用不展示哔哩哔哩的推荐流，首页只呈现这里定义的主题。
/// 每个主题由三部分组成：
/// - queries: 用于调用搜索接口的关键词（可以有多个，分页时轮流使用）
/// - matchKeywords: 用于校验搜索结果的标题关键词，只有命中才算该主题内容
/// - excludeKeywords: 标题命中任一即否决（用来挡掉投流漫剧、游戏、课程广告）
///
/// 另外，凡是标题命中主题关键词的视频，其 UP 主会被自动加入“信任 UP 主”
/// 名单（可在设置中关闭），之后该 UP 主的投稿会被视为安全内容。
library;

/// 全局硬屏蔽词
///
/// 投流广告 / 漫剧的典型标记，命中即不显示，对**所有主题**生效，
/// 并且优先于“信任 UP 主”（即信任名单里的号发这些也照样挡掉）。
const List<String> kidsGlobalBlockKeywords = [
  '漫剧',
  '短剧',
  '小说推文',
  '免费观看',
  '勉费观看',
  '荃集',
  '爽文',
];

/// 一个主题（如“我的世界”“芭比娃娃”）
class KidsTopic {
  /// 稳定 id，用于持久化开关状态（不要随意改动）
  final String id;

  /// 界面上显示的名称
  final String label;

  /// 搜索关键词列表
  final List<String> queries;

  /// 标题匹配关键词（全部按小写比较）
  final List<String> matchKeywords;

  /// 标题排除关键词：命中任意一个就不算该主题内容（全部按小写比较）
  final List<String> excludeKeywords;

  /// 默认是否启用
  final bool defaultEnabled;

  const KidsTopic({
    required this.id,
    required this.label,
    required this.queries,
    required this.matchKeywords,
    this.excludeKeywords = const [],
    this.defaultEnabled = false,
  });

  /// 是否是用户自己添加的主题（id 不在内置目录里）
  bool get isCustom => !kidsTopicCatalog.any((t) => t.id == id);

  /// 从持久化的 JSON 还原（用于自定义主题）
  factory KidsTopic.fromJson(Map<String, dynamic> json) {
    List<String> strList(dynamic value) {
      if (value is List) {
        return value
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    return KidsTopic(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      queries: strList(json['queries']),
      matchKeywords: strList(json['matchKeywords']),
      excludeKeywords: strList(json['excludeKeywords']),
      defaultEnabled: false,
    );
  }

  /// 序列化（用于保存自定义主题）
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'queries': queries,
    'matchKeywords': matchKeywords,
    'excludeKeywords': excludeKeywords,
  };
}

/// 内置主题目录
///
/// 默认启用：我的世界、芭比娃娃、美甲、盖房子。
/// 其余主题可在 设置 → 儿童模式（或手机网页配置）里按需打开。
const List<KidsTopic> kidsTopicCatalog = [
  KidsTopic(
    id: 'minecraft',
    label: '我的世界',
    queries: [
      '我的世界',
      '我的世界 生存',
      '我的世界 动画',
      '我的世界 建筑',
    ],
    matchKeywords: ['我的世界', 'minecraft', '麦块', '方块世界'],
    defaultEnabled: true,
  ),
  KidsTopic(
    id: 'barbie',
    label: '芭比娃娃',
    queries: ['芭比娃娃', '芭比娃娃 动画', '芭比 玩具', '芭比娃娃 故事'],
    matchKeywords: ['芭比', 'barbie'],
    defaultEnabled: true,
  ),
  KidsTopic(
    id: 'nail_art',
    label: '美甲',
    queries: ['儿童美甲', '美甲 玩具'],
    matchKeywords: ['美甲', '指甲'],
    // 裸词「美甲」会搜出成人美甲课程/开店教学/带货广告，这里挡掉
    excludeKeywords: [
      '游戏',
      '攻略',
      '通关',
      '课程',
      '培训',
      '必修课',
      '全科班',
      '线上课',
      '开班',
      '招生',
      '学员',
      '考证',
      '进修',
      '零基础',
      '基本功',
      '美甲师',
      '教官',
      '开店',
      '创业',
      '转行',
      '接单',
      '月入',
      '实操',
      '款式图',
      '带货',
      '广告',
      '店铺',
      '测评',
      '安利',
      '团购',
      '优惠',
      '必买',
      '链接',
    ],
    defaultEnabled: true,
  ),
  KidsTopic(
    id: 'house_build',
    label: '盖房子',
    queries: [
      // 实测：这几个词搜出来的都是真实建房/荒野搭建的长视频
      '农村建房',
      '自建房 全过程',
      '野外搭建庇护所',
      '荒野 建造 庇护所',
    ],
    matchKeywords: ['建房', '盖房', '搭建', '庇护所', '建造', '木屋', '施工'],
    // 「森林 木屋 搭建」这类词会搜出游戏（森林之子/TheForest），
    // 「庇护所」裸词会搜出末日爽文漫剧，这里挡掉
    excludeKeywords: [
      '游戏',
      '手游',
      '实况',
      '攻略',
      '教学',
      '教程',
      '森林之子',
      '方舟',
      '迷你世界',
      '我的世界',
      'minecraft',
      '泰拉瑞亚',
      '明日之后',
      '诡异',
      '恐怖',
      '灵异',
      '广告',
      '带货',
      '课程',
      '培训',
      '女友',
      '富二代',
      '觉醒',
      '穿越',
    ],
    defaultEnabled: true,
  ),
  KidsTopic(
    id: 'peppa',
    label: '小猪佩奇',
    queries: ['小猪佩奇', '小猪佩奇 合集'],
    matchKeywords: ['小猪佩奇', 'peppa'],
  ),
  KidsTopic(
    id: 'paw_patrol',
    label: '汪汪队立大功',
    queries: ['汪汪队立大功', '汪汪队 合集'],
    matchKeywords: ['汪汪队', 'paw patrol'],
  ),
  KidsTopic(
    id: 'super_wings',
    label: '超级飞侠',
    queries: ['超级飞侠', '超级飞侠 合集'],
    matchKeywords: ['超级飞侠', 'super wings'],
  ),
  KidsTopic(
    id: 'octonauts',
    label: '海底小纵队',
    queries: ['海底小纵队', '海底小纵队 合集'],
    matchKeywords: ['海底小纵队', 'octonauts'],
  ),
  KidsTopic(
    id: 'babybus',
    label: '宝宝巴士',
    queries: ['宝宝巴士', '宝宝巴士 儿歌'],
    matchKeywords: ['宝宝巴士', 'babybus'],
  ),
  KidsTopic(
    id: 'nursery_rhyme',
    label: '儿歌童谣',
    queries: ['儿童儿歌', '儿歌 童谣', '经典儿歌'],
    matchKeywords: ['儿歌', '童谣', 'nursery rhyme'],
  ),
  KidsTopic(
    id: 'ultraman',
    label: '奥特曼',
    queries: ['奥特曼', '奥特曼 合集'],
    matchKeywords: ['奥特曼', 'ultraman'],
  ),
  KidsTopic(
    id: 'lego',
    label: '乐高积木',
    queries: ['乐高 动画', '乐高 积木 拼搭'],
    matchKeywords: ['乐高', 'lego'],
  ),
  KidsTopic(
    id: 'dinosaur',
    label: '恐龙世界',
    queries: ['恐龙 科普 儿童', '恐龙 动画'],
    matchKeywords: ['恐龙', 'dinosaur'],
  ),
  KidsTopic(
    id: 'thomas',
    label: '托马斯小火车',
    queries: ['托马斯小火车', '托马斯 合集'],
    matchKeywords: ['托马斯', 'thomas'],
  ),
  KidsTopic(
    id: 'miniworld',
    label: '迷你世界',
    queries: ['迷你世界', '迷你世界 动画'],
    matchKeywords: ['迷你世界'],
  ),
  KidsTopic(
    id: 'disney',
    label: '迪士尼动画',
    queries: ['迪士尼 动画', '冰雪奇缘'],
    matchKeywords: ['迪士尼', 'disney', '冰雪奇缘', 'frozen', '艾莎'],
  ),
];

/// 默认启用的主题 id 列表
List<String> get defaultEnabledTopicIds => kidsTopicCatalog
    .where((topic) => topic.defaultEnabled)
    .map((topic) => topic.id)
    .toList();
