import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:bili_tv_app/models/video.dart';
import 'home/home_tab.dart';
import 'home/history_tab.dart';
import 'home/search_tab.dart';
import 'home/login_tab.dart';
import 'home/dynamic_tab.dart';
import 'home/live_tab.dart';
import '../widgets/tv_focusable_item.dart';
import '../services/auth_service.dart';
import '../services/kids_mode_service.dart';
import '../services/settings_service.dart';

/// 侧边栏标签类型
enum SideTabType { search, home, dynamic, history, live, login }

/// 侧边栏标签定义（图标 + 类型）
class _SideTab {
  final SideTabType type;
  final String icon;

  const _SideTab(this.type, this.icon);
}

/// 全部标签（儿童模式下会隐藏动态和直播）
const List<_SideTab> _allSideTabs = [
  _SideTab(SideTabType.search, 'assets/icons/search.svg'),
  _SideTab(SideTabType.home, 'assets/icons/home.svg'),
  _SideTab(SideTabType.dynamic, 'assets/icons/dynamic.svg'),
  _SideTab(SideTabType.history, 'assets/icons/history.svg'),
  _SideTab(SideTabType.live, 'assets/icons/live.svg'),
  _SideTab(SideTabType.login, 'assets/icons/user.svg'),
];

/// 主页框架
class HomeScreen extends StatefulWidget {
  final List<Video>? preloadedVideos;

  const HomeScreen({super.key, this.preloadedVideos});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 当前可见的标签（顺序即侧边栏顺序）
  List<_SideTab> _tabs = List<_SideTab>.of(_allSideTabs);
  int _selectedTabIndex = 0;
  DateTime? _lastBackPressed;
  DateTime? _backFromSearchHandled; // 防止搜索键盘返回键重复处理

  /// 每个标签类型固定一个 FocusNode，避免切换儿童模式时销毁/重建焦点节点
  late final Map<SideTabType, FocusNode> _sideBarFocusNodes = {
    for (final tab in _allSideTabs) tab.type: FocusNode(),
  };

  // 用于访问 SearchTab 状态
  final GlobalKey<SearchTabState> _searchTabKey = GlobalKey<SearchTabState>();
  // 用于访问 HomeTab 状态 (刷新功能)
  final GlobalKey<HomeTabState> _homeTabKey = GlobalKey<HomeTabState>();
  // 动态和历史记录 Tab - 每次切换时刷新
  final GlobalKey<DynamicTabState> _dynamicTabKey =
      GlobalKey<DynamicTabState>();
  final GlobalKey<HistoryTabState> _historyTabKey =
      GlobalKey<HistoryTabState>();
  final GlobalKey<LoginTabState> _loginTabKey = GlobalKey<LoginTabState>();
  // 直播 Tab
  final GlobalKey<LiveTabState> _liveTabKey = GlobalKey<LiveTabState>();

