import 'package:dio/dio.dart';

import '../models/app_open_ad.dart';
import '../utils/image_upload.dart';

/// REST access to the singleton app-open interstitial ad.
///
/// Unlike [PromoBannerRepository] there is no list to cache/stream — the
/// campaign is a single document — so this stays a plain fetch/save/delete
/// wrapper. Constructed with the **authenticated** Dio: the write endpoints
/// are admin-gated, and the public GET tolerates the bearer token fine.
class AppOpenAdRepository {
  final Dio _dio;
  AppOpenAdRepository(this._dio);

  /// The current campaign, or null when none exists (the endpoint returns a
  /// JSON `null` body rather than a 404).
  Future<AppOpenAd?> fetch({bool activeOnly = false}) async {
    final res = await _dio.get<dynamic>(
      '/api/app-open-ad',
      queryParameters: activeOnly ? {'active': '1'} : null,
    );
    final data = res.data;
    if (data is! Map) return null;
    return AppOpenAd.fromJson(Map<String, dynamic>.from(data));
  }

  /// Upserts the campaign. [imageBytes] is required by the backend on the
  /// very first save; afterwards it's optional (keep the current image).
  Future<AppOpenAd> save({
    required int durationInSeconds,
    required bool isActive,
    PreparedImage? image,
  }) async {
    final form = FormData.fromMap({
      'durationInSeconds': durationInSeconds.toString(),
      'isActive': isActive.toString(),
      if (image != null) 'image': image.toMultipart(),
    });
    final res =
        await _dio.put<Map<String, dynamic>>('/api/app-open-ad', data: form);
    return AppOpenAd.fromJson(res.data!);
  }

  Future<void> delete() async {
    await _dio.delete('/api/app-open-ad');
  }
}
