/// 交易 & 商品數據模型

class TransactionModel {
  final String transactionId;
  final String productId;
  final int amount;
  final int quotaAdded;
  final String status;
  final String createdAt;

  TransactionModel({
    required this.transactionId,
    required this.productId,
    required this.amount,
    required this.quotaAdded,
    required this.status,
    required this.createdAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      transactionId: json['transaction_id'],
      productId: json['product_id'],
      amount: json['amount'],
      quotaAdded: json['quota_added'],
      status: json['status'],
      createdAt: json['created_at'] ?? '',
    );
  }
}

class ProductModel {
  final String productId;
  final int amount;
  final String amountFormatted;
  final int quota;
  final String currency;
  final String type; // 'one_time' or 'subscription'
  final String? description;
  final int? durationDays;

  ProductModel({
    required this.productId,
    required this.amount,
    required this.amountFormatted,
    required this.quota,
    required this.currency,
    this.type = 'one_time',
    this.description,
    this.durationDays,
  });

  bool get isSubscription => type == 'subscription';

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      productId: json['product_id'],
      amount: json['amount'],
      amountFormatted: json['amount_formatted'],
      quota: json['quota'] ?? 0,
      currency: json['currency'] ?? 'USD',
      type: json['type'] ?? 'one_time',
      description: json['description'],
      durationDays: json['duration_days'],
    );
  }
}
