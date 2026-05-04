// Meal Service — API client for the Meal Feature.
// Mirrors the singleton/setToken pattern of TaskService.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../constants/api_constants.dart';
import '../../shared/models/meal_models.dart';
import 'task_service.dart';

class MealService {
  static final MealService _instance = MealService._internal();
  factory MealService() => _instance;
  MealService._internal();

  String? _token;
  final Dio _dio = Dio();

  // Inherited from PRD §11: 500KB per image, max 99 images.
  static const int _maxImageBytes = 500 * 1024;
  static const int _maxImagesPerMeal = 99;

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Map an HTTP failure to a user-friendly message.
  ///
  /// FastAPI returns `{"detail": "Not Found"}` for any unmatched route. If we
  /// surface that detail verbatim the user sees "Not Found", which sounds
  /// like the AI didn't recognise their food when it actually means the
  /// service is unreachable. This translator normalises common transport-
  /// level failures and only passes through *product-level* details when
  /// the backend has clearly customised them.
  ///
  /// [status] is the HTTP status (null when the request never reached the
  /// server — DNS, timeout, no internet, etc).
  /// [rawDetail] is the `detail` field of the backend's JSON body, if any.
  /// [action] is a short verb-phrase like "load meals" used in fallback copy.
  String _translateError({
    int? status,
    Object? rawDetail,
    required String action,
  }) {
    final detail = rawDetail is String ? rawDetail.trim() : '';

    // No response → network problem.
    if (status == null) {
      return "Couldn't reach the meal service. Check your connection and try again.";
    }

    // FastAPI defaults — these mean the route didn't match (deployment / proxy
    // / version mismatch), never something the user can act on. Translate.
    if (detail == 'Not Found' || detail == 'Method Not Allowed') {
      return 'Meal service is unavailable right now. Please try again in a moment.';
    }

    // The genuine "AI couldn't see any food" case — keep the product-level
    // message but use warmer copy than the raw detail.
    if (status == 422 && detail.toLowerCase().contains('food items')) {
      return "We couldn't spot any food in this photo. Try another shot?";
    }

    if (status == 401 || status == 403) {
      return detail.isNotEmpty ? detail : 'Please sign in again.';
    }

    if (status >= 500) {
      return 'Something went wrong on our side. Please try again.';
    }

    // 4xx with a custom detail string (e.g. "Meal not found", "team_id is
    // required when visibility='team'") — those are product-level messages
    // worth showing.
    if (detail.isNotEmpty) return detail;

    return "Couldn't $action. Please try again.";
  }

  Never _handleError(http.Response response, String action) {
    Object? detail;
    try {
      final body = json.decode(response.body);
      if (body is Map<String, dynamic>) {
        detail = body['detail'];
      }
    } catch (_) {
      // Non-JSON body — leave detail as null and use status only.
    }
    debugPrint(
      '[MealService] $action failed: status=${response.statusCode} '
      'detail=${detail ?? '(none)'} url=${response.request?.url}',
    );
    throw Exception(_translateError(
      status: response.statusCode,
      rawDetail: detail,
      action: action,
    ));
  }

  // ============ Image compression ============

  // Iterative JPEG compression: 85% → 25% quality. Same algorithm used by
  // tasks_list_screen for nutrition uploads, kept local so the screen layer
  // doesn't need to know about size limits.
  Future<File> _compressImageToLimit(File source) async {
    if (source.lengthSync() <= _maxImageBytes) return source;
    final tempDir = await getTemporaryDirectory();
    File? lastCompressed;
    for (final quality in const [85, 75, 65, 55, 45, 35, 25]) {
      final targetPath =
          '${tempDir.path}/meal_${DateTime.now().microsecondsSinceEpoch}_$quality.jpg';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        source.path,
        targetPath,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (compressed == null) continue;
      final file = File(compressed.path);
      if (!file.existsSync()) continue;
      lastCompressed = file;
      if (file.lengthSync() <= _maxImageBytes) return file;
    }
    if (lastCompressed != null &&
        lastCompressed.lengthSync() <= _maxImageBytes) {
      return lastCompressed;
    }
    throw Exception(
      'Image is still larger than 500KB after compression. Please choose another image.',
    );
  }

  // ============ Analyze (multipart) ============

