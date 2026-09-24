## 原生 Android TV 版本（繁体中文支持）

后续会专注于优化原生版

[BiliTVNative](https://github.com/Hyper-Beast/BiliTVNative)


原生版截图
<img width="2048" height="1104" alt="image" src="https://github.com/user-attachments/assets/9d57c6c7-d1ed-4960-b86b-de475949f88b" />






# BiliTV 📺

一款专为 Android TV 设计的第三方哔哩哔哩客户端，使用 Flutter 开发。从图标到开屏动画到全部代码100%由AI开发，本人只负责提出需求和测试，测试设备有限，仅测试了索尼电视（armv7,安卓9）和redmi G Pro 27U（armv8,澎湃OS2）显示器，理论支持的最低安卓版本为安卓5，其他设备请自行测试。

更新功能是我自己内测使用，开源版本未实装

## 🧒 儿童模式（内容白名单）

默认开启。开启后本应用**不再有任何推荐流**，只播放白名单里的主题内容：

**默认启用 4 个主题：我的世界、芭比娃娃、美甲、盖房子**（内置共 16 个，其余可在设置或网页里打开）。

- **首页 = 主题行**：只显示已启用的主题，一屏一行，没有推荐、热门、分区。
- **搜索也被过滤**：搜索结果里只保留命中主题关键词的视频，并会自动连翻几页补齐结果。
- **播放器只连播同主题**：「更多视频」和播完自动连播改为同一 UP 主的投稿 → 官方相关推荐（逐个过滤）→ 同主题搜索，永远不会跳到无关内容。
- **隐藏动态与直播**：侧边栏不再出现动态、直播入口。
- **内容屏蔽词**：标题命中屏蔽词直接不显示。全局屏蔽「漫剧 / 短剧 / 免费观看 / 荃集」等投流广告标记（对所有主题生效，且优先于信任名单）；每个主题另有自己的屏蔽词，比如「美甲」屏蔽 33 个课程/开店/带货词，「盖房子」屏蔽游戏与恐怖向词。
- **UP 主信任名单**：标题命中主题的视频，其作者会被自动加入信任名单（可关闭），之后这些 UP 主的投稿都会被视为安全内容；设置页可以一键清空。
- **无需登录**：儿童模式下不要求登录 bilibili（请求会带上本地生成的匿名设备指纹 buvid3）。

### 主题是怎么定关键词的

以「盖房子」为例（要求是**真实世界建房 vlog**，不要投流广告和游戏广告）：

| 项 | 内容 | 为什么 |
|---|---|---|
| 搜索词 | 农村建房 / 自建房 全过程 / 野外搭建庇护所 / 荒野 建造 庇护所 | 实测这几个词搜出来的都是真实建房长视频；「森林 木屋 搭建」会搜出《森林之子》《TheForest》等游戏，故弃用 |
| 标题匹配词 | 建房 / 盖房 / 搭建 / 庇护所 / 建造 / 木屋 / 施工 | 只保留标题含这些词的 |
| 屏蔽词 | 游戏 / 攻略 / 教学 / 森林之子 / 我的世界 / 诡异 / 恐怖 / 广告 / 女友 / 富二代 / 觉醒 / 穿越 … | 「庇护所」裸词会搜出末日爽文漫剧，这里挡掉 |

调主题词时建议先跑一遍搜索看真实结果——关键词的**命中率高不等于内容对**，比如「盖房子」命中 14/20，但里面混着成人三农 vlog。

### 添加自己的主题（手机/电脑网页配置）

电视遥控器打中文很痛苦，所以推荐用手机配：

1. 手机连上**和电视同一个 Wi-Fi**
2. 浏览器打开 `http://<电视IP>:3322/kids`
   （电视上「设置 → 儿童模式」里会直接显示这个网址，不用自己查 IP）
3. 勾选内置主题，或输入任意新主题名点「添加」

**改完立即生效，电视上不需要任何操作。** 网页里还能开关儿童模式、开关自动信任、清空信任名单。

主题名会同时作为搜索词和标题匹配词：搜索结果标题里出现这个词才会显示；想覆盖更全可以再填「额外搜索词」。

也可以直接改代码：主题定义在 `lib/config/kids_topics.dart`，加一条 `KidsTopic` 即可。

### 设置入口

侧边栏「用户」标签就是设置页，**未登录也能进**（登录入口在「账号」分类里）。
儿童模式本身不需要登录 bilibili 也能正常使用，只是未登录只能看 360P/480P。

> 说明：白名单是“标题关键词 + UP 主”两级过滤，能挡住绝大多数无关内容，但哔哩哔哩的搜索结果本身不保证内容分级，仍建议家长偶尔抽查。

## ✨ 功能特色


### 截图展示
<img width="189" height="139" alt="image" src="https://github.com/user-attachments/assets/52b04c2a-85b6-4e35-bc3b-10e6bd588a4e" />
<img width="1193" height="666" alt="image" src="https://github.com/user-attachments/assets/7d779704-6709-49a3-957a-4253403bd71e" />
<img width="1203" height="668" alt="image" src="https://github.com/user-attachments/assets/b6784e77-96c5-40da-b567-9e8c6574b704" />
<img width="1069" height="569" alt="image" src="https://github.com/user-attachments/assets/209de939-bc94-4dc3-a8fd-1d9c57c4378d" />
<img width="1080" height="558" alt="image" src="https://github.com/user-attachments/assets/aeb84e09-7388-4ab6-b9be-b0da0340ddde" />






### 🎬 视频播放
- **多编解码器支持** - H.264 / H.265 / AV1 硬件解码，自动选择最优编码
- **DASH 视频流** - 高质量视频 + 独立音轨播放
- **多画质切换** - 支持 4K/1080P+/1080P/720P/480P 等多种画质
- **实时弹幕** - 完整弹幕体验，支持开关、透明度、字体大小、显示区域调节
- **弹幕倍速同步** - 弹幕飞行速度随播放倍速自动调整
- **播放进度记忆** - 自动保存播放进度，下次打开自动续播
- **自动连播** - 支持多P视频自动播放下一集，播完自动播放推荐
- **快进预览** - 拖动进度条时实时预览画面（雪碧图预览）
- **多P雪碧图支持** - 切换分P时自动加载对应预览图

### 📱 用户功能
- **二维码登录** - 使用手机扫码快速登录
- **动态页面** - 查看关注UP主的最新动态
- **观看历史** - 自动记录并同步云端历史，显示"已看完"状态
- **搜索功能** - 支持关键词搜索，保存搜索历史（最多10条）
- **推荐视频** - 首页展示个性化推荐内容（儿童模式关闭时）
- **儿童模式** - 内容白名单，只播放指定主题，无推荐流（默认开启，见上文）
- **分区浏览** - 动画、游戏、音乐、科技等多分区内容
- **分区管理** - 自定义首页分区顺序和启用状态

### 🎮 TV 遥控器优化
- **完整遥控器支持** - 方向键导航、确认键选择、返回键退出
- **焦点系统** - 清晰的焦点高亮，便于遥控器操作
- **快速切换** - 侧边栏一键切换首页/动态/搜索/历史/用户
- **播放器快捷键** - 左右快进快退、上下调节音量、确认暂停

### 🔌 插件系统
- **空降助手** - 基于 SponsorBlock 数据库自动跳过广告、赞助、片头片尾
- **视频过滤** - 按关键词/UP主屏蔽不想看的视频，过滤低质量内容
- **弹幕屏蔽** - 按关键词屏蔽弹幕，支持精确匹配和模糊匹配
- **插件中心** - 统一管理插件开关和配置

### ⚙️ 设置选项

#### 播放设置
- **首选编解码器** - 选择 H.264/H.265/AV1 或自动
- **自动连播开关** - 可选择是否自动播放下一个视频
- **快进预览** - 开启/关闭拖动进度条时的预览

#### 界面设置
- **启动动画** - 开启/关闭应用启动动画
- **迷你进度条** - 播放器底部常驻进度条
- **默认隐藏控制栏** - 播放时自动隐藏控制条
- **播放器时间显示** - 右上角常驻时间
- **分区排序** - 自定义首页分区顺序

#### 存储设置
- **清除缓存** - 清除图片缓存和搜索记录
- **清除播放记录** - 清除本地播放进度

## 🛠️ 技术栈
- **Flutter 3.10+** - 跨平台 UI 框架
- **video_player + ExoPlayer** - 视频播放引擎，支持 DASH 格式
- **canvas_danmaku** - 弹幕渲染引擎
- **cached_network_image** - 图片缓存（限制 200MB，内存缓存 500张）
- **shared_preferences** - 本地数据存储
- **keframe** - 列表渲染性能优化
- **http** - 网络请求

## 📦 编译

```bash
# 获取依赖
flutter pub get

# 编译 APK (Android TV)
flutter build apk --target-platform android-arm64
```

## 🙏 致谢

本项目基于以下开源项目开发，特此感谢：

### 原始项目
- **[BiliPai](https://github.com/jay3-yy/BiliPai)** - 本项目的基础，感谢原作者的工作

### 依赖库
| 库名 | 用途 |
|------|------|
| [video_player](https://pub.dev/packages/video_player) | 视频播放引擎 |
| [canvas_danmaku](https://pub.dev/packages/canvas_danmaku) | 弹幕渲染 |
| [cached_network_image](https://pub.dev/packages/cached_network_image) | 图片缓存 |
| [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager) | 缓存管理 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | 本地存储 |
| [http](https://pub.dev/packages/http) | 网络请求 |
| [qr_flutter](https://pub.dev/packages/qr_flutter) | 二维码生成 |
| [crypto](https://pub.dev/packages/crypto) | MD5 签名 |
| [keframe](https://pub.dev/packages/keframe) | 列表性能优化 |
| [fluttertoast](https://pub.dev/packages/fluttertoast) | Toast 提示 |
| [flutter_svg](https://pub.dev/packages/flutter_svg) | SVG 图标 |
| [marquee](https://pub.dev/packages/marquee) | 滚动文字 |
| [wakelock_plus](https://pub.dev/packages/wakelock_plus) | 屏幕常亮 |
| [path_provider](https://pub.dev/packages/path_provider) | 文件路径 |
| [package_info_plus](https://pub.dev/packages/package_info_plus) | 应用信息 |
| [permission_handler](https://pub.dev/packages/permission_handler) | 权限管理 |

## ⚠️ 免责声明

本项目仅供学习交流使用，请勿用于商业用途。视频内容版权归哔哩哔哩及原作者所有。

## 📄 许可证

GPLV3 License
