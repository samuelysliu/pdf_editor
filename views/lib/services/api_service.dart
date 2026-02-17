import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/user_model.dart';
import '../models/pdf_model.dart';
import '../models/brush_stroke_model.dart';
import '../models/transaction_model.dart';
import 'auth_service.dart';

/// API 回傳的統一結果
class ApiResult<T> {
  final bool success;
  final T? data;
  final String? message;
  final int statusCode;

  ApiResult({
    required this.success,
    this.data,
    this.message,
    required this.statusCode,
  });
}

/// 統一 API 服務層
/// 所有 HTTP 請求都經過這裡，自動帶上 Token
class ApiService {
  // ============================================================
  //  內部工具方法
  // ============================================================

  /// 通用 GET
  static Future<ApiResult<Map<String, dynamic>>> _get(
    String path, {
    Map<String, String>? queryParams,
    bool requireAuth = true,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path')
          .replace(queryParameters: queryParams);

      final headers = requireAuth
          ? await AuthService.getAuthHeaders()
          : {'Content-Type': 'application/json'};

      final response = await http.get(uri, headers: headers);
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      return ApiResult(
        success: response.statusCode == 200,
        data: body,
        message: body['message'] ?? body['detail'],
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: '網路錯誤：$e',
        statusCode: 0,
      );
    }
  }

  /// 通用 POST (JSON Body)
  static Future<ApiResult<Map<String, dynamic>>> _post(
    String path, {
    Map<String, dynamic>? body,
    bool requireAuth = true,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path');

      final headers = requireAuth
          ? await AuthService.getAuthHeaders()
          : {'Content-Type': 'application/json'};

      final response = await http.post(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;

      return ApiResult(
        success: response.statusCode == 200,
        data: responseBody,
        message: responseBody['message'] ?? responseBody['detail'],
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: '網路錯誤：$e',
        statusCode: 0,
      );
    }
  }

  /// 通用 DELETE
  static Future<ApiResult<Map<String, dynamic>>> _delete(
    String path, {
    bool requireAuth = true,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      final headers = requireAuth
          ? await AuthService.getAuthHeaders()
          : {'Content-Type': 'application/json'};

      final response = await http.delete(uri, headers: headers);
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      return ApiResult(
        success: response.statusCode == 200,
        data: body,
        message: body['message'] ?? body['detail'],
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: '網路錯誤：$e',
        statusCode: 0,
      );
    }
  }

  // ============================================================
  //  🔐 認證 API
  // ============================================================

  /// 用戶註冊
  /// POST /api/v1/users/register
  static Future<ApiResult<AuthResponse>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final result = await _post(
      ApiConfig.register,
      body: {
        'username': username,
        'email': email,
        'password': password,
      },
      requireAuth: false,
    );

    if (result.success && result.data != null) {
      final auth = AuthResponse.fromJson(result.data!);
      // 自動保存 Token
      await AuthService.saveAuth(
        token: auth.accessToken,
        userId: auth.userId,
        username: auth.username,
      );
      return ApiResult(
        success: true,
        data: auth,
        message: result.message,
        statusCode: result.statusCode,
      );
    }

    return ApiResult(
      success: false,
      message: result.message,
      statusCode: result.statusCode,
    );
  }

  /// 用戶登入
  /// POST /api/v1/users/login
  static Future<ApiResult<AuthResponse>> login({
    required String username,
    required String password,
  }) async {
    final result = await _post(
      ApiConfig.login,
      body: {
        'username': username,
        'password': password,
      },
      requireAuth: false,
    );

    if (result.success && result.data != null) {
      final auth = AuthResponse.fromJson(result.data!);
      // 自動保存 Token
      await AuthService.saveAuth(
        token: auth.accessToken,
        userId: auth.userId,
        username: auth.username,
      );
      return ApiResult(
        success: true,
        data: auth,
        message: result.message,
        statusCode: result.statusCode,
      );
    }

    return ApiResult(
      success: false,
      message: result.message,
      statusCode: result.statusCode,
    );
  }

  /// 取得個人資料
  /// GET /api/v1/users/profile
  static Future<ApiResult<UserModel>> getProfile() async {
    final result = await _get(ApiConfig.profile);

    if (result.success && result.data != null) {
      return ApiResult(
        success: true,
        data: UserModel.fromJson(result.data!),
        statusCode: result.statusCode,
      );
    }

    return ApiResult(
      success: false,
      message: result.message,
      statusCode: result.statusCode,
    );
  }

  // ============================================================
  //  📄 PDF API
  // ============================================================

