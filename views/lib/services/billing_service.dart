import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api_service.dart';

/// ============================================================
///  Google Play 商品 ID 設定
///  ⚠️ 請填入你在 Google Play Console 建立的商品 ID
/// ============================================================
class BillingProductIds {
  // --- 一次性購買商品 ID（對應 Google Play Console「受管理的商品」）---
  static const String oneTime50Pages = 'pdf_editor_50_pages';
  static const String oneTime5000Pages = 'pdf_editor_5000_pages';

  // --- 訂閱商品 ID（對應 Google Play Console「訂閱」）---
  static const String monthlyUnlimited = 'pdf_editor_monthly_unlimited';
  /// 所有一次性商品 ID
  static const Set<String> oneTimeProductIds = {
    oneTime50Pages,
    oneTime5000Pages,
  };

  /// 所有訂閱商品 ID
  static const Set<String> subscriptionProductIds = {
    monthlyUnlimited,
  };

  /// 所有商品 ID
  static Set<String> get allProductIds =>
      {...oneTimeProductIds, ...subscriptionProductIds};
}

/// 購買狀態回呼
typedef PurchaseCallback = void Function(bool success, String message);

/// Google Play Billing 服務
/// 封裝 in_app_purchase，處理真實的 Google Play 購買流程
class BillingService {
  static final BillingService _instance = BillingService._internal();
  factory BillingService() => _instance;
  BillingService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;

  bool _isAvailable = false;
  bool _isInitialized = false;

  /// 已查詢到的商品詳情（從 Google Play 取得）
  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

  /// 購買中的監聽
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// 購買完成後的回呼
  PurchaseCallback? _onPurchaseComplete;

  /// 是否可用（非 Web、非桌面、Google Play 可連線）
  bool get isAvailable => _isAvailable;

  // ============================================================
  //  初始化
  // ============================================================

