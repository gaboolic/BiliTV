/// 儿童模式「指定 UP 主」名单配置
///
/// 首页的「我的 UP 主」频道内容完全来自这里：每一项都是一个 UP 主，
/// 频道会把他们的投稿混在一起展示。
///
/// [mid] 为 UP 主的 UID：
/// - 大于 0：已经确定了具体账号，直接拉他的投稿；
/// - 等于 0：只有名字，运行时用搜索接口按名字找账号（找不到就跳过）。
library;

/// 一个 UP 主
class KidsUpOwner {
  /// UP 主昵称（也是搜索用的关键词）
  final String name;

  /// UP 主 UID，0 表示还没解析出来
  final int mid;

  const KidsUpOwner({required this.name, this.mid = 0});

  /// 序列化
  Map<String, dynamic> toJson() => {'name': name, 'mid': mid};

  /// 反序列化
  factory KidsUpOwner.fromJson(Map<String, dynamic> json) {
    return KidsUpOwner(
      name: json['name']?.toString() ?? '',
      mid: _toInt(json['mid']),
    );
  }

  /// 是否已经确定了账号
  bool get resolved => mid > 0;

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  String toString() => mid > 0 ? '$name(uid:$mid)' : name;
}

/// 默认名单
///
/// [mid] 已经确定的账号直接写死 UID，不会因为昵称搜索而选错人；
/// 只写昵称的账号会在运行时按昵称找（找不到就跳过）。
const List<KidsUpOwner> defaultKidsUpOwners = [
  // 怪小逗小舞台（B站昵称「怪逗逗小舞台」），定格动画
  KidsUpOwner(name: '怪逗逗小舞台', mid: 421188041),
  // 麦琪
  KidsUpOwner(name: 'MC杰杰和麦琪', mid: 3546568911227178),
];
