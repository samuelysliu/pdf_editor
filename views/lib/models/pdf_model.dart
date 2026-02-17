/// PDF 文件數據模型

class PdfFileModel {
  final int id;
  final String filename;
  final int pageCount;
  final int quotaUsed;
  final String createdAt;

  PdfFileModel({
    required this.id,
    required this.filename,
    required this.pageCount,
    required this.quotaUsed,
    required this.createdAt,
  });

  factory PdfFileModel.fromJson(Map<String, dynamic> json) {
    return PdfFileModel(
      id: json['id'],
      filename: json['filename'],
      pageCount: json['page_count'],
      quotaUsed: json['quota_used'],
      createdAt: json['created_at'] ?? '',
    );
  }
}

class MergedPdfResult {
  final int id;
  final String filename;
  final String filePath;
  final int fileSize;
  final int pageCount;
  final int quotaUsed;

  MergedPdfResult({
    required this.id,
    required this.filename,
    required this.filePath,
    required this.fileSize,
    required this.pageCount,
    required this.quotaUsed,
  });

  factory MergedPdfResult.fromJson(Map<String, dynamic> json) {
    return MergedPdfResult(
      id: json['id'],
      filename: json['filename'],
      filePath: json['file_path'] ?? '',
      fileSize: json['file_size'] ?? 0,
      pageCount: json['page_count'],
      quotaUsed: json['quota_used'] ?? 0,
    );
  }
}