  /// 取得 PDF 指定頁面的渲染圖片
  /// GET /api/pdf/page-image/{pdfId}/{pageNumber}
  static Future<ApiResult<Uint8List>> getPdfPageImage({
    required int pdfId,
    required int pageNumber,
    int dpi = 150,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.pdfPageImage(pdfId, pageNumber)}?dpi=$dpi',
      );
      final headers = await AuthService.getAuthHeaders();
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        return ApiResult(
          success: true,
          data: response.bodyBytes,
          statusCode: 200,
        );
      }
      return ApiResult(
        success: false,
        message: 'Failed to load page image (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: '網路錯誤：$e',
        statusCode: 0,
      );
    }
  }

  /// 下載編輯後的 PDF（筆觸已渲染）
  /// GET /api/pdf/download/{pdfId}
  static Future<ApiResult<Uint8List>> downloadPdf({
    required int pdfId,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.pdfDownload(pdfId)}',
      );
      final headers = await AuthService.getAuthHeaders();
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        return ApiResult(
          success: true,
          data: response.bodyBytes,
          statusCode: 200,
        );
      }
      return ApiResult(
        success: false,
        message: '下載失敗 (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: '網路錯誤：$e',
        statusCode: 0,
      );
    }
  }

  /// 上傳 PDF
  /// POST /api/pdf/upload  (multipart/form-data)
  static Future<ApiResult<Map<String, dynamic>>> uploadPdf({
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.pdfUpload}');
      final token = await AuthService.getToken();

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      return ApiResult(
        success: response.statusCode == 200,
        data: body,
        message: body['message'] ?? body['detail'],
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: '上傳失敗：$e',
        statusCode: 0,
      );
    }
  }

  /// 取得 PDF 列表
  /// GET /api/pdf/list?limit=50
  static Future<ApiResult<List<PdfFileModel>>> getPdfList({
    int limit = 50,
  }) async {
    final result = await _get(
      ApiConfig.pdfList,
      queryParams: {'limit': limit.toString()},
    );

    if (result.success && result.data != null) {
      final data = result.data!['data'] as Map<String, dynamic>;
      final files = (data['pdf_files'] as List<dynamic>)
          .map((e) => PdfFileModel.fromJson(e))
          .toList();
      return ApiResult(
        success: true,
        data: files,
        statusCode: result.statusCode,
      );
    }

    return ApiResult(
      success: false,
      message: result.message,
      statusCode: result.statusCode,
    );
  }

  /// 查詢額度
  /// GET /api/pdf/quota
  static Future<ApiResult<int>> getQuota() async {
    final result = await _get(ApiConfig.pdfQuota);

    if (result.success && result.data != null) {
      final quota = result.data!['data']['quota'] as int;
      return ApiResult(
        success: true,
        data: quota,
        statusCode: result.statusCode,
      );
    }

    return ApiResult(
      success: false,
      message: result.message,
      statusCode: result.statusCode,
    );
  }

  /// 刪除 PDF
  /// DELETE /api/pdf/delete/{pdf_id}
  static Future<ApiResult<Map<String, dynamic>>> deletePdf(int pdfId) async {
    return _delete(ApiConfig.pdfDelete(pdfId));
  }

  /// 合併 PDF
  /// POST /api/pdf/merge
  static Future<ApiResult<MergedPdfResult>> mergePdfs({
    required List<int> pdfIds,
    required String outputFilename,
  }) async {
    final result = await _post(
      ApiConfig.pdfMerge,
      body: {
        'pdf_ids': pdfIds,
        'output_filename': outputFilename,
      },
    );

    if (result.success && result.data != null) {
      final data = result.data!['data'] as Map<String, dynamic>;
      final merged = MergedPdfResult.fromJson(data['merged_pdf']);
      return ApiResult(
        success: true,
        data: merged,
        message: result.message,
        statusCode: result.statusCode,
      );
    }

    return ApiResult(
      success: false,
      message: result.message,
      statusCode: result.statusCode,
    );
  }

  /// PDF 轉 Word
  /// GET /api/pdf/convert-to-word/{pdfId}
  /// 下載轉換後的 Word 檔案
  static Future<ApiResult<Uint8List>> convertToWord({
    required int pdfId,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.pdfConvertToWord(pdfId)}',
      );
      final headers = await AuthService.getAuthHeaders();
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        return ApiResult(
          success: true,
          data: response.bodyBytes,
          statusCode: 200,
        );
      }
      return ApiResult(
        success: false,
        message: '轉換失敗 (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: '網路錯誤：$e',
        statusCode: 0,
      );
    }
  }

  /// 插入圖片（上傳圖片到指定 PDF 頁面）
  /// POST /api/pdf/insert-image (multipart)
  static Future<ApiResult<Map<String, dynamic>>> insertImage({
    required int pdfId,
    required int pageNumber,
    required Uint8List imageBytes,
    required String filename,
    double x = 0,
    double y = 0,
    double imgWidth = 200,
    double imgHeight = 200,
    double rotation = 0,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.pdfInsertImage}');
      final headers = await AuthService.getAuthHeaders();

      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(headers);
      request.fields['pdf_id'] = pdfId.toString();
      request.fields['page_number'] = pageNumber.toString();
      request.fields['x'] = x.toString();
      request.fields['y'] = y.toString();
      request.fields['img_width'] = imgWidth.toString();
      request.fields['img_height'] = imgHeight.toString();
      request.fields['rotation'] = rotation.toString();
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        imageBytes,
        filename: filename,
      ));

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();
      final body = jsonDecode(responseBody) as Map<String, dynamic>;

      return ApiResult(
        success: streamedResponse.statusCode == 200,
        data: body,
        message: body['message']?.toString(),
        statusCode: streamedResponse.statusCode,
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: e.toString(),
        statusCode: 0,
      );
    }
  }

  /// 取得頁面圖片列表
  /// GET /api/pdf/page-images/{pdf_id}?page_number=
  static Future<ApiResult<List<Map<String, dynamic>>>> getPageImages({
    required int pdfId,
    int? pageNumber,
  }) async {
    final queryParams = <String, String>{};
    if (pageNumber != null) {
      queryParams['page_number'] = pageNumber.toString();
    }

    final result = await _get(
      ApiConfig.pdfPageImages(pdfId),
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );

    if (result.success && result.data != null) {
      final data = result.data!['data'] as Map<String, dynamic>;
      final images = (data['images'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      return ApiResult(success: true, data: images, statusCode: result.statusCode);
    }
    return ApiResult(success: false, message: result.message, statusCode: result.statusCode);
  }

  /// 取得已插入圖片的原始檔案 bytes
  /// GET /api/pdf/page-image-file/{image_id}
  static Future<ApiResult<Uint8List>> getPageImageFile({
    required int imageId,
  }) async {
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}${ApiConfig.pdfPageImageFile(imageId)}');
      final headers = await AuthService.getAuthHeaders();
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        return ApiResult(success: true, data: response.bodyBytes, statusCode: 200);
      }
      return ApiResult(success: false, message: 'Failed to load image', statusCode: response.statusCode);
    } catch (e) {
      return ApiResult(success: false, message: e.toString(), statusCode: 0);
    }
  }

  /// 更新圖片位置/尺寸/旋轉
  /// PUT /api/pdf/page-image/{image_id}
  static Future<ApiResult<Map<String, dynamic>>> updatePageImage({
    required int imageId,
    required double x,
    required double y,
    required double imgWidth,
    required double imgHeight,
    double rotation = 0,
  }) async {
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}${ApiConfig.pdfPageImageUpdate(imageId)}');
      final headers = await AuthService.getAuthHeaders();
      // PUT with query params
      final uriWithParams = uri.replace(queryParameters: {
        'x': x.toString(),
        'y': y.toString(),
        'img_width': imgWidth.toString(),
        'img_height': imgHeight.toString(),
        'rotation': rotation.toString(),
      });
      final response = await http.put(uriWithParams, headers: headers);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResult(
        success: response.statusCode == 200,
        data: body,
        message: body['message']?.toString(),
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult(success: false, message: e.toString(), statusCode: 0);
    }
  }

  /// 刪除插入的圖片
  /// DELETE /api/pdf/page-image/{image_id}
  static Future<ApiResult<Map<String, dynamic>>> deletePageImage({
    required int imageId,
  }) async {
    return _delete(ApiConfig.pdfPageImageDelete(imageId));
  }

  // ============================================================
  //  🖌️ 筆觸 API
  // ============================================================

  /// 保存單一筆觸
  /// POST /api/pdf/brush-save
  static Future<ApiResult<Map<String, dynamic>>> saveBrushStroke(
    BrushStrokeModel stroke,
  ) async {
    return _post(ApiConfig.pdfBrushSave, body: stroke.toJson());
  }

  /// 批量保存筆觸
  /// POST /api/pdf/brush-save-batch
  static Future<ApiResult<Map<String, dynamic>>> saveBrushStrokesBatch({
    required int pdfId,
    required List<BrushStrokeModel> strokes,
  }) async {
    return _post(
      ApiConfig.pdfBrushSaveBatch,
      body: {
        'pdf_id': pdfId,
        'strokes': strokes.map((s) => s.toJson()).toList(),
      },
    );
  }

  /// 取得筆觸
  /// GET /api/pdf/brush-strokes/{pdf_id}?page_number=
  static Future<ApiResult<List<BrushStrokeModel>>> getBrushStrokes({
    required int pdfId,
    int? pageNumber,
  }) async {
    final queryParams = <String, String>{};
    if (pageNumber != null) {
      queryParams['page_number'] = pageNumber.toString();
    }

    final result = await _get(
      ApiConfig.pdfBrushStrokes(pdfId),
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );

    if (result.success && result.data != null) {
      final data = result.data!['data'] as Map<String, dynamic>;
      final strokes = (data['strokes'] as List<dynamic>)
          .map((e) => BrushStrokeModel.fromJson(e))
          .toList();
      return ApiResult(
        success: true,
        data: strokes,
        statusCode: result.statusCode,
      );
    }

    return ApiResult(
      success: false,
      message: result.message,
      statusCode: result.statusCode,
    );
  }

  /// 刪除單一筆觸 (Undo)
  /// DELETE /api/pdf/brush-stroke/{stroke_id}
  static Future<ApiResult<Map<String, dynamic>>> deleteBrushStroke(
    int strokeId,
  ) async {
    return _delete(ApiConfig.pdfBrushStrokeDelete(strokeId));
  }

  /// 清除整頁筆觸
  /// DELETE /api/pdf/brush-strokes/{pdf_id}/page/{page_number}
  static Future<ApiResult<Map<String, dynamic>>> clearPageBrushStrokes({
    required int pdfId,
    required int pageNumber,
  }) async {
    return _delete(ApiConfig.pdfBrushStrokesClearPage(pdfId, pageNumber));
  }

  // ============================================================
  //  💳 支付 API
  // ============================================================

  /// 取得商品列表
  /// GET /api/payment/products
  static Future<ApiResult<List<ProductModel>>> getProducts() async {
    final result = await _get(ApiConfig.paymentProducts, requireAuth: false);

    if (result.success && result.data != null) {
      final data = result.data!['data'] as Map<String, dynamic>;
      final products = (data['products'] as List<dynamic>)
          .map((e) => ProductModel.fromJson(e))
          .toList();
      return ApiResult(
        success: true,
        data: products,
        statusCode: result.statusCode,
      );
    }

    return ApiResult(
      success: false,
      message: result.message,
      statusCode: result.statusCode,
    );
  }

  /// 驗證 Google Play 購買
  /// POST /api/payment/google-play/validate
  static Future<ApiResult<Map<String, dynamic>>> validateGooglePlayPurchase({
    required String transactionId,
    required String productId,
    required String receiptData,
  }) async {
    return _post(
      ApiConfig.paymentValidate,
      body: {
        'transaction_id': transactionId,
        'product_id': productId,
        'receipt_data': receiptData,
      },
    );
  }

  /// 取得交易紀錄
  /// GET /api/payment/transactions?limit=50
  static Future<ApiResult<List<TransactionModel>>> getTransactions({
    int limit = 50,
  }) async {
    final result = await _get(
      ApiConfig.paymentTransactions,
      queryParams: {'limit': limit.toString()},
    );

    if (result.success && result.data != null) {
      final data = result.data!['data'] as Map<String, dynamic>;
      final transactions = (data['transactions'] as List<dynamic>)
          .map((e) => TransactionModel.fromJson(e))
          .toList();
      return ApiResult(
        success: true,
        data: transactions,
        statusCode: result.statusCode,
      );
    }

    return ApiResult(
      success: false,
      message: result.message,
      statusCode: result.statusCode,
    );
  }

  /// 模擬購買（測試用）
  /// POST /api/payment/mock-purchase?product_id=xxx
  static Future<ApiResult<Map<String, dynamic>>> mockPurchase(
    String productId,
  ) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.paymentMockPurchase}?product_id=$productId',
      );
      final headers = await AuthService.getAuthHeaders();
      final response = await http.post(uri, headers: headers);
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      return ApiResult(
        success: response.statusCode == 200,
        data: body,
        message: body['message'] ?? body['detail'],
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: '網路錯誤：$e',
        statusCode: 0,
      );
    }
  }
}
