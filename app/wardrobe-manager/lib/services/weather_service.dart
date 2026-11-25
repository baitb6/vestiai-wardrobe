import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 天气信息（Open-Meteo，免 key）
class WeatherInfo {
  final String city;
  final double temperature;
  final double tempMin;
  final double tempMax;
  final int weatherCode;
  final double windSpeed;
  final int humidity;
  final int precipProb; // 降水概率 %

  const WeatherInfo({
    required this.city,
    required this.temperature,
    required this.tempMin,
    required this.tempMax,
    required this.weatherCode,
    required this.windSpeed,
    required this.humidity,
    required this.precipProb,
  });

  String get conditionText => WmoWeather.describe(weatherCode);
  String get emoji => WmoWeather.emoji(weatherCode);

  /// 简要描述：「晴 18° ~ 26°」
  String get brief => '$conditionText ${tempMin.round()}° ~ ${tempMax.round()}°';

  /// 降温/降雨提醒
  List<String> get tips {
    final list = <String>[];
    if (tempMax - tempMin >= 8) list.add('昼夜温差 ${tempMax.round() - tempMin.round()}°C，建议叠穿方便穿脱');
    if (precipProb >= 50) list.add('降水概率 $precipProb%，记得带伞');
    if (windSpeed >= 25) list.add('风力较大（${windSpeed.round()} km/h），注意防风');
    if (temperature <= 5) list.add('低温寒冷，注意保暖层');
    if (temperature >= 32) list.add('高温炎热，选透气速干材质');
    return list;
  }
}

/// WMO weather code → 中文
class WmoWeather {
  static String describe(int code) {
    if (code == 0) return '晴';
    if (code <= 2) return '多云';
    if (code == 3) return '阴';
    if (code >= 45 && code <= 48) return '雾';
    if (code >= 51 && code <= 57) return '毛毛雨';
    if (code >= 61 && code <= 67) return '雨';
    if (code >= 71 && code <= 77) return '雪';
    if (code >= 80 && code <= 82) return '阵雨';
    if (code >= 85 && code <= 86) return '阵雪';
    if (code >= 95 && code <= 99) return '雷雨';
    return '未知';
  }

  static String emoji(int code) {
    if (code == 0) return '☀️';
    if (code <= 2) return '⛅';
    if (code == 3) return '☁️';
    if (code >= 45 && code <= 48) return '🌫️';
    if (code >= 51 && code <= 57) return '🌦️';
    if (code >= 61 && code <= 67) return '🌧️';
    if (code >= 71 && code <= 77) return '❄️';
    if (code >= 80 && code <= 82) return '🌦️';
    if (code >= 85 && code <= 86) return '🌨️';
    if (code >= 95) return '⛈️';
    return '🌡️';
  }
}

class WeatherService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  static const String _forecastUrl = 'https://api.open-meteo.com/v1/forecast';
  static const String _geocodingUrl = 'https://geocoding-api.open-meteo.com/v1/search';

  /// 网络城市定位：不申请系统定位权限，靠出口 IP 推断城市。
  /// 返回城市名交给 getByCity 走同一套地理编码 + 天气查询。
  Future<String?> locateCityByIp() async {
    try {
      final r = await _dio.get('https://ipapi.co/json/');
      final data = r.data;
      if (data is! Map) return null;
      final city = (data['city'] ?? data['region']) as String?;
      return city?.trim().isEmpty ?? true ? null : city!.trim();
    } catch (_) {
      return null;
    }
  }

  /// 按城市名取天气（先地理编码再查天气）。
  /// 失败抛出带中文原因的 Exception（超时 / 5xx / 数据异常分类）。
  Future<WeatherInfo> getByCity(String city) async {
    final geo = await _guard(() async {
      return await _dio.get(_geocodingUrl, queryParameters: {
        'name': city,
        'count': 1,
        'language': 'zh',
      });
    });
    final results = geo.data is Map ? geo.data['results'] : null;
    if (results is! List || results.isEmpty) {
      throw Exception('找不到城市「$city」');
    }
    final hit = results.first is Map ? results.first as Map : null;
    if (hit == null) {
      throw Exception('城市信息解析失败，稍后再试');
    }
    final resolvedName = (hit['name'] as String?) ?? city;
    final admin = hit['admin1'] as String?;
    final lat = (hit['latitude'] as num?)?.toDouble();
    final lon = (hit['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      throw Exception('城市坐标解析失败，换个写法试试（如「武汉」）');
    }
    return _fetch(
      city: admin != null && admin != resolvedName ? '$resolvedName·$admin' : resolvedName,
      lat: lat,
      lon: lon,
    );
  }

  Future<WeatherInfo> getByLocation(double lat, double lon) async {
    return _fetch(city: '当前位置', lat: lat, lon: lon);
  }

  Future<WeatherInfo> _fetch({
    required String city,
    required double lat,
    required double lon,
  }) async {
    final resp = await _guard(() => _dio.get(
      _forecastUrl,
      queryParameters: {
        'latitude': lat,
        'longitude': lon,
        'current': 'temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m',
        'daily': 'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
        'timezone': 'auto',
        'forecast_days': 1,
      },
    ));
    final data = resp.data;
    if (data is! Map || data['current'] is! Map || data['daily'] is! Map) {
      throw Exception('天气服务返回的数据格式异常，稍后再试');
    }
    final current = data['current'] as Map;
    final daily = data['daily'] as Map;
    try {
      return WeatherInfo(
        city: city,
        temperature: (current['temperature_2m'] as num).toDouble(),
        tempMin: ((daily['temperature_2m_min'] as List).first as num).toDouble(),
        tempMax: ((daily['temperature_2m_max'] as List).first as num).toDouble(),
        weatherCode: (current['weather_code'] as num).toInt(),
        windSpeed: (current['wind_speed_10m'] as num?)?.toDouble() ?? 0,
        humidity: (current['relative_humidity_2m'] as num?)?.toInt() ?? 0,
        precipProb: ((daily['precipitation_probability_max'] as List?)?.first as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      // 字段缺失 / 类型不对都算脏数据，不让上层拿到半空的 WeatherInfo
      debugPrint('天气数据字段缺失，按数据异常处理：$e');
      throw Exception('天气服务返回的数据不完整，稍后再试');
    }
  }

  /// Dio 异常 → 中文一句话；其它异常原样上抛
  Future<Response> _guard(Future<Response> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      throw Exception(_describeDio(e));
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('天气服务返回的数据格式异常：$e');
    }
  }

  String _describeDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接天气服务超时，请检查网络';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '天气服务响应超时，稍后再试';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code >= 500) return '天气服务异常（HTTP $code），稍后再试';
        return '天气服务返回 HTTP $code，稍后再试';
      case DioExceptionType.connectionError:
        return '网络不可达，请检查网络连接';
      case DioExceptionType.badCertificate:
        return '天气服务证书校验失败';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        return '网络错误：${e.message ?? e.type.name}';
    }
  }
}
