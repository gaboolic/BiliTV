import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';

/// Bilibili API 基础类 - 提供共享工具方法
class BaseApi {
  static const String apiBase = 'https://api.bilibili.com';
  static const String passportBase = 'https://passport.bilibili.com';

  // WBI keys 缓存
  static String? imgKey;
  static String? subKey;
  static DateTime? wbiKeysTime;
  static bool _wbiLoaded = false;

  // 匿名设备指纹 (buvid3/buvid4)
  // 哔哩哔哩的风控接口（搜索、播放地址等）即使不登录也会要求带上它，
  // 否则容易返回 -412。这里在本地生成/缓存一份，随请求 Cookie 一起发送。
  static String? buvid3;
  static String? buvid4;
  static bool _buvidLoaded = false;

  /// 获取通用请求头
  static Map<String, String> getHeaders({bool withCookie = false}) {
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
      'Referer': 'https://www.bilibili.com',
    };

    if (withCookie) {
      final cookies = <String>[];

      if (buvid3 != null && buvid3!.isNotEmpty) {
        cookies.add('buvid3=$buvid3');
      }
      if (buvid4 != null && buvid4!.isNotEmpty) {
        cookies.add('buvid4=$buvid4');
      }

      final sessdata = AuthService.sessdata;
      final biliJct = AuthService.biliJct;
      if (sessdata != null && sessdata.isNotEmpty) {
        cookies.add('SESSDATA=$sessdata');
        if (biliJct != null && biliJct.isNotEmpty) {
          cookies.add('bili_jct=$biliJct');
        }
      }

      if (cookies.isNotEmpty) {
        headers['Cookie'] = cookies.join('; ');
      }
    }

    return headers;
  }

  /// 加载本地缓存的 buvid
  static Future<void> _loadBuvidFromStorage() async {
    if (_buvidLoaded) return;
    _buvidLoaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      buvid3 = prefs.getString('buvid3');
      buvid4 = prefs.getString('buvid4');
    } catch (e) {
      // 忽略加载错误
    }
  }

  /// 确保存在 buvid3/buvid4（匿名可用，不依赖登录）
  static Future<void> ensureBuvid() async {
    await _loadBuvidFromStorage();
    if (buvid3 != null && buvid3!.isNotEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBase/x/frontend/finger/spi'),
        headers: getHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = json['data'] as Map<String, dynamic>?;
        if (data != null) {
          buvid3 = data['b_3'] as String?;
          buvid4 = data['b_4'] as String?;

          if (buvid3 != null && buvid3!.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            prefs.setString('buvid3', buvid3!);
            if (buvid4 != null) prefs.setString('buvid4', buvid4!);
          }
        }
      }
    } catch (e) {
      // 拿不到就算了，请求会退回无 Cookie 状态
    }
  }

  /// 从本地存储加载 WBI keys
  static Future<void> _loadWbiFromStorage() async {
    if (_wbiLoaded) return;
    _wbiLoaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      imgKey = prefs.getString('wbi_img_key');
      subKey = prefs.getString('wbi_sub_key');
      final timeMs = prefs.getInt('wbi_keys_time');
      if (timeMs != null) {
        wbiKeysTime = DateTime.fromMillisecondsSinceEpoch(timeMs);
      }
    } catch (e) {
      // 忽略加载错误
    }
  }

  /// 保存 WBI keys 到本地存储
  static Future<void> _saveWbiToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (imgKey != null) prefs.setString('wbi_img_key', imgKey!);
      if (subKey != null) prefs.setString('wbi_sub_key', subKey!);
      if (wbiKeysTime != null) {
        prefs.setInt('wbi_keys_time', wbiKeysTime!.millisecondsSinceEpoch);
      }
    } catch (e) {
      // 忽略保存错误
    }
  }

  /// 获取 WBI keys (从 nav 接口)
  /// 缓存2小时，失败时继续使用旧值
  static Future<void> ensureWbiKeys() async {
    // 首次启动时从本地加载
    await _loadWbiFromStorage();
    // 先保证有匿名设备指纹，否则搜索接口容易被风控拦截 (-412)
    await ensureBuvid();

    // 缓存2小时
    if (imgKey != null && subKey != null && wbiKeysTime != null) {
      if (DateTime.now().difference(wbiKeysTime!).inMinutes < 120) {
        return;
      }
    }

    try {
      final response = await http.get(
        Uri.parse('$apiBase/x/web-interface/nav'),
        headers: getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        // 注意：未登录时 nav 返回 code=-101，但 data.wbi_img 依然存在。
        // 这里不能判断 code == 0，否则匿名用户永远拿不到 WBI key，
        // 搜索/播放地址就会退化成未签名请求被风控拦截（返回空或 -412）。
        final data = json['data'] as Map<String, dynamic>?;
        if (data != null) {
          final wbiImg = data['wbi_img'];
          if (wbiImg != null) {
            final imgUrl = wbiImg['img_url'] as String? ?? '';
            final subUrl = wbiImg['sub_url'] as String? ?? '';

            imgKey = imgUrl.split('/').last.split('.').first;
            subKey = subUrl.split('/').last.split('.').first;
            wbiKeysTime = DateTime.now();

            // 保存到本地存储
            _saveWbiToStorage();
          }
        }
      }
    } catch (e) {
      // 刷新失败时继续使用旧值（如果有的话）
    }
  }

  /// 修复图片 URL
  static String fixPicUrl(String url) {
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  /// 转换为整数 (支持 "1.2万" 格式)
  static int toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) {
      final direct = int.tryParse(value);
      if (direct != null) return direct;

      if (value.endsWith('万')) {
        final num = double.tryParse(value.replaceAll('万', ''));
        if (num != null) return (num * 10000).round();
      }
      if (value.endsWith('亿')) {
        final num = double.tryParse(value.replaceAll('亿', ''));
        if (num != null) return (num * 100000000).round();
      }
    }
    return 0;
  }

  /// 解析时长 (支持 "1:23" 和 "1:23:45" 格式)
  static int parseDuration(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      final parts = value.split(':');
      if (parts.length == 2) {
        return (int.tryParse(parts[0]) ?? 0) * 60 +
            (int.tryParse(parts[1]) ?? 0);
      }
      if (parts.length == 3) {
        return (int.tryParse(parts[0]) ?? 0) * 3600 +
            (int.tryParse(parts[1]) ?? 0) * 60 +
            (int.tryParse(parts[2]) ?? 0);
      }
    }
    return 0;
  }
}
