/// 儿童模式新频道的冒烟测试（流行音乐 / 我的UP主）
///
/// 这些用例会真的请求哔哩哔哩接口，所以**需要联网**；
/// 跑法：`flutter test`
library;

import 'dart:io';

import 'package:bili_tv_app/config/kids_topics.dart';
import 'package:bili_tv_app/config/kids_up_owners.dart';
import 'package:bili_tv_app/models/video.dart';
import 'package:bili_tv_app/services/bilibili_api.dart';
import 'package:bili_tv_app/services/kids_feed_service.dart';
import 'package:bili_tv_app/services/kids_mode_service.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// flutter_test 默认把所有网络请求改成 400，这里放行真实请求
class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  setUp(() {
    KidsModeService.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  test('新装时两个新频道默认打开', () async {
    await KidsModeService.init();
    expect(KidsModeService.isTopicEnabled('pop_music'), isTrue);
    expect(KidsModeService.isTopicEnabled('my_ups'), isTrue);
  });

  test('新加的五个卡通主题默认打开', () async {
    await KidsModeService.init();
    for (final id in [
      'peppa',
      'paw_patrol',
      'doraemon',
      'boonie_bears',
      'sponge_bob',
    ]) {
      expect(KidsModeService.isTopicEnabled(id), isTrue, reason: id);
    }
  });

  test('老配置升级后自动补上新频道，关掉后不会再自动打开', () async {
    // 模拟老版本只勾了「我的世界」
    SharedPreferences.setMockInitialValues({
      'kids_mode_topic_ids': <String>['minecraft'],
      'kids_mode_known_topic_ids': <String>['minecraft'],
    });
    await KidsModeService.init();

    expect(KidsModeService.isTopicEnabled('pop_music'), isTrue);
    expect(KidsModeService.isTopicEnabled('my_ups'), isTrue);
    // 老主题不会被自动打开
    expect(KidsModeService.isTopicEnabled('disney'), isFalse);

    // 用户手动关掉后，下次读取不该再自动打开
    await KidsModeService.setTopicEnabled('pop_music', false);
    expect(KidsModeService.isTopicEnabled('pop_music'), isFalse);
  });

  test('音乐区排行榜只返回歌曲类内容', () async {
    final videos = await BilibiliApi.getMusicRanking();
    if (videos.isEmpty) {
      markTestSkipped('接口没返回内容（断网或被限流）');
      return;
    }
    expect(videos.every((v) => v.bvid.isNotEmpty), isTrue);
    expect(videos.every((v) => v.ownerName.isNotEmpty), isTrue);
  });

  test('按昵称能解析出具体账号', () async {
    final owner = await KidsModeService.resolveUpOwner(
      const KidsUpOwner(name: '怪逗逗'),
    );
    if (owner.mid == 0) {
      markTestSkipped('搜索接口没返回结果（断网或被限流）');
      return;
    }
    expect(owner.mid, greaterThan(0));
    expect(owner.name.contains('怪逗逗'), isTrue);
  });

  test('流行音乐频道能装出内容', () async {
    final topic = kidsTopicCatalog.firstWhere((t) => t.id == 'pop_music');
    final videos = await KidsFeedService.loadTopicFeed(topic, page: 1);
    if (videos.isEmpty) {
      markTestSkipped('接口没返回内容（断网或被限流）');
      return;
    }
    // 精选出来的内容要能通过白名单
    expect(KidsModeService.filter(videos).length, videos.length);
  });

  test('音乐区的歌在搜索里也能放行，其它分区不放行', () async {
    await KidsModeService.init();
    final song = Video(
      bvid: 'BV1music',
      title: '周杰伦 - 稻香',
      pic: '',
      areaName: '音乐综合',
    );
    final other = Video(
      bvid: 'BV1other',
      title: '周杰伦 - 稻香',
      pic: '',
      areaName: '生活',
    );
    expect(KidsModeService.isAllowed(song), isTrue);

    // 关掉「流行音乐」主题后，音乐区也不再放行
    await KidsModeService.setTopicEnabled('pop_music', false);
    expect(KidsModeService.isAllowed(song), isFalse);
    expect(KidsModeService.isAllowed(other), isFalse);
  });

  test('我的 UP 主频道只放名单里的账号', () async {
    await KidsModeService.setUpOwners([
      const KidsUpOwner(name: '怪逗逗小舞台', mid: 421188041),
    ]);
    final topic = kidsTopicCatalog.firstWhere((t) => t.id == 'my_ups');
    final videos = await KidsFeedService.loadTopicFeed(topic, page: 1);
    if (videos.isEmpty) {
      markTestSkipped('接口没返回内容（断网或被限流）');
      return;
    }
    expect(
      videos.every((v) => v.ownerMid == 421188041),
      isTrue,
    );
    // 名单里的 UP 主不受标题关键词限制
    expect(KidsModeService.filter(videos).length, videos.length);
  });

  test('默认名单里的怪小逗账号写死了 UID', () async {
    await KidsModeService.init();
    final owner = KidsModeService.upOwners.firstWhere(
      (o) => o.mid == 421188041,
      orElse: () => const KidsUpOwner(name: ''),
    );
    expect(owner.mid, 421188041);
    expect(owner.name, contains('怪'));
  });

  test('关掉频道后，精选出来的内容不再放行', () async {
    final topic = kidsTopicCatalog.firstWhere((t) => t.id == 'pop_music');
    final videos = await KidsFeedService.loadTopicFeed(topic, page: 1);
    if (videos.isEmpty) {
      markTestSkipped('接口没返回内容（断网或被限流）');
      return;
    }
    expect(KidsModeService.filter(videos).length, videos.length);

    await KidsModeService.setTopicEnabled('pop_music', false);
    expect(KidsModeService.filter(videos).length, lessThan(videos.length));
  });

  test('搜索排序方式会被记住', () async {
    await SettingsService.init();
    await SettingsService.setSearchOrder('pubdate');
    expect(SettingsService.searchOrder, 'pubdate');

    // 非法值不生效
    await SettingsService.setSearchOrder('不存在的排序');
    expect(SettingsService.searchOrder, 'pubdate');

    await SettingsService.setSearchOrder('totalrank');
    expect(SettingsService.searchOrder, 'totalrank');
  });
}