  /// 初始化 Billing 服務。應在 App 啟動時呼叫一次。
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Web / Desktop 不支援 Google Play
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      debugPrint('[BillingService] 非行動平台，跳過初始化');
      _isAvailable = false;
      return;
    }

    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint('[BillingService] Google Play Billing 不可用');
      return;
    }

    // 監聽購買更新
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (error) {
        debugPrint('[BillingService] purchaseStream error: $error');
      },
      onDone: () {
        _subscription?.cancel();
      },
    );

    // 載入商品
    await loadProducts();

    debugPrint('[BillingService] 初始化完成，可用商品：${_products.length}');
  }

  /// 釋放資源
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
  }

  // ============================================================
  //  載入商品
  // ============================================================

  /// 從 Google Play 查詢商品詳情（價格、名稱等）
  Future<void> loadProducts() async {
    if (!_isAvailable) return;

    final response = await _iap.queryProductDetails(
      BillingProductIds.allProductIds,
    );

    if (response.error != null) {
      debugPrint('[BillingService] 查詢商品失敗: ${response.error}');
      return;
    }

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint(
        '[BillingService] 以下商品 ID 未在 Google Play 找到: '
        '${response.notFoundIDs.join(", ")}\n'
        '請確認 Google Play Console 已正確建立這些商品。',
      );
    }

    _products = response.productDetails;
  }

  // ============================================================
  //  發起購買
  // ============================================================

  /// 購買一次性商品（Consumable）
  Future<bool> buyOneTimeProduct(
    String productId, {
    PurchaseCallback? onComplete,
  }) async {
    return _buyProduct(productId, isSubscription: false, onComplete: onComplete);
  }

  /// 購買訂閱
  Future<bool> buySubscription(
    String productId, {
    PurchaseCallback? onComplete,
  }) async {
    return _buyProduct(productId, isSubscription: true, onComplete: onComplete);
  }

  Future<bool> _buyProduct(
    String productId, {
    required bool isSubscription,
    PurchaseCallback? onComplete,
  }) async {
    if (!_isAvailable) {
      onComplete?.call(false, 'Google Play Billing 不可用');
      return false;
    }

    // 找到對應商品
    final product = _products.cast<ProductDetails?>().firstWhere(
      (p) => p?.id == productId,
      orElse: () => null,
    );

    if (product == null) {
      onComplete?.call(false, '找不到商品：$productId');
      return false;
    }

    _onPurchaseComplete = onComplete;

    final purchaseParam = PurchaseParam(productDetails: product);

    try {
      if (isSubscription) {
        // 訂閱不可消耗
        return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      } else {
        // 一次性購買 = 可消耗商品（買完可再買）
        return await _iap.buyConsumable(purchaseParam: purchaseParam);
      }
    } catch (e) {
      debugPrint('[BillingService] 購買啟動失敗: $e');
      _onPurchaseComplete?.call(false, '購買失敗：$e');
      _onPurchaseComplete = null;
      return false;
    }
  }

  // ============================================================
  //  處理購買結果
  // ============================================================

  void _onPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchase in purchaseDetailsList) {
      _handlePurchase(purchase);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    debugPrint(
      '[BillingService] 購買狀態: ${purchase.status}, '
      'productID: ${purchase.productID}',
    );

    switch (purchase.status) {
      case PurchaseStatus.pending:
        debugPrint('[BillingService] 購買待處理中...');
        break;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        // 購買成功或恢復購買 → 向後端驗證
        await _verifyAndDeliver(purchase);
        break;

      case PurchaseStatus.error:
        debugPrint('[BillingService] 購買錯誤: ${purchase.error}');
        _onPurchaseComplete?.call(
          false,
          '購買失敗：${purchase.error?.message ?? "未知錯誤"}',
        );
        _onPurchaseComplete = null;
        break;

      case PurchaseStatus.canceled:
        debugPrint('[BillingService] 使用者取消購買');
        _onPurchaseComplete?.call(false, '已取消購買');
        _onPurchaseComplete = null;
        break;
    }

    // 完成購買交易（必須呼叫，否則 Google Play 會退款）
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  /// 將購買收據發送到後端驗證
  Future<void> _verifyAndDeliver(PurchaseDetails purchase) async {
    final productId = purchase.productID;
    final isSubscription =
        BillingProductIds.subscriptionProductIds.contains(productId);

    // 取得收據（purchase token）
    final receiptData =
        purchase.verificationData.serverVerificationData;
    final transactionId = purchase.purchaseID ?? '';

    debugPrint(
      '[BillingService] 向後端驗證: productId=$productId, '
      'transactionId=$transactionId, isSubscription=$isSubscription',
    );

    ApiResult<Map<String, dynamic>> result;

    if (isSubscription) {
      // 訂閱驗證
      result = await ApiService.validateSubscriptionPurchase(
        transactionId: transactionId,
        productId: productId,
        receiptData: receiptData,
      );
    } else {
      // 一次性購買驗證
      result = await ApiService.validateGooglePlayPurchase(
        transactionId: transactionId,
        productId: productId,
        receiptData: receiptData,
      );
    }

    if (result.success) {
      _onPurchaseComplete?.call(true, '購買成功！');
    } else {
      _onPurchaseComplete?.call(
        false,
        '後端驗證失敗：${result.message ?? "未知錯誤"}',
      );
    }

    _onPurchaseComplete = null;
  }

  // ============================================================
  //  工具方法
  // ============================================================

  /// 根據商品 ID 取得 Google Play 上的價格字串
  String? getPrice(String productId) {
    final product = _products.cast<ProductDetails?>().firstWhere(
      (p) => p?.id == productId,
      orElse: () => null,
    );
    return product?.price;
  }

  /// 取得一次性商品清單
  List<ProductDetails> get oneTimeProducts => _products
      .where((p) => BillingProductIds.oneTimeProductIds.contains(p.id))
      .toList();

  /// 取得訂閱商品清單
  List<ProductDetails> get subscriptionProducts => _products
      .where((p) => BillingProductIds.subscriptionProductIds.contains(p.id))
      .toList();
}
