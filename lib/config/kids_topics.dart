/// 儿童模式内容白名单配置
///
/// 本应用不展示哔哩哔哩的推荐流，首页只呈现这里定义的主题。
/// 每个主题由两部分组成：
/// - queries: 用于调用搜索接口的关键词（可以有多个，分页时轮流使用）
/// - matchKeywords: 用于校验搜索结果的标题关键词，只有命中才算该主题内容
///
/// 另外，凡是标题命中主题关键词的视频，其 UP 主会被自动加入“信任 UP 主”
/// 名单（可在设置中关闭），之后该 UP 主的投稿会被视为安全内容。
library;

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

  /// 默认是否启用
  final bool defaultEnabled;

  const KidsTopic({
    required this.id,
    required this.label,
    required this.queries,
    required this.matchKeywords,
    this.defaultEnabled = false,
  });
}

/// 内置主题目录
///
/// 默认只启用“我的世界”和“芭比娃娃”，其余主题可在
/// 设置 → 儿童模式 中按需打开。
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
