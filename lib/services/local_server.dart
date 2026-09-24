import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../config/kids_topics.dart';
import '../plugins/ad_filter_plugin.dart';
import '../plugins/danmaku_enhance_plugin.dart';
import '../core/plugin/plugin_manager.dart';
import 'kids_mode_service.dart';

/// 全局 HTTP 服务
///
/// 提供:
/// 1. MPD 文件代理 (播放器使用)
/// 2. 插件配置 REST API
/// 3. Web 管理界面
class LocalServer {
  static final LocalServer _instance = LocalServer._internal();
  static LocalServer get instance => _instance;

  LocalServer._internal();

  HttpServer? _server;
  String? _currentMpdContent;
  String? _localIp;

  static const int port = 3322;

  /// 服务是否正在运行
  bool get isRunning => _server != null;

  /// 获取服务地址 (用于显示)
  String? get address => _localIp != null ? 'http://$_localIp:$port' : null;

  /// 获取 MPD 播放地址
  String get mpdUrl => 'http://127.0.0.1:$port/video.mpd';

  /// 启动服务
  Future<void> start() async {
    if (_server != null) return;

    try {
      // 获取本地 IP（使用 NetworkInterface）
      _localIp = await _getLocalIp();

      // 绑定到所有网络接口
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handleRequest);

      debugPrint('🌐 LocalServer started at http://$_localIp:$port');
    } catch (e) {
      debugPrint('❌ LocalServer failed to start: $e');
    }
  }

  /// 获取本地 WiFi/以太网 IP 地址
  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (var interface in interfaces) {
        // 优先选择 WiFi 或以太网接口
        final name = interface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('eth') ||
            name.contains('en0')) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback) {
              return addr.address;
            }
          }
        }
      }
      // 回退：返回第一个非回环地址
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting local IP: $e');
    }
    return null;
  }

  /// 停止服务
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _currentMpdContent = null;
    debugPrint('🔴 LocalServer stopped');
  }

  /// 设置当前 MPD 内容
  void setMpdContent(String content) {
    _currentMpdContent = content;
  }

  /// 清除 MPD 内容
  void clearMpdContent() {
    _currentMpdContent = null;
  }

  /// 处理 HTTP 请求
  Future<void> _handleRequest(HttpRequest request) async {
    // CORS 头
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add(
      'Access-Control-Allow-Methods',
      'GET, POST, DELETE, OPTIONS',
    );
    request.response.headers.add(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );

    // 预检请求
    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    try {
      // MPD 文件
      if (path.endsWith('.mpd')) {
        await _serveMpd(request);
      }
      // API 路由
      else if (path.startsWith('/api/')) {
        await _handleApi(request);
      }
      // Web 管理界面
      else if (path == '/' || path == '/index.html') {
        await _serveWebUI(request);
      }
      // 儿童模式配置页（手机/电脑浏览器访问，避免用遥控器输中文）
      else if (path == '/kids' || path == '/kids.html') {
        await _serveKidsWebUI(request);
      }
      // 404
      else {
        request.response.statusCode = 404;
        request.response.write('Not Found');
      }
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write('Error: $e');
    }

    await request.response.close();
  }

  /// 提供 MPD 文件
  Future<void> _serveMpd(HttpRequest request) async {
    if (_currentMpdContent == null) {
      request.response.statusCode = 404;
      request.response.write('No MPD content available');
      return;
    }

    request.response.headers.contentType = ContentType(
      'application',
      'dash+xml',
    );
    request.response.write(_currentMpdContent);
  }

  /// 处理 API 请求
  Future<void> _handleApi(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    // 去广告插件 API
    if (path.startsWith('/api/ad-filter/')) {
      await _handleAdFilterApi(request, path, method);
    }
    // 儿童模式 API（主题白名单）
    else if (path.startsWith('/api/kids/')) {
      await _handleKidsApi(request, path, method);
    }
    // 弹幕增强插件 API
    else if (path.startsWith('/api/danmaku/')) {
      await _handleDanmakuApi(request, path, method);
    } else {
      request.response.statusCode = 404;
      request.response.write('API not found');
    }
  }

  /// 儿童模式 API
  ///
  /// GET  /api/kids/config  读取当前配置（开关、内置主题、自定义主题、信任UP主数量）
  /// POST /api/kids/config  修改配置，body 里给出要改的字段即可
  Future<void> _handleKidsApi(
    HttpRequest request,
    String path,
    String method,
  ) async {
    if (path != '/api/kids/config') {
      _jsonResponse(request, {'error': 'API not found'}, 404);
      return;
    }

    await KidsModeService.init();

    if (method == 'GET') {
      _jsonResponse(request, {
        'enabled': KidsModeService.enabled,
        'autoLearnUps': KidsModeService.autoLearnUps,
        'trustedUpCount': KidsModeService.trustedUpMids.length,
        'presets': kidsTopicCatalog
            .map(
              (t) => {
                'id': t.id,
                'label': t.label,
                'enabled': KidsModeService.isTopicEnabled(t.id),
                'queries': t.queries,
                'matchKeywords': t.matchKeywords,
              },
            )
            .toList(),
        'custom': KidsModeService.customTopics
            .map(
              (t) => {
                'id': t.id,
                'label': t.label,
                'queries': t.queries,
                'matchKeywords': t.matchKeywords,
              },
            )
            .toList(),
      });
      return;
    }

    if (method != 'POST') {
      _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      return;
    }

    final body = await _readJsonBody(request);
    if (body == null) {
      _jsonResponse(request, {'error': 'Invalid body'}, 400);
      return;
    }

    if (body['enabled'] is bool) {
      await KidsModeService.setEnabled(body['enabled'] as bool);
    }
    if (body['autoLearnUps'] is bool) {
      await KidsModeService.setAutoLearnUps(body['autoLearnUps'] as bool);
    }
    if (body['clearTrustedUps'] == true) {
      await KidsModeService.clearTrustedUps();
    }

    // 内置主题：请求里给的是“最终要启用的集合”
    final enabledIds = body['presetEnabledIds'];
    if (enabledIds is List) {
      await KidsModeService.setPresetTopics(
        enabledIds.map((e) => e.toString()).toSet(),
      );
    }

    final removeId = body['removeCustomId'];
    if (removeId is String && removeId.isNotEmpty) {
      await KidsModeService.removeCustomTopic(removeId);
    }

    final add = body['addCustom'];
    if (add is Map) {
      final label = add['label']?.toString().trim() ?? '';
      if (label.isEmpty) {
        _jsonResponse(request, {'error': '主题名不能为空'}, 400);
        return;
      }
      await KidsModeService.addCustomTopic(
        label: label,
        extraQueries: _splitKeywords(add['queries']),
        extraKeywords: _splitKeywords(add['matchKeywords']),
      );
    }

    _jsonResponse(request, {'success': true});
  }

  /// 把请求里的关键词字段统一整理成字符串列表
  ///
  /// 既接受 JSON 数组，也接受「逗号/顿号/空格分隔」的字符串。
  List<String> _splitKeywords(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split(RegExp(r'[,，、\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  /// 去广告插件 API
  Future<void> _handleAdFilterApi(
    HttpRequest request,
    String path,
    String method,
  ) async {
    final plugin = PluginManager().getPlugin<AdFilterPlugin>('ad_filter');
    if (plugin == null) {
      _jsonResponse(request, {'error': 'Plugin not found'}, 404);
      return;
    }

    // /api/ad-filter/config - 获取/更新配置
    if (path == '/api/ad-filter/config') {
      if (method == 'GET') {
        final config = plugin.getConfig();
        _jsonResponse(request, {
          'filterSponsored': config.filterSponsored,
          'filterClickbait': config.filterClickbait,
          'filterLowQuality': config.filterLowQuality,
          'minViewCount': config.minViewCount,
        });
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        if (body != null) {
          if (body.containsKey('filterSponsored')) {
            plugin.setFilterSponsored(body['filterSponsored'] as bool);
          }
          if (body.containsKey('filterClickbait')) {
            plugin.setFilterClickbait(body['filterClickbait'] as bool);
          }
          if (body.containsKey('filterLowQuality')) {
            plugin.setFilterLowQuality(body['filterLowQuality'] as bool);
          }
          if (body.containsKey('minViewCount')) {
            plugin.setMinViewCount(body['minViewCount'] as int);
          }
          _jsonResponse(request, {'success': true});
        } else {
          _jsonResponse(request, {'error': 'Invalid body'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/keywords
    else if (path == '/api/ad-filter/keywords') {
      if (method == 'GET') {
        _jsonResponse(request, {'keywords': plugin.getKeywords()});
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        final keyword = body?['keyword'] as String?;
        if (keyword != null && keyword.isNotEmpty) {
          plugin.addKeyword(keyword);
          _jsonResponse(request, {'success': true, 'keyword': keyword});
        } else {
          _jsonResponse(request, {'error': 'Missing keyword'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/keywords/{keyword}
    else if (path.startsWith('/api/ad-filter/keywords/')) {
      final keyword = Uri.decodeComponent(
        path.substring('/api/ad-filter/keywords/'.length),
      );
      if (method == 'DELETE') {
        plugin.removeKeyword(keyword);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/upnames - UP主名称黑名单
    else if (path == '/api/ad-filter/upnames') {
      if (method == 'GET') {
        _jsonResponse(request, {'upnames': plugin.getBlockedUpNames()});
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        final name = body?['name'] as String?;
        if (name != null && name.isNotEmpty) {
          plugin.addBlockedUpName(name);
          _jsonResponse(request, {'success': true, 'name': name});
        } else {
          _jsonResponse(request, {'error': 'Missing name'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/upnames/{name}
    else if (path.startsWith('/api/ad-filter/upnames/')) {
      final name = Uri.decodeComponent(
        path.substring('/api/ad-filter/upnames/'.length),
      );
      if (method == 'DELETE') {
        plugin.unblockUploaderByName(name);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/blocked - UP主 MID 黑名单
    else if (path == '/api/ad-filter/blocked') {
      if (method == 'GET') {
        _jsonResponse(request, {'blocked': plugin.getBlockedMids()});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/ad-filter/blocked/{mid}
    else if (path.startsWith('/api/ad-filter/blocked/')) {
      final midStr = path.substring('/api/ad-filter/blocked/'.length);
      final mid = int.tryParse(midStr);
      if (method == 'DELETE' && mid != null) {
        plugin.unblockUploader(mid);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Invalid request'}, 400);
      }
    } else {
      _jsonResponse(request, {'error': 'Not found'}, 404);
    }
  }

  /// 弹幕增强插件 API
  Future<void> _handleDanmakuApi(
    HttpRequest request,
    String path,
    String method,
  ) async {
    final plugin = PluginManager().getPlugin<DanmakuEnhancePlugin>(
      'danmaku_enhance',
    );
    if (plugin == null) {
      _jsonResponse(request, {'error': 'Plugin not found'}, 404);
      return;
    }

    // /api/danmaku/config - 获取/更新配置
    if (path == '/api/danmaku/config') {
      if (method == 'GET') {
        final config = plugin.getConfig();
        _jsonResponse(request, {'enableFilter': config.enableFilter});
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        if (body != null) {
          if (body.containsKey('enableFilter')) {
            plugin.setEnableFilter(body['enableFilter'] as bool);
          }
          _jsonResponse(request, {'success': true});
        } else {
          _jsonResponse(request, {'error': 'Invalid body'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/danmaku/block/partial (部分匹配)
    else if (path == '/api/danmaku/block/partial' ||
        path == '/api/danmaku/block') {
      if (method == 'GET') {
        _jsonResponse(request, {'keywords': plugin.getConfig().blockKeywords});
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        final keyword = body?['keyword'] as String?;
        if (keyword != null && keyword.isNotEmpty) {
          plugin.addBlockKeyword(keyword);
          _jsonResponse(request, {'success': true, 'keyword': keyword});
        } else {
          _jsonResponse(request, {'error': 'Missing keyword'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/danmaku/block/partial/{keyword}
    else if (path.startsWith('/api/danmaku/block/partial/')) {
      final keyword = Uri.decodeComponent(
        path.substring('/api/danmaku/block/partial/'.length),
      );
      if (method == 'DELETE') {
        plugin.removeBlockKeyword(keyword);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // 兼容旧 API: /api/danmaku/block/{keyword}
    else if (path.startsWith('/api/danmaku/block/') &&
        !path.contains('/full')) {
      final keyword = Uri.decodeComponent(
        path.substring('/api/danmaku/block/'.length),
      );
      if (method == 'DELETE') {
        plugin.removeBlockKeyword(keyword);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/danmaku/block/full (全词匹配)
    else if (path == '/api/danmaku/block/full') {
      if (method == 'GET') {
        _jsonResponse(request, {'keywords': plugin.getFullKeywords()});
      } else if (method == 'POST') {
        final body = await _readJsonBody(request);
        final keyword = body?['keyword'] as String?;
        if (keyword != null && keyword.isNotEmpty) {
          plugin.addFullKeyword(keyword);
          _jsonResponse(request, {'success': true, 'keyword': keyword});
        } else {
          _jsonResponse(request, {'error': 'Missing keyword'}, 400);
        }
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/danmaku/block/full/{keyword}
    else if (path.startsWith('/api/danmaku/block/full/')) {
      final keyword = Uri.decodeComponent(
        path.substring('/api/danmaku/block/full/'.length),
      );
      if (method == 'DELETE') {
        plugin.removeFullKeyword(keyword);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    }
    // /api/danmaku/block/{keyword}
    else if (path.startsWith('/api/danmaku/block/')) {
      final keyword = Uri.decodeComponent(
        path.substring('/api/danmaku/block/'.length),
      );
      if (method == 'DELETE') {
        plugin.removeBlockKeyword(keyword);
        _jsonResponse(request, {'success': true});
      } else {
        _jsonResponse(request, {'error': 'Method not allowed'}, 405);
      }
    } else {
      _jsonResponse(request, {'error': 'Not found'}, 404);
    }
  }

  /// 读取 JSON 请求体
  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
    try {
      final content = await utf8.decoder.bind(request).join();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 发送 JSON 响应
  void _jsonResponse(
    HttpRequest request,
    Map<String, dynamic> data, [
    int statusCode = 200,
  ]) {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
  }

  /// 提供儿童模式配置页
  Future<void> _serveKidsWebUI(HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_kidsWebUIHtml);
  }

  /// 儿童模式配置页 HTML（手机/电脑浏览器打开，勾选主题、添加自定义主题）
  ///
  /// 用 raw string，避免 HTML/JS 里的 \$ 被 Dart 当成插值。
  static const String _kidsWebUIHtml = r'''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>BiliTV 儿童模式</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Microsoft YaHei', sans-serif;
    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
    color: #fff; min-height: 100vh; padding: 16px;
  }
  .container { max-width: 720px; margin: 0 auto; padding-bottom: 40px; }
  h1 { text-align: center; color: #fb7299; font-size: 24px; margin: 12px 0 6px; }
  .sub { text-align: center; color: rgba(255,255,255,0.45); font-size: 13px; margin-bottom: 20px; }
  .card {
    background: rgba(255,255,255,0.05); border-radius: 16px; padding: 18px;
    margin-bottom: 16px; border: 1px solid rgba(255,255,255,0.1);
  }
  .card h2 { color: #fb7299; font-size: 17px; margin-bottom: 14px; }
  .row {
    display: flex; align-items: center; gap: 12px;
    padding: 12px 4px; font-size: 15px; cursor: pointer;
  }
  .row input[type="checkbox"] { width: 22px; height: 22px; accent-color: #fb7299; flex: none; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 8px; }
  .chip {
    display: flex; flex-direction: column; gap: 2px;
    padding: 10px 12px; border-radius: 10px;
    background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.08);
    cursor: pointer; font-size: 14px;
  }
  .chip.on { background: rgba(251,114,153,0.22); border-color: #fb7299; }
  .chip small { color: rgba(255,255,255,0.35); font-size: 11px; word-break: break-all; }
  .chip .top { display: flex; align-items: center; gap: 8px; }
  .chip input { width: 18px; height: 18px; accent-color: #fb7299; flex: none; }
  input[type="text"] {
    width: 100%; padding: 12px 14px; border-radius: 10px; font-size: 16px;
    border: 1px solid rgba(255,255,255,0.2); background: rgba(255,255,255,0.1);
    color: #fff; outline: none;
  }
  input[type="text"]:focus { border-color: #fb7299; }
  input[type="text"]::placeholder { color: rgba(255,255,255,0.35); }
  .input-row { display: flex; gap: 10px; margin-bottom: 10px; }
  button {
    padding: 12px 20px; border: none; border-radius: 10px; background: #fb7299;
    color: #fff; font-size: 15px; cursor: pointer; white-space: nowrap;
  }
  button:active { transform: scale(0.98); }
  button.ghost { background: rgba(255,255,255,0.12); }
  button.danger { background: rgba(255,80,80,0.85); }
  .tags { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 14px; }
  .tag {
    display: inline-flex; align-items: center; gap: 8px;
    padding: 8px 10px 8px 14px; border-radius: 20px; font-size: 14px;
    background: rgba(251,114,153,0.2);
  }
  .tag button {
    padding: 0; width: 20px; height: 20px; border-radius: 50%;
    background: rgba(255,255,255,0.2); font-size: 14px; line-height: 1;
  }
  .hint { color: rgba(255,255,255,0.4); font-size: 12px; line-height: 1.6; margin-top: 6px; }
  #toast {
    position: fixed; left: 50%; bottom: 30px; transform: translateX(-50%);
    background: rgba(0,0,0,0.85); padding: 12px 22px; border-radius: 24px;
    font-size: 14px; opacity: 0; transition: opacity 0.25s; pointer-events: none;
  }
  #toast.show { opacity: 1; }
</style>
</head>
<body>
<div class="container">
  <h1>🧒 儿童模式</h1>
  <div class="sub">改完立即生效，电视上无需任何操作</div>

  <div class="card">
    <h2>开关</h2>
    <label class="row"><input type="checkbox" id="enabled"> 儿童模式（关闭后恢复推荐流首页）</label>
    <label class="row"><input type="checkbox" id="autoLearn"> 自动信任通过的 UP 主</label>
  </div>

  <div class="card">
    <h2>内置主题</h2>
    <div class="grid" id="presets"></div>
  </div>

  <div class="card">
    <h2>自定义主题</h2>
    <div class="tags" id="customList"></div>
    <div class="input-row">
      <input type="text" id="newLabel" placeholder="主题名，例如：熊出没">
      <button id="btnAdd">添加</button>
    </div>
    <div class="input-row">
      <input type="text" id="newExtra" placeholder="（可选）额外搜索词，逗号分隔">
    </div>
    <p class="hint">
      主题名会同时作为搜索词和标题匹配词：搜索结果标题里出现这个词才会显示。<br>
      想覆盖得更全，可以填额外搜索词，例如「熊出没, 熊出没之探险日记」。
    </p>
  </div>

  <div class="card">
    <h2>信任的 UP 主</h2>
    <p class="hint" id="trustedInfo">加载中…</p>
    <div style="margin-top:12px"><button class="danger" id="btnClearTrusted">清空信任名单</button></div>
  </div>
</div>
<div id="toast"></div>

<script>
var state = { presets: [], custom: [] };

function $(id) { return document.getElementById(id); }

function esc(s) {
  return String(s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}

var toastTimer = null;
function toast(msg) {
  var el = $('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(function () { el.classList.remove('show'); }, 1800);
}

function post(body) {
  return fetch('/api/kids/config', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
}

function load() {
  return fetch('/api/kids/config').then(function (r) { return r.json(); }).then(function (cfg) {
    state.presets = cfg.presets || [];
    state.custom = cfg.custom || [];

    $('enabled').checked = !!cfg.enabled;
    $('autoLearn').checked = !!cfg.autoLearnUps;
    $('trustedInfo').textContent = '当前已信任 ' + (cfg.trustedUpCount || 0) + ' 位 UP 主，' +
      '他们的投稿会被视为安全内容。';

    var box = $('presets');
    box.innerHTML = state.presets.map(function (p) {
      return '<label class="chip' + (p.enabled ? ' on' : '') + '">' +
        '<span class="top"><input type="checkbox" class="preset" value="' + esc(p.id) + '"' +
        (p.enabled ? ' checked' : '') + '><span>' + esc(p.label) + '</span></span>' +
        '<small>' + esc((p.queries || []).join(' / ')) + '</small></label>';
    }).join('');

    Array.prototype.forEach.call(box.querySelectorAll('input.preset'), function (cb) {
      cb.addEventListener('change', function () {
        cb.closest('.chip').classList.toggle('on', cb.checked);
        saveTopics();
      });
    });

    renderCustom();
  }).catch(function () {
    toast('读取失败，请确认电视上的 App 正在运行');
  });
}

function renderCustom() {
  var box = $('customList');
  if (state.custom.length === 0) {
    box.innerHTML = '<span class="hint">还没有自定义主题</span>';
    return;
  }
  box.innerHTML = state.custom.map(function (t) {
    return '<span class="tag">' + esc(t.label) +
      '<button class="x" data-id="' + esc(t.id) + '">×</button></span>';
  }).join('');
  Array.prototype.forEach.call(box.querySelectorAll('button.x'), function (b) {
    b.addEventListener('click', function () { removeTopic(b.getAttribute('data-id')); });
  });
}

function saveTopics() {
  var ids = Array.prototype.map.call(
    document.querySelectorAll('input.preset:checked'),
    function (e) { return e.value; }
  );
  return post({
    enabled: $('enabled').checked,
    autoLearnUps: $('autoLearn').checked,
    presetEnabledIds: ids
  }).then(function (r) {
    toast(r.ok ? '已保存 ✓' : '保存失败');
  });
}

function addTopic() {
  var label = $('newLabel').value.trim();
  if (!label) { toast('请先填写主题名'); return; }
  var extra = $('newExtra').value.split(/[,，、\s]+/).filter(Boolean);
  var words = [label].concat(extra);
  post({ addCustom: { label: label, queries: words, matchKeywords: words } })
    .then(function (r) {
      if (r.ok) {
        $('newLabel').value = '';
        $('newExtra').value = '';
        toast('已添加 ✓');
        return load();
      }
      return r.json().then(function (e) { toast(e.error || '添加失败'); });
    });
}

function removeTopic(id) {
  post({ removeCustomId: id }).then(function () {
    toast('已删除');
    load();
  });
}

function clearTrusted() {
  post({ clearTrustedUps: true }).then(function () {
    toast('已清空');
    load();
  });
}

$('enabled').addEventListener('change', saveTopics);
$('autoLearn').addEventListener('change', saveTopics);
$('btnAdd').addEventListener('click', addTopic);
$('btnClearTrusted').addEventListener('click', clearTrusted);
$('newLabel').addEventListener('keydown', function (e) { if (e.key === 'Enter') addTopic(); });
$('newExtra').addEventListener('keydown', function (e) { if (e.key === 'Enter') addTopic(); });

load();
</script>
</body>
</html>
''';

  /// 提供 Web 管理界面
  Future<void> _serveWebUI(HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_webUIHtml);
  }

  /// Web 管理界面 HTML
  static const String _webUIHtml = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>BiliTV 插件管理</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { 
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: #fff; 
      min-height: 100vh;
      padding: 20px;
    }
    .container { max-width: 800px; margin: 0 auto; }
    h1 { 
      text-align: center; 
      margin-bottom: 30px;
      color: #fb7299;
      font-size: 28px;
    }
    .card {
      background: rgba(255,255,255,0.05);
      border-radius: 16px;
      padding: 24px;
      margin-bottom: 20px;
      backdrop-filter: blur(10px);
      border: 1px solid rgba(255,255,255,0.1);
    }
    .card h2 {
      color: #fb7299;
      margin-bottom: 16px;
      font-size: 20px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .card h3 {
      color: #fff;
      margin: 16px 0 8px;
      font-size: 16px;
    }
    .input-row {
      display: flex;
      gap: 10px;
      margin-bottom: 16px;
    }
    input[type="text"] {
      flex: 1;
      padding: 12px 16px;
      border: 1px solid rgba(255,255,255,0.2);
      border-radius: 8px;
      background: rgba(255,255,255,0.1);
      color: #fff;
      font-size: 16px;
      outline: none;
      transition: border-color 0.2s;
    }
    input[type="text"]:focus {
      border-color: #fb7299;
    }
    input[type="text"]::placeholder {
      color: rgba(255,255,255,0.4);
    }
    button {
      padding: 12px 24px;
      border: none;
      border-radius: 8px;
      background: #fb7299;
      color: #fff;
      font-size: 16px;
      cursor: pointer;
      transition: transform 0.1s, background 0.2s;
    }
    button:hover { background: #e5638a; }
    button:active { transform: scale(0.98); }
    .tags {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      min-height: 32px;
    }
    .tag {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 8px 12px;
      background: rgba(251,114,153,0.2);
      border-radius: 20px;
      font-size: 14px;
    }
    .tag.highlight {
      background: rgba(255,215,0,0.2);
    }
    .tag.blocked {
      background: rgba(255,0,0,0.2);
    }
    .tag .delete {
      cursor: pointer;
      opacity: 0.6;
      font-size: 16px;
    }
    .tag .delete:hover { opacity: 1; }
    .empty {
      color: rgba(255,255,255,0.4);
      font-style: italic;
    }
    .switch-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 0;
      border-bottom: 1px solid rgba(255,255,255,0.1);
    }
    .switch-row:last-child { border-bottom: none; }
    .switch-label {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .switch-label span:first-child {
      font-size: 16px;
    }
    .switch-label span:last-child {
      font-size: 12px;
      color: rgba(255,255,255,0.5);
    }
    .switch {
      position: relative;
      width: 50px;
      height: 28px;
      background: rgba(255,255,255,0.2);
      border-radius: 14px;
      cursor: pointer;
      transition: background 0.2s;
    }
    .switch.on {
      background: #fb7299;
    }
    .switch::after {
      content: '';
      position: absolute;
      top: 2px;
      left: 2px;
      width: 24px;
      height: 24px;
      background: #fff;
      border-radius: 50%;
      transition: left 0.2s;
    }
    .switch.on::after {
      left: 24px;
    }
    .tabs {
      display: flex;
      margin-bottom: 16px;
      gap: 8px;
    }
    .tab {
      padding: 8px 16px;
      background: rgba(255,255,255,0.1);
      border-radius: 8px;
      cursor: pointer;
      transition: background 0.2s;
    }
    .tab.active {
      background: #fb7299;
    }
    .tab:hover:not(.active) {
      background: rgba(255,255,255,0.2);
    }
    .section { display: none; }
    .section.active { display: block; }
    .divider {
      height: 1px;
      background: rgba(255,255,255,0.1);
      margin: 16px 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>📺 BiliTV 插件管理</h1>
    
    <!-- 去广告插件 -->
    <div class="card">
      <h2>🚫 去广告增强</h2>
      
      <!-- 过滤开关 -->
      <div class="switch-row">
        <div class="switch-label">
          <span>过滤广告推广</span>
          <span>隐藏商业合作、恰饭、推广等内容</span>
        </div>
        <div class="switch" id="filterSponsored" onclick="toggleAdConfig('filterSponsored')"></div>
      </div>
      <div class="switch-row">
        <div class="switch-label">
          <span>过滤标题党</span>
          <span>隐藏震惊体、夸张标题视频</span>
        </div>
        <div class="switch" id="filterClickbait" onclick="toggleAdConfig('filterClickbait')"></div>
      </div>
      <div class="switch-row">
        <div class="switch-label">
          <span>过滤低播放量</span>
          <span>隐藏播放量低于1000的视频</span>
        </div>
        <div class="switch" id="filterLowQuality" onclick="toggleAdConfig('filterLowQuality')"></div>
      </div>
      
      <div class="divider"></div>
      
      <!-- UP主拉黑 -->
      <h3>👤 UP主拉黑</h3>
      <div class="input-row">
        <input type="text" id="upNameInput" placeholder="输入UP主名称">
        <button onclick="addUpName()">添加</button>
      </div>
      <div class="tags" id="upNames"></div>
      
      <div class="divider"></div>
      
      <!-- 自定义关键词 -->
      <h3>🔤 自定义屏蔽关键词</h3>
      <p style="font-size:12px;color:rgba(255,255,255,0.5);margin-bottom:12px;">标题中包含这些关键词的视频将被屏蔽</p>
      <div class="input-row">
        <input type="text" id="adKeywordInput" placeholder="输入要屏蔽的标题关键词">
        <button onclick="addAdKeyword()">添加</button>
      </div>
      <div class="tags" id="adKeywords"></div>
    </div>

    <!-- 弹幕屏蔽插件 -->
    <div class="card">
      <h2>💬 弹幕屏蔽</h2>
      
      <!-- 开关 -->
      <div class="switch-row">
        <div class="switch-label">
          <span>启用弹幕屏蔽</span>
          <span>屏蔽包含指定关键词的弹幕</span>
        </div>
        <div class="switch" id="enableFilter" onclick="toggleDanmakuConfig('enableFilter')"></div>
      </div>
      
      <div class="divider"></div>
      
      <!-- 部分匹配关键词 -->
      <h3>📝 部分匹配关键词</h3>
      <p style="font-size:12px;color:rgba(255,255,255,0.5);margin-bottom:12px;">包含即屏蔽（如 "第一" 会屏蔽 "我是第一名"）</p>
      <div class="input-row">
        <input type="text" id="partialKeywordInput" placeholder="输入部分匹配关键词">
        <button onclick="addDanmakuKeyword('partial')">添加</button>
      </div>
      <div class="tags" id="partialKeywords"></div>

      <div class="divider" style="margin: 20px 0;"></div>

      <!-- 全词匹配关键词 -->
      <h3>🔤 全词匹配关键词</h3>
      <p style="font-size:12px;color:rgba(255,255,255,0.5);margin-bottom:12px;">必须完全一致才屏蔽（如 "第一" 只屏蔽 "第一"）</p>
      <div class="input-row">
        <input type="text" id="fullKeywordInput" placeholder="输入全词匹配关键词">
        <button onclick="addDanmakuKeyword('full')">添加</button>
      </div>
      <div class="tags" id="fullKeywords"></div>
    </div>
  </div>

  <script>
    let adConfig = {};
    let danmakuConfig = {};

    async function loadData() {
      // 加载去广告配置
      try {
        const configRes = await fetch('/api/ad-filter/config');
        adConfig = await configRes.json();
        updateSwitch('filterSponsored', adConfig.filterSponsored);
        updateSwitch('filterClickbait', adConfig.filterClickbait);
        updateSwitch('filterLowQuality', adConfig.filterLowQuality);
      } catch (e) { console.error(e); }

      // 加载UP主名称
      try {
        const upRes = await fetch('/api/ad-filter/upnames');
        const upData = await upRes.json();
        renderTags('upNames', upData.upnames || [], deleteUpName, false, true);
      } catch (e) { console.error(e); }

      // 加载自定义关键词
      try {
        const adRes = await fetch('/api/ad-filter/keywords');
        const adData = await adRes.json();
        renderTags('adKeywords', adData.keywords || [], deleteAdKeyword);
      } catch (e) { console.error(e); }

      // 加载弹幕配置
      try {
        const dmConfigRes = await fetch('/api/danmaku/config');
        danmakuConfig = await dmConfigRes.json();
        updateSwitch('enableFilter', danmakuConfig.enableFilter);
      } catch (e) { console.error(e); }

      // 加载部分匹配关键词
      loadDanmakuKeywords('partial');
      // 加载全词匹配关键词
      loadDanmakuKeywords('full');
    }

    async function loadDanmakuKeywords(type) {
      try {
        // partial 也可以用 /api/danmaku/block (兼容)
        const path = type === 'partial' ? '/api/danmaku/block' : '/api/danmaku/block/' + type;
        const res = await fetch(path);
        const data = await res.json();
        renderTags(type + 'Keywords', data.keywords || [], (k) => deleteDanmakuKeyword(type, k));
      } catch (e) { console.error(e); }
    }

    function updateSwitch(id, value) {
      const el = document.getElementById(id);
      if (el) {
        el.classList.toggle('on', value);
      }
    }

    async function toggleAdConfig(key) {
      adConfig[key] = !adConfig[key];
      updateSwitch(key, adConfig[key]);
      await fetch('/api/ad-filter/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [key]: adConfig[key] })
      });
    }

    async function toggleDanmakuConfig(key) {
      danmakuConfig[key] = !danmakuConfig[key];
      updateSwitch(key, danmakuConfig[key]);
      await fetch('/api/danmaku/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [key]: danmakuConfig[key] })
      });
    }

    function renderTags(containerId, keywords, deleteFunc, isHighlight, isBlocked) {
      const container = document.getElementById(containerId);
      if (!container) return;
      if (keywords.length === 0) {
        container.innerHTML = '<span class="empty">暂无</span>';
        return;
      }
      container.innerHTML = '';
      keywords.forEach(k => {
        const tag = document.createElement('span');
        tag.className = 'tag' + (isHighlight ? ' highlight' : '') + (isBlocked ? ' blocked' : '');
        tag.innerHTML = k + ' <span class="delete">×</span>';
        tag.querySelector('.delete').onclick = (e) => {
          e.stopPropagation();
          deleteFunc(k);
        };
        container.appendChild(tag);
      });
    }

    async function addUpName() {
      const input = document.getElementById('upNameInput');
      const name = input.value.trim();
      if (!name) return;
      await fetch('/api/ad-filter/upnames', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name })
      });
      input.value = '';
      loadData();
    }

    async function deleteUpName(name) {
      await fetch('/api/ad-filter/upnames/' + encodeURIComponent(name), { method: 'DELETE' });
      loadData();
    }

    async function addAdKeyword() {
      const input = document.getElementById('adKeywordInput');
      const keyword = input.value.trim();
      if (!keyword) return;
      await fetch('/api/ad-filter/keywords', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ keyword })
      });
      input.value = '';
      loadData();
    }

    async function deleteAdKeyword(keyword) {
      await fetch('/api/ad-filter/keywords/' + encodeURIComponent(keyword), { method: 'DELETE' });
      loadData();
    }

    async function addDanmakuKeyword(type) {
      const input = document.getElementById(type + 'KeywordInput');
      const keyword = input.value.trim();
      if (!keyword) return;
      
      const path = type === 'partial' ? '/api/danmaku/block' : '/api/danmaku/block/' + type;
      
      await fetch(path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ keyword })
      });
      input.value = '';
      loadDanmakuKeywords(type); // 只刷新对应列表
    }

    async function deleteDanmakuKeyword(type, keyword) {
      const path = type === 'partial' 
        ? '/api/danmaku/block/' + encodeURIComponent(keyword)
        : '/api/danmaku/block/' + type + '/' + encodeURIComponent(keyword);
        
      await fetch(path, { method: 'DELETE' });
      loadDanmakuKeywords(type); // 只刷新对应列表
    }

    // 回车键提交
    document.getElementById('upNameInput').addEventListener('keypress', e => {
      if (e.key === 'Enter') addUpName();
    });
    document.getElementById('adKeywordInput').addEventListener('keypress', e => {
      if (e.key === 'Enter') addAdKeyword();
    });
    document.getElementById('partialKeywordInput').addEventListener('keypress', e => {
      if (e.key === 'Enter') addDanmakuKeyword('partial');
    });
    document.getElementById('fullKeywordInput').addEventListener('keypress', e => {
      if (e.key === 'Enter') addDanmakuKeyword('full');
    });

    loadData();
  </script>
</body>
</html>
''';
}
