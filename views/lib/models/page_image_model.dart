/// 頁面插入圖片數據模型

class PageImageModel {
  final int imageId;
  final int pdfId;
  final int pageNumber;
  double x;
  double y;
  double imgWidth;
  double imgHeight;
  double rotation;
  final String? filename;
  final String? createdAt;

  PageImageModel({
    required this.imageId,
    required this.pdfId,
    required this.pageNumber,
    required this.x,
    required this.y,
    required this.imgWidth,
    required this.imgHeight,
    this.rotation = 0,
    this.filename,
    this.createdAt,
  });

  factory PageImageModel.fromJson(Map<String, dynamic> json) {
    return PageImageModel(
      imageId: json['image_id'] ?? json['id'] ?? 0,
      pdfId: json['pdf_id'] ?? 0,
      pageNumber: json['page_number'] ?? 1,
      x: (json['x'] ?? 0).toDouble(),
      y: (json['y'] ?? 0).toDouble(),
      imgWidth: (json['img_width'] ?? json['width'] ?? 200).toDouble(),
      imgHeight: (json['img_height'] ?? json['height'] ?? 200).toDouble(),
      rotation: (json['rotation'] ?? 0).toDouble(),
      filename: json['filename'],
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'image_id': imageId,
      'pdf_id': pdfId,
      'page_number': pageNumber,
      'x': x,
      'y': y,
      'img_width': imgWidth,
      'img_height': imgHeight,
      'rotation': rotation,
      if (filename != null) 'filename': filename,
    };
  }

  PageImageModel copyWith({
    int? imageId,
    int? pdfId,
    int? pageNumber,
    double? x,
    double? y,
    double? imgWidth,
    double? imgHeight,
    double? rotation,
    String? filename,
    String? createdAt,
  }) {
    return PageImageModel(
      imageId: imageId ?? this.imageId,
      pdfId: pdfId ?? this.pdfId,
      pageNumber: pageNumber ?? this.pageNumber,
      x: x ?? this.x,
      y: y ?? this.y,
      imgWidth: imgWidth ?? this.imgWidth,
      imgHeight: imgHeight ?? this.imgHeight,
      rotation: rotation ?? this.rotation,
      filename: filename ?? this.filename,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
