/// API 設定檔
/// 修改 baseUrl 即可切換開發 / 正式環境
class ApiConfig {
  // --- 在這裡改你的後端位址 ---
  // static const String baseUrl = 'http://10.0.2.2:8000'; // Android Emulator
  static const String baseUrl = 'http://localhost:8000'; // iOS Simulator / Web
  // static const String baseUrl = 'https://your-server.com'; // Production

  // Auth
  static const String register = '/api/v1/users/register';
  static const String login = '/api/v1/users/login';
  static const String profile = '/api/v1/users/profile';

  // PDF
  static const String pdfUpload = '/api/pdf/upload';
  static const String pdfList = '/api/pdf/list';
  static const String pdfQuota = '/api/pdf/quota';
  static const String pdfInsertImage = '/api/pdf/insert-image';
  static String pdfPageImages(int pdfId) => '/api/pdf/page-images/$pdfId';
  static String pdfPageImageFile(int imageId) =>
      '/api/pdf/page-image-file/$imageId';
  static String pdfPageImageUpdate(int imageId) =>
      '/api/pdf/page-image/$imageId';
  static String pdfPageImageDelete(int imageId) =>
      '/api/pdf/page-image/$imageId';
  static const String pdfBrushSave = '/api/pdf/brush-save';
  static const String pdfBrushSaveBatch = '/api/pdf/brush-save-batch';
  static String pdfBrushStrokes(int pdfId) => '/api/pdf/brush-strokes/$pdfId';
  static String pdfBrushStrokeDelete(int strokeId) =>
      '/api/pdf/brush-stroke/$strokeId';
  static String pdfBrushStrokesClearPage(int pdfId, int pageNumber) =>
      '/api/pdf/brush-strokes/$pdfId/page/$pageNumber';
  static const String pdfMerge = '/api/pdf/merge';
  static String pdfConvertToWord(int pdfId) => '/api/pdf/convert-to-word/$pdfId';
  static String pdfDelete(int pdfId) => '/api/pdf/delete/$pdfId';
  static String pdfPageImage(int pdfId, int pageNumber) =>
      '/api/pdf/page-image/$pdfId/$pageNumber';
  static String pdfDownload(int pdfId) => '/api/pdf/download/$pdfId';

  // Payment
  static const String paymentValidate = '/api/payment/google-play/validate';
  static const String paymentProducts = '/api/payment/products';
  static const String paymentTransactions = '/api/payment/transactions';
  static const String paymentMockPurchase = '/api/payment/mock-purchase';
}
