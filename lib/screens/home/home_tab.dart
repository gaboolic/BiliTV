import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import '../../models/video.dart';
import 'package:keframe/keframe.dart';
import '../../config/kids_topics.dart';
import '../../services/auth_service.dart';
import '../../services/bilibili_api.dart';
import '../../services/kids_feed_service.dart';
import '../../services/kids_mode_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/tv_video_card.dart';
import '../../widgets/time_display.dart';
import '../../core/plugin/plugin_manager.dart';
import '../../core/plugin/plugin_types.dart';
import '../player/player_screen.dart';

class HomeTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onFirstLoadComplete;
  final List<Video>? preloadedVideos; // 接收预加载数据

  const HomeTab({
    super.key,
    this.sidebarFocusNode,
    this.onFirstLoadComplete,
    this.preloadedVideos,
  });

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  int _selectedCategoryIndex = 0;
  final ScrollController _scrollController = ScrollController();
  late List<HomeCategory> _categories;
  late List<FocusNode> _categoryFocusNodes;

  /// 儿童模式：当前启用的主题（替代原来的推荐/热门/分区）
  List<KidsTopic> _kidsTopics = [];
  bool _kidsMode = false;

  // 数据缓存
  final Map<int, List<Video>> _categoryVideos = {};
  final Map<int, bool> _categoryLoading = {};
  final Map<int, int> _categoryPage = {};
  final Map<int, int> _categoryRefreshIdx = {};
  bool _firstLoadDone = false;
  bool _usedPreloadedData = false; // 标记是否使用了预加载数据
  bool _isRefreshing = false; // 标记是否正在刷新中（用于控制分帧渲染）
  // 每个视频卡片的 FocusNode
  final Map<int, FocusNode> _videoFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _kidsMode = KidsModeService.enabled;
    _kidsTopics = KidsModeService.topics;
    _loadCategoryOrder();
    _categoryFocusNodes = List.generate(_maxSectionCount, (_) => FocusNode());

    // 设置页里改了儿童模式/主题后立即重建首页
    KidsModeService.revision.addListener(_onKidsModeChanged);

    // 【优化核心 1】如果有预加载数据，立即填充，且标记 loading 为 false
    if (widget.preloadedVideos != null && widget.preloadedVideos!.isNotEmpty) {
      _categoryVideos[0] = widget.preloadedVideos!;
      _categoryRefreshIdx[0] = 1;
      _categoryLoading[0] = false; // 关键：明确标记不加载
      _usedPreloadedData = true; // 标记使用了预加载数据
      _firstLoadDone = true;

      // 通知父组件（用于 Sidebar 焦点处理等）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFirstLoadComplete?.call();
      });
    } else {
      // 只有没数据时，才自己去请求
      _loadVideosForCategory(0);
    }
  }

  /// 首页当前的行数（儿童模式下是主题数，否则是分区数）
  int get _sectionCount => _kidsMode ? _kidsTopics.length : _categories.length;

  /// 分类标签最多需要的焦点节点数
  ///
  /// 一次性按最大值创建，切换儿童模式时不再重建，避免销毁仍在组件树上的
  /// FocusNode（那会导致 "used after being disposed" 断言）。
  int get _maxSectionCount {
    final topicCount = kidsTopicCatalog.length;
    final categoryCount = HomeCategory.values.length;
    return topicCount > categoryCount ? topicCount : categoryCount;
  }

  /// 第 index 行的标题
  String _sectionLabel(int index) {
    if (_kidsMode) {
      if (index < 0 || index >= _kidsTopics.length) return '';
      return _kidsTopics[index].label;
    }
    return _categories[index].label;
  }

  /// 儿童模式开关/主题变化后重建首页
  void _onKidsModeChanged() {
    if (!mounted) return;

    // 只重置数据，不重建焦点节点：焦点节点按索引复用，多出来的闲置即可
    setState(() {
      _kidsMode = KidsModeService.enabled;
      _kidsTopics = KidsModeService.topics;
      _selectedCategoryIndex = 0;
      _categoryVideos.clear();
      _categoryLoading.clear();
      _categoryPage.clear();
      _categoryRefreshIdx.clear();
      _firstLoadDone = false;
      _usedPreloadedData = false;
    });

    _loadVideosForCategory(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onFirstLoadComplete?.call();
    });
  }

  // ... (省略 _loadCategoryOrder, dispose 等未改动代码) ...

  void _loadCategoryOrder() {
    final order = SettingsService.categoryOrder;
    final enabled = SettingsService.enabledCategories;
    _categories = order
        .where((name) => enabled.contains(name))
        .map(
          (name) => HomeCategory.values.firstWhere(
            (c) => c.name == name,
            orElse: () => HomeCategory.recommend,
          ),
        )
        .toList();
    if (_categories.isEmpty) _categories = [HomeCategory.recommend];
  }

  @override
  void dispose() {
    KidsModeService.revision.removeListener(_onKidsModeChanged);
    _scrollController.dispose();
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    // 清理视频卡片的 FocusNode
    for (final node in _videoFocusNodes.values) {
      node.dispose();
    }
    _videoFocusNodes.clear();
    super.dispose();
  }

  // 获取或创建视频卡片的 FocusNode
  FocusNode _getFocusNode(int index) {
    return _videoFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  List<Video> get _currentVideos =>
      _categoryVideos[_selectedCategoryIndex] ?? [];
  bool get _isLoading => _categoryLoading[_selectedCategoryIndex] ?? false;

  Future<void> _loadVideosForCategory(
    int categoryIndex, {
    bool refresh = false,
  }) async {
    // 儿童模式下一个主题都没开，没有内容可加载
    if (_sectionCount == 0) return;
    if (_categoryLoading[categoryIndex] == true) return;

    // ... (保持原有的分页逻辑) ...
    final currentPage = _categoryPage[categoryIndex] ?? 1;
    final currentRefreshIdx = _categoryRefreshIdx[categoryIndex] ?? 0;

    if (refresh) {
      _categoryPage[categoryIndex] = 1;
      _categoryRefreshIdx[categoryIndex] = 0;
      setState(() {
        _categoryLoading[categoryIndex] = true;
        _categoryVideos[categoryIndex] = [];
        _isRefreshing = true; // 开始刷新
      });
    } else {
      setState(() => _categoryLoading[categoryIndex] = true);
    }

    List<Video> videos;

    try {
      if (_kidsMode) {
        // 儿童模式：只加载白名单主题内容，永远不调用推荐接口
        final topic = _kidsTopics[categoryIndex];
        final page = refresh ? 1 : currentPage;
        videos = await KidsFeedService.loadTopicFeed(topic, page: page);
      } else {
        final category = _categories[categoryIndex];
        // 网络请求逻辑...
        switch (category) {
          case HomeCategory.recommend:
            final idx = refresh ? 0 : currentRefreshIdx;
            videos = await BilibiliApi.getRecommendVideos(idx: idx);
            _categoryRefreshIdx[categoryIndex] = idx + 1;
            break;
          case HomeCategory.popular:
            final page = refresh ? 1 : currentPage;
            videos = await BilibiliApi.getPopularVideos(page: page);
            break;
          default:
            final page = refresh ? 1 : currentPage;
            videos = await BilibiliApi.getRegionVideos(
              tid: category.tid,
              page: page,
            );
            break;
        }
      }
    } catch (e) {
      videos = [];
    }

    if (!mounted) return;
    setState(() {
      final page = _categoryPage[categoryIndex] ?? 1;

      // 插件过滤 + 儿童模式白名单二次兜底
      final filteredVideos = KidsModeService.filter(_filterVideos(videos));

      if (refresh || page == 1) {
        _categoryVideos[categoryIndex] = filteredVideos;
      } else {
        _categoryVideos[categoryIndex] = [
          ...(_categoryVideos[categoryIndex] ?? []),
          ...filteredVideos,
        ];
      }
      _categoryLoading[categoryIndex] = false;
      _isRefreshing = false; // 刷新完成

      if (!_firstLoadDone) {
        _firstLoadDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onFirstLoadComplete?.call();
        });
      }
    });
  }

  // ... (省略 _loadMore, _switchCategory 等辅助方法) ...
  void _loadMore() {
    if (_isLoading) return;
    final page = (_categoryPage[_selectedCategoryIndex] ?? 1) + 1;
    _categoryPage[_selectedCategoryIndex] = page;
    _loadVideosForCategory(_selectedCategoryIndex);
  }

  void _switchCategory(int index) {
    if (_selectedCategoryIndex == index) return;
    // 切换分类后不再是初始预加载状态
    _usedPreloadedData = false;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() => _selectedCategoryIndex = index);
    if ((_categoryVideos[index] ?? []).isEmpty) _loadVideosForCategory(index);
  }

  void refreshCurrentCategory() {
    // 刷新后不再是初始预加载状态
    _usedPreloadedData = false;
    _loadVideosForCategory(_selectedCategoryIndex, refresh: true);
  }

  void _onVideoTap(Video video) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => PlayerScreen(video: video)));
  }

  @override
  Widget build(BuildContext context) {
    // 儿童模式下不要求登录（孩子不需要账号），普通模式维持原有登录校验
    if (!_kidsMode && !AuthService.isLoggedIn) {
      return const Center(child: Text("请先登录")); // 简写，保持你原有的 UI
    }

    // 儿童模式但一个主题都没启用：给出明确指引，而不是空白页
    if (_kidsMode && _kidsTopics.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.child_care, size: 72, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              '儿童模式已开启，但还没有启用任何主题',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              '请到 设置 → 儿童模式 中打开“我的世界”“芭比娃娃”等主题',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // 判断是否是"启动后的第一屏数据"
    // 使用稳定的标志变量，避免 List 引用比较在 loadMore 后失效
    final bool isInitialLoad =
        _selectedCategoryIndex == 0 && _usedPreloadedData;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: FocusTraversalGroup(
            child: _isLoading && _currentVideos.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : (!_isLoading && _currentVideos.isEmpty && _kidsMode)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.search_off,
                          size: 56,
                          color: Colors.white24,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '“${_sectionLabel(_selectedCategoryIndex)}”暂时没有获取到内容',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '按确定键重新加载，或换个主题',
                          style: TextStyle(color: Colors.white24, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : SizeCacheWidget(
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(30, 100, 30, 80),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  childAspectRatio: 320 / 280,
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 30,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final video = _currentVideos[index];

                              if (index == _currentVideos.length - 4) {
                                _loadMore();
                              }

                              // 【优化】只有刷新时才使用交错加载
                              // 初始加载和从播放器返回时，图片已在缓存中，直接显示
                              final int? staggerIdx = _isRefreshing
                                  ? (index % 8)
                                  : null;

                              // 构建卡片内容
                              Widget buildCard(BuildContext ctx) {
                                return TvVideoCard(
                                  video: video,
                                  focusNode: _getFocusNode(index),
                                  autofocus: isInitialLoad && index == 0,
                                  disableCache: false,
                                  staggerIndex: staggerIdx,
                                  onTap: () => _onVideoTap(video),
                                  onMoveLeft: (index % 4 == 0)
                                      ? () => widget.sidebarFocusNode
                                            ?.requestFocus()
                                      : () => _getFocusNode(
                                          index - 1,
                                        ).requestFocus(),
                                  // 强制向右导航，避免 ScaleTransition 导致的误判
                                  onMoveRight:
                                      (index + 1 < _currentVideos.length)
                                      ? () => _getFocusNode(
                                          index + 1,
                                        ).requestFocus()
                                      : null,
                                  // 严格按列向上移动（4个一行），最顶行跳到分类标签
                                  onMoveUp: index >= 4
                                      ? () => _getFocusNode(
                                          index - 4,
                                        ).requestFocus()
                                      : () =>
                                            _categoryFocusNodes[_selectedCategoryIndex]
                                                .requestFocus(),
                                  // 严格按列向下移动
                                  onMoveDown:
                                      (index + 4 < _currentVideos.length)
                                      ? () => _getFocusNode(
                                          index + 4,
                                        ).requestFocus()
                                      : null,
                                  onFocus: () {
                                    if (!_scrollController.hasClients) {
                                      return;
                                    }

                                    final RenderObject? object = ctx
                                        .findRenderObject();
                                    if (object != null && object is RenderBox) {
                                      final viewport =
                                          RenderAbstractViewport.of(object);
                                      final offsetToReveal = viewport
                                          .getOffsetToReveal(object, 0.0)
                                          .offset;
                                      final targetOffset =
                                          (offsetToReveal - 120).clamp(
                                            0.0,
                                            _scrollController
                                                .position
                                                .maxScrollExtent,
                                          );

                                      if ((_scrollController.offset -
                                                  targetOffset)
                                              .abs() >
                                          50) {
                                        _scrollController.animateTo(
                                          targetOffset,
                                          duration: const Duration(
                                            milliseconds: 500,
                                          ),
                                          curve: Curves.easeOutCubic,
                                        );
                                      }
                                    }
                                  },
                                );
                              }

                              // 只有刷新时使用分帧渲染，其他情况直接渲染
                              if (_isRefreshing) {
                                return FrameSeparateWidget(
                                  index: index,
                                  placeHolder: const Center(
                                    child: SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  child: Builder(builder: buildCard),
                                );
                              }

                              return Builder(builder: buildCard);
                            }, childCount: _currentVideos.length),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        // ... (Header / Category Tabs 保持不变) ...
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 80,
          child: Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.only(left: 30, right: 30, top: 20),
            child: FocusTraversalGroup(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // 儿童模式标识：明确告诉家长当前只展示白名单内容
                    if (_kidsMode) ...[
                      Container(
                        margin: const EdgeInsets.only(right: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFfb7299).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFfb7299),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.child_care,
                              size: 16,
                              color: Color(0xFFfb7299),
                            ),
                            SizedBox(width: 4),
                            Text(
                              '儿童模式',
                              style: TextStyle(
                                color: Color(0xFFfb7299),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    ...List.generate(_sectionCount, (index) {
                      return _CategoryTab(
                        label: _sectionLabel(index),
                        isSelected: _selectedCategoryIndex == index,
                        focusNode: _categoryFocusNodes[index],
                        onTap: () => _switchCategory(index),
                        onFocus: () => _switchCategory(index),
                        onConfirm: refreshCurrentCategory,
                        onMoveLeft: index == 0
                            ? () => widget.sidebarFocusNode?.requestFocus()
                            : null,
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Positioned(top: 20, right: 30, child: TimeDisplay()),
      ],
    );
  }

  List<Video> _filterVideos(List<Video> videos) {
    if (videos.isEmpty) return [];
    final plugins = PluginManager().getEnabledPlugins<FeedPlugin>();
    if (plugins.isEmpty) return videos;

    return videos.where((video) {
      for (final plugin in plugins) {
        if (!plugin.shouldShowItem(video)) return false;
      }
      return true;
    }).toList();
  }
}

/// 分类标签组件
class _CategoryTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback onConfirm;
  final VoidCallback? onMoveLeft;

  const _CategoryTab({
    required this.label,
    required this.isSelected,
    required this.focusNode,
    required this.onTap,
    required this.onFocus,
    required this.onConfirm,
    this.onMoveLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (f) => f ? onFocus() : null,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                onMoveLeft != null) {
              onMoveLeft!();
              return KeyEventResult.handled;
            }
            // 确定键刷新当前分类
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              onConfirm();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (ctx) {
            final f = Focus.of(ctx).hasFocus;
            return GestureDetector(
              onTap: onTap,
              child: Container(
                // 紧凑的 padding 确保文字高度位置与普通标题接近
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                decoration: BoxDecoration(
                  color: f ? const Color(0xFFfb7299) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: f ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: f
                            ? Colors.white
                            : (isSelected
                                  ? const Color(0xFFfb7299)
                                  : Colors.grey),
                        fontSize: 20,
                        fontWeight: f || isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 3,
                      width: 20,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFfb7299)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 首页分类枚举
enum HomeCategory {
  recommend('推荐', 0),
  popular('热门', 0),
  anime('番剧', 13),
  movie('影视', 181),
  game('游戏', 4),
  knowledge('知识', 36),
  tech('科技', 188),
  music('音乐', 3),
  dance('舞蹈', 129),
  life('生活', 160),
  food('美食', 211),
  douga('动画', 1);

  const HomeCategory(this.label, this.tid);
  final String label;
  final int tid;
}
