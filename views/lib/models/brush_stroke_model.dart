/// 畫筆筆觸數據模型

class BrushStrokeModel {
  final int? strokeId;
  final int pdfId;
  final int pageNumber;
  final String color;
  final double width;
  final double opacity;
  final String tool;
  final List<StrokePoint> points;
  final String? createdAt;

  BrushStrokeModel({
    this.strokeId,
    required this.pdfId,
    required this.pageNumber,
    this.color = '#000000',
    this.width = 2.0,
    this.opacity = 1.0,
    this.tool = 'pen',
    required this.points,
    this.createdAt,
  });

  factory BrushStrokeModel.fromJson(Map<String, dynamic> json) {
    return BrushStrokeModel(
      strokeId: json['stroke_id'],
      pdfId: json['pdf_id'] ?? 0,
      pageNumber: json['page_number'],
      color: json['color'] ?? '#000000',
      width: (json['width'] ?? 2.0).toDouble(),
      opacity: (json['opacity'] ?? 1.0).toDouble(),
      tool: json['tool'] ?? 'pen',
      points: (json['points'] as List<dynamic>?)
              ?.map((p) => StrokePoint.fromJson(p))
              .toList() ??
          [],
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pdf_id': pdfId,
      'page_number': pageNumber,
      'color': color,
      'width': width,
      'opacity': opacity,
      'tool': tool,
      'points': points.map((p) => p.toJson()).toList(),
    };
  }
}

class StrokePoint {
  final double x;
  final double y;

  StrokePoint({required this.x, required this.y});

  factory StrokePoint.fromJson(Map<String, dynamic> json) {
    return StrokePoint(
      x: (json['x']).toDouble(),
      y: (json['y']).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}