  @override
  void initState() {
    super.initState();
    _applyTabVisibility();

    // 儿童模式开关变化时重新计算侧边栏
    KidsModeService.revision.addListener(_onKidsModeChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 确保 Highlight 策略正确
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
    });
  }

  /// 根据儿童模式计算可见标签
  ///
  /// [keepCurrent] 为 true 时尽量停留在当前所在标签（设置里改儿童模式时用）；
  /// 为 false 时定位到首页（App 启动时用，首页才是该有的入口，
  /// 不能一打开就停在搜索键盘上）。
  void _applyTabVisibility({bool keepCurrent = false}) {
    final kidsMode = KidsModeService.enabled;

    var target = SideTabType.home;
    if (keepCurrent &&
        _tabs.isNotEmpty &&
        _selectedTabIndex >= 0 &&
        _selectedTabIndex < _tabs.length) {
      target = _tabs[_selectedTabIndex].type;
    }

    _tabs = _allSideTabs
        .where(
          (tab) =>
              !kidsMode ||
              (tab.type != SideTabType.dynamic &&
                  tab.type != SideTabType.live),
        )
        .toList();

    final index = _tabs.indexWhere((tab) => tab.type == target);
    _selectedTabIndex = index >= 0 ? index : _indexOf(SideTabType.home);
  }

  void _onKidsModeChanged() {
    if (!mounted) return;
    // 改儿童模式/主题时保持在当前标签页
    setState(() => _applyTabVisibility(keepCurrent: true));

    // 切换后把焦点放到当前标签上，避免焦点停在已隐藏的图标上
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sideBarFocusNodes[_tabs[_selectedTabIndex].type]?.requestFocus();
    });
  }

  int _indexOf(SideTabType type) => _tabs.indexWhere((tab) => tab.type == type);

  /// 取某个标签的焦点节点（所有标签类型在初始化时都已创建）
  FocusNode _focusNodeOf(SideTabType type) => _sideBarFocusNodes[type]!;

  SideTabType get _currentTabType => _tabs[_selectedTabIndex].type;

  // 激活焦点系统
  void _activateFocusSystem() {
    if (!mounted) return;

    // 强制设置高亮策略为传统模式 (TV 模式)
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;

    final currentFocusNode = _sideBarFocusNodes[_currentTabType];
    if (currentFocusNode != null && !currentFocusNode.hasFocus) {
      currentFocusNode.requestFocus();
    }

    // 首页加载完成后，延迟后台预加载动态和历史记录
    _preloadOtherTabs();
  }

  // 后台预加载动态和历史记录
  void _preloadOtherTabs() {
    // 延迟 500ms 后开始预加载，避免影响首页渲染
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      // 预加载动态页面（如果用户已登录，且儿童模式下未被隐藏）
      if (AuthService.isLoggedIn && _indexOf(SideTabType.dynamic) >= 0) {
        _dynamicTabKey.currentState?.refresh();
      }
    });

    // 再延迟 1 秒后预加载历史记录
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      // 预加载历史记录（如果用户已登录）
      if (AuthService.isLoggedIn) {
        _historyTabKey.currentState?.refresh();
      }
    });

    // 预加载直播（儿童模式下没有直播入口，跳过）
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      if (_indexOf(SideTabType.live) < 0) return;
      _liveTabKey.currentState?.refresh();
    });
  }

  @override
  void dispose() {
    KidsModeService.revision.removeListener(_onKidsModeChanged);
    for (var node in _sideBarFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleSideBarTap(int index) {
    final type = _tabs[index].type;

    // 如果已经在当前标签，点击刷新
    if (index == _selectedTabIndex) {
      switch (type) {
        case SideTabType.home:
          _homeTabKey.currentState?.refreshCurrentCategory();
          break;
        case SideTabType.dynamic:
          _dynamicTabKey.currentState?.refresh();
          break;
        case SideTabType.history:
          _historyTabKey.currentState?.refresh();
          break;
        case SideTabType.live:
          _liveTabKey.currentState?.refresh();
          break;
        case SideTabType.search:
        case SideTabType.login:
          break;
      }
      return;
    }

    setState(() => _selectedTabIndex = index);
    _sideBarFocusNodes[type]?.requestFocus();

    // 动态和历史记录、直播标签: 切换时也刷新
    switch (type) {
      case SideTabType.dynamic:
        _dynamicTabKey.currentState?.refresh();
        break;
      case SideTabType.history:
        _historyTabKey.currentState?.refresh();
        break;
      case SideTabType.live:
        _liveTabKey.currentState?.refresh();
        break;
      case SideTabType.search:
      case SideTabType.home:
      case SideTabType.login:
        break;
    }
  }

  void _refreshCurrentTab() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 检查是否刚刚被搜索键盘的返回键处理过
        if (_backFromSearchHandled != null &&
            DateTime.now().difference(_backFromSearchHandled!) <
                const Duration(milliseconds: 200)) {
          return; // 已被处理，忽略
        }

        // 搜索标签需要特殊处理：结果界面返回键盘，键盘返回主页
        if (_currentTabType == SideTabType.search) {
          final handled = _searchTabKey.currentState?.handleBack() ?? false;
          if (!handled) {
            // 键盘界面 → 回主页
            setState(() => _selectedTabIndex = _indexOf(SideTabType.home));
            _focusNodeOf(SideTabType.home).requestFocus();
          }
          return;
        }

        if (_currentTabType != SideTabType.home) {
          // 其他标签（历史、直播、登录）按返回键都回到主页
          setState(() => _selectedTabIndex = _indexOf(SideTabType.home));
          _focusNodeOf(SideTabType.home).requestFocus();
          return;
        }

        // 主页标签：按两次退出
        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;

          Fluttertoast.showToast(
            msg: '再按一次返回键退出应用',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.CENTER,
            backgroundColor: Colors.black.withValues(alpha: 0.7),
            textColor: Colors.white,
            fontSize: 18.0,
          );
        } else {
          // 退出前清理缓存
          await SettingsService.clearImageCache();
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧边栏
            Expanded(
              flex: 8,
              child: Container(
                color: const Color(0xFF1E1E1E),
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: List.generate(_tabs.length, (index) {
                    final type = _tabs[index].type;
                    final isUserTab = type == SideTabType.login;
                    final avatarUrl = isUserTab && AuthService.isLoggedIn
                        ? AuthService.face
                        : null;

                    return TvFocusableItem(
                      iconPath: _tabs[index].icon,
                      avatarUrl: avatarUrl,
                      isSelected: _selectedTabIndex == index,
                      focusNode: _sideBarFocusNodes[type]!,
                      onFocus: () {
                        // 焦点移动时只切换标签页，不刷新任何内容
                        setState(() => _selectedTabIndex = index);
                      },
                      onTap: () => _handleSideBarTap(index), // 按确定键才刷新
                      // 直播/用户标签按右键导航到内容区
                      // 用户标签现在未登录也能进设置，所以不再要求已登录
                      onMoveRight: type == SideTabType.live
                          ? () {
                              _liveTabKey.currentState?.focusFirstItem();
                            }
                          : isUserTab
                          ? () =>
                                _loginTabKey.currentState?.focusFirstCategory()
                          : null,
                    );
                  }),
                ),
              ),
            ),
            // 右侧内容区
            Expanded(flex: 92, child: _buildRightContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildRightContent() {
    // 使用 IndexedStack 保持所有 Tab 状态，避免切换时重新加载
    // 使用 GlobalKey 保证调整可见标签后状态仍然保留
    return IndexedStack(
      index: _selectedTabIndex,
      children: _tabs.map(_buildTabContent).toList(),
    );
  }

  Widget _buildTabContent(_SideTab tab) {
    switch (tab.type) {
      case SideTabType.search:
        return SearchTab(
          key: _searchTabKey,
          sidebarFocusNode: _focusNodeOf(SideTabType.search),
          onBackToHome: () {
            _backFromSearchHandled = DateTime.now(); // 记录处理时间
            setState(() => _selectedTabIndex = _indexOf(SideTabType.home));
            _focusNodeOf(SideTabType.home).requestFocus();
          },
        );
      case SideTabType.home:
        return HomeTab(
          key: _homeTabKey,
          sidebarFocusNode: _focusNodeOf(SideTabType.home),
          onFirstLoadComplete: _activateFocusSystem,
          preloadedVideos: widget.preloadedVideos,
        );
      case SideTabType.dynamic:
        return DynamicTab(
          key: _dynamicTabKey,
          sidebarFocusNode: _focusNodeOf(SideTabType.dynamic),
          isVisible: _currentTabType == SideTabType.dynamic,
        );
      case SideTabType.history:
        return HistoryTab(
          key: _historyTabKey,
          sidebarFocusNode: _focusNodeOf(SideTabType.history),
          isVisible: _currentTabType == SideTabType.history,
        );
      case SideTabType.live:
        return LiveTab(
          key: _liveTabKey,
          sidebarFocusNode: _focusNodeOf(SideTabType.live),
          isVisible: _currentTabType == SideTabType.live,
        );
      case SideTabType.login:
        return LoginTab(
          key: _loginTabKey,
          sidebarFocusNode: _focusNodeOf(SideTabType.login),
          onLoginSuccess: _refreshCurrentTab,
        );
    }
  }
}