  /// Upload meal photos and receive structured analysis. Backend persists images
  /// under uploads/meals/{meal_id}/ but does NOT yet create a meal document —
  /// call [createMeal] with the returned [mealId] to confirm.
  Future<MealAnalyzeResult> analyzeMealImages({
    required List<File> files,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    if (files.isEmpty) throw Exception('Please select at least one photo');
    if (files.length > _maxImagesPerMeal) {
      throw Exception('At most $_maxImagesPerMeal photos per meal');
    }

    debugPrint('[MealAnalyze] ── start ──────────────────────');
    debugPrint('[MealAnalyze] auth_token_present=${_token != null} '
        'file_count=${files.length}');

    // ── STEP 1: compress each photo to ≤500KB ─────────────────────────
    debugPrint('[MealAnalyze] STEP 1: compressing ${files.length} file(s)…');
    final compressed = <File>[];
    try {
      for (final f in files) {
        final beforeBytes = f.lengthSync();
        final c = await _compressImageToLimit(f);
        final afterBytes = c.lengthSync();
        debugPrint(
          '[MealAnalyze]   compressed "${f.path.split('/').last}": '
          '$beforeBytes → $afterBytes bytes (path=${c.path})',
        );
        compressed.add(c);
      }
    } catch (e) {
      debugPrint('[MealAnalyze] STEP 1 FAILED: $e');
      rethrow;
    }
    debugPrint('[MealAnalyze] STEP 1 OK: ${compressed.length} file(s) ready');

    // ── STEP 2 (per PRD): vision step calls /tasks/nutrition/analyze-images ──
    debugPrint(
      '[MealAnalyze] STEP 2: POST ${ApiConstants.baseUrl}/tasks/nutrition/analyze-images',
    );
    final String summaryText;
    try {
      summaryText = await TaskService().analyzeNutritionImages(
        files: compressed,
      );
    } catch (e) {
      debugPrint('[MealAnalyze] STEP 2 FAILED at vision: $e');
      rethrow;
    }
    debugPrint(
      '[MealAnalyze] STEP 2 OK: summary length=${summaryText.length} '
      'snippet="${_snippet(summaryText, 120)}"',
    );

    // ── STEP 3: validate the vision result is non-empty ───────────────
    if (summaryText.trim().isEmpty) {
      debugPrint(
        '[MealAnalyze] STEP 3 FAILED: nutrition endpoint returned empty summary',
      );
      throw Exception(
        'The nutrition service returned an empty result. Please try again.',
      );
    }
    debugPrint('[MealAnalyze] STEP 3 OK: non-empty summary forwarded');

    // ── STEP 4: build multipart for /meals/analyze ───────────────────
    final structureMultipart = <MultipartFile>[];
    for (final file in compressed) {
      final filename = file.path.split('/').last;
      structureMultipart.add(
        await MultipartFile.fromFile(file.path, filename: filename),
      );
    }
    debugPrint(
      '[MealAnalyze] STEP 4: POST ${ApiConstants.baseUrl}/meals/analyze '
      'files=${structureMultipart.length} summary_text_len=${summaryText.length}',
    );

    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/meals/analyze',
        data: FormData.fromMap({
          'files': structureMultipart,
          'summary_text': summaryText,
        }),
        options: Options(headers: {'Authorization': 'Bearer $_token'}),
      );
      debugPrint(
        '[MealAnalyze] STEP 5: response status=${response.statusCode} '
        'body_type=${response.data.runtimeType}',
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        debugPrint(
          '[MealAnalyze] STEP 5 FAILED: response not a JSON object: '
          'value=${_snippet(data.toString(), 200)}',
        );
        throw Exception(
          "We couldn't read the analysis response. Please try again.",
        );
      }

      debugPrint(
        '[MealAnalyze] STEP 6: parsing response with keys=${data.keys.toList()}',
      );
      final result = MealAnalyzeResult.fromJson(data);
      debugPrint(
        '[MealAnalyze] STEP 6 OK: meal_id=${result.mealId} '
        'images=${result.images.length} food_items=${result.foodItems.length} '
        'meal_name="${result.mealName}" '
        'nutrition_level=${result.nutritionLevel} '
        'advisor_insight_len=${result.advisorInsight?.length ?? 0}',
      );
      debugPrint('[MealAnalyze] ── end (success) ───────────────');
      return result;
    } on DioException catch (e) {
      final body = e.response?.data;
      final detail = body is Map<String, dynamic> ? body['detail'] : null;
      debugPrint(
        '[MealAnalyze] STEP 5 FAILED: status=${e.response?.statusCode} '
        'type=${e.type} detail=${detail ?? '(none)'} '
        'url=${e.requestOptions.uri} '
        'body=${_snippet(body?.toString() ?? '', 300)}',
      );
      throw Exception(_translateError(
        status: e.response?.statusCode,
        rawDetail: detail,
        action: 'finalize meal analysis',
      ));
    }
  }

  /// Truncate a string for log readability without breaking on a non-string.
  static String _snippet(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  // ============ CRUD ============

  /// Confirm a previously-analyzed meal. The [mealId] must come from a prior
  /// [analyzeMealImages] call so the backend can locate the saved images.
  ///
  /// V2 fields (mealName / mealType / mealTime / nutritionLevel / advisorInsight)
  /// are pass-through from the analyze result. Server derives sensible defaults
  /// when omitted, so callers can pass only the bits they care about.
  Future<Meal> createMeal({
    required String mealId,
    required List<FoodItem> foodItems,
    required MacroRatio macroRatio,
    String? note,
    MealVisibility visibility = MealVisibility.private,
    String? teamId,
    String? mealName,
    MealType? mealType,
    DateTime? mealTime,
    NutritionLevel? nutritionLevel,
    String? advisorInsight,
    MacroLevel? processingLevel,
    MacroLevel? addedSugar,
    String? timezone,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{
      'meal_id': mealId,
      'food_items': foodItems.map((f) => f.toJson()).toList(),
      'macro_ratio': macroRatio.toJson(),
      'visibility': visibility.apiValue,
      if (note != null) 'note': note,
      if (teamId != null) 'team_id': teamId,
      if (mealName != null) 'meal_name': mealName,
      if (mealType != null) 'meal_type': mealType.apiValue,
      if (mealTime != null) 'meal_time': mealTime.toUtc().toIso8601String(),
      if (nutritionLevel != null) 'nutrition_level': nutritionLevel.apiValue,
      if (advisorInsight != null) 'advisor_insight': advisorInsight,
      if (processingLevel != null) 'processing_level': processingLevel.apiValue,
      if (addedSugar != null) 'added_sugar': addedSugar.apiValue,
      if (timezone != null) 'timezone': timezone,
    };

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/meals'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 201) {
      return Meal.fromJson(json.decode(response.body));
    }
    _handleError(response, 'create meal');
  }

  /// Re-run structuring against a user-edited food list (with portion
  /// weights) without re-running vision. Used by the Log screen Re-analyze
  /// button before the meal is confirmed. Returns the same shape as
  /// `analyzeMealImages` minus the persisted-image metadata; the caller
  /// re-uses the existing draft's meal_id and images.
  Future<MealAnalyzeResult> restructureFoodList({
    required String draftMealId,
    required List<MealAttachment> draftImages,
    required List<FoodItem> foodItems,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    final body = {
      'food_items': foodItems.map((f) => f.toJson()).toList(),
    };
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/meals/restructure'),
      headers: _headers,
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      final raw = json.decode(response.body) as Map<String, dynamic>;
      // The backend returns analysis-only fields; merge in the existing
      // draft's meal_id and images so the on-screen draft stays consistent.
      raw['meal_id'] = draftMealId;
      raw['images'] = draftImages
          .map((a) => {
                'attachment_id': a.attachmentId,
                'filename': a.filename,
                'content_type': a.contentType,
                'size_bytes': a.sizeBytes,
                'path': a.path,
                'url': a.url,
                'thumbnail_path': a.thumbnailPath,
                'thumbnail_url': a.thumbnailUrl,
                'uploaded_at': a.uploadedAt,
              })
          .toList();
      return MealAnalyzeResult.fromJson(raw);
    }
    _handleError(response, 're-analyze meal');
  }

  Future<Meal> getMeal(String mealId) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/meals/$mealId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return Meal.fromJson(json.decode(response.body));
    }
    _handleError(response, 'load meal');
  }

  /// Edit a meal. Pass [sendTeamId]=true to send `team_id` even when null
  /// (e.g. detaching from a team while staying visibility=team is unusual but
  /// possible; see backend MealUpdate.model_fields_set semantics).
  Future<Meal> updateMeal({
    required String mealId,
    List<FoodItem>? foodItems,
    MacroRatio? macroRatio,
    String? note,
    MealVisibility? visibility,
    bool sendTeamId = false,
    String? teamId,
    String? mealName,
    MealType? mealType,
    DateTime? mealTime,
    NutritionLevel? nutritionLevel,
    String? advisorInsight,
    MacroLevel? processingLevel,
    MacroLevel? addedSugar,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    final body = <String, dynamic>{};
    if (foodItems != null) {
      body['food_items'] = foodItems.map((f) => f.toJson()).toList();
    }
    if (macroRatio != null) body['macro_ratio'] = macroRatio.toJson();
    if (note != null) body['note'] = note;
    if (visibility != null) body['visibility'] = visibility.apiValue;
    if (sendTeamId) body['team_id'] = teamId;
    if (mealName != null) body['meal_name'] = mealName;
    if (mealType != null) body['meal_type'] = mealType.apiValue;
    if (mealTime != null) body['meal_time'] = mealTime.toUtc().toIso8601String();
    if (nutritionLevel != null) body['nutrition_level'] = nutritionLevel.apiValue;
    if (advisorInsight != null) body['advisor_insight'] = advisorInsight;
    if (processingLevel != null) body['processing_level'] = processingLevel.apiValue;
    if (addedSugar != null) body['added_sugar'] = addedSugar.apiValue;

    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}/meals/$mealId'),
      headers: _headers,
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return Meal.fromJson(json.decode(response.body));
    }
    _handleError(response, 'update meal');
  }

  /// Weekly nutrition trend for the home-screen chart.
  /// Returns one bucket per local-calendar day (oldest first; last entry is today).
  Future<MealTrendResponse> getTrend({int days = 7}) async {
    if (_token == null) throw Exception('Not authenticated');
    final qp = <String, String>{'days': days.toString()};
    final uri = Uri.parse('${ApiConstants.baseUrl}/meals/trend')
        .replace(queryParameters: qp);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      return MealTrendResponse.fromJson(json.decode(response.body));
    }
    _handleError(response, 'load meal trend');
  }

  Future<void> deleteMeal(String mealId) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/meals/$mealId'),
      headers: _headers,
    );
    if (response.statusCode == 200) return;
    _handleError(response, 'delete meal');
  }

  // ============ Listing ============

  /// Personal meal history, newest first. [before] is an ISO timestamp from
  /// the previous response's `nextCursor`.
  Future<MealListResponse> listMyMeals({int limit = 20, String? before}) async {
    if (_token == null) throw Exception('Not authenticated');
    final qp = <String, String>{'limit': limit.toString()};
    if (before != null) qp['before'] = before;
    final uri = Uri.parse('${ApiConstants.baseUrl}/meals/me')
        .replace(queryParameters: qp);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      return MealListResponse.fromJson(json.decode(response.body));
    }
    _handleError(response, 'load my meals');
  }

  /// Team-scoped meals feed (visibility=team meals where team_id matches).
  Future<MealListResponse> getTeamMealFeed({
    required String teamId,
    int limit = 20,
    String? before,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    final qp = <String, String>{
      'team_id': teamId,
      'limit': limit.toString(),
    };
    if (before != null) qp['before'] = before;
    final uri = Uri.parse('${ApiConstants.baseUrl}/meals/feed')
        .replace(queryParameters: qp);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      return MealListResponse.fromJson(json.decode(response.body));
    }
    _handleError(response, 'load team meal feed');
  }

  // ============ Corrections ============

  Future<MealCorrectionResponse> submitCorrection({
    required String mealId,
    required List<FoodItem> originalFoodItems,
    required List<FoodItem> correctedFoodItems,
    MacroRatio? originalMacroRatio,
    MacroRatio? correctedMacroRatio,
  }) async {
    if (_token == null) throw Exception('Not authenticated');
    final body = <String, dynamic>{
      'original_food_items':
          originalFoodItems.map((f) => f.toJson()).toList(),
      'corrected_food_items':
          correctedFoodItems.map((f) => f.toJson()).toList(),
      if (originalMacroRatio != null)
        'original_macro_ratio': originalMacroRatio.toJson(),
      if (correctedMacroRatio != null)
        'corrected_macro_ratio': correctedMacroRatio.toJson(),
    };
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/meals/$mealId/correction'),
      headers: _headers,
      body: json.encode(body),
    );
    if (response.statusCode == 201) {
      return MealCorrectionResponse.fromJson(json.decode(response.body));
    }
    _handleError(response, 'submit correction');
  }
}
