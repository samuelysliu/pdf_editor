import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/pdf_model.dart';
import '../models/brush_stroke_model.dart';
import '../models/page_image_model.dart';
import '../services/api_service.dart';

// Web 下載用
import 'web_download_stub.dart'
    if (dart.library.html) 'web_download.dart' as download_helper;

/// PDF 編輯頁面
/// 功能：畫筆繪製（pen / highlighter / eraser）、筆觸保存、Undo、清除整頁
class PdfEditorPage extends StatefulWidget {
  final PdfFileModel pdfFile;

  const PdfEditorPage({super.key, required this.pdfFile});

  @override
  State<PdfEditorPage> createState() => _PdfEditorPageState();
}

class _PdfEditorPageState extends State<PdfEditorPage> {
  // 目前頁碼（從 1 開始）
  int _currentPage = 1;

  // 繪圖狀態
  String _currentTool = 'pen';
  Color _currentColor = Colors.black;
  double _currentWidth = 3.0;
  double _currentOpacity = 1.0;

  // 當前正在畫的筆觸點
  List<StrokePoint> _currentPoints = [];

  // 已從後端載入的筆觸（按頁面）
  List<BrushStrokeModel> _savedStrokes = [];

  // 本地未保存的筆觸（畫完但還沒 saved 的，用於即時顯示）
  List<BrushStrokeModel> _localStrokes = [];

  // Undo 堆疊（記錄 stroke_id，用於刪除）
  List<int> _undoStack = [];

  // 等待中的筆觸保存任務
  final List<Future<void>> _pendingSaves = [];

  // 頁面上插入的圖片
  List<PageImageModel> _pageImages = [];
  // 每張插入圖片的實際 bytes（key = imageId）
  final Map<int, Uint8List> _pageImageData = {};
  // 正在拖曳的圖片 index（-1 = 無）
  int _draggingImageIndex = -1;
  // 正在調整大小的圖片 index（-1 = 無）
  int _resizingImageIndex = -1;
  // 正在旋轉的圖片 index（-1 = 無）
  int _rotatingImageIndex = -1;
  // 選中的圖片 index（-1 = 無）
  int _selectedImageIndex = -1;

  // PDF 頁面圖片
  Uint8List? _pageImageBytes;
  double _imageWidth = 0;
  double _imageHeight = 0;

  bool _isLoading = true;
  bool _isDownloading = false;

  /// 計算 BoxFit.contain 圖片在 widget 內的實際位置與縮放
  Rect _getImageRect(Size widgetSize) {
    if (_imageWidth == 0 || _imageHeight == 0) {
      return Rect.fromLTWH(0, 0, widgetSize.width, widgetSize.height);
    }
    final scaleX = widgetSize.width / _imageWidth;
    final scaleY = widgetSize.height / _imageHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final w = _imageWidth * scale;
    final h = _imageHeight * scale;
    final dx = (widgetSize.width - w) / 2;
    final dy = (widgetSize.height - h) / 2;
    return Rect.fromLTWH(dx, dy, w, h);
  }

  /// 螢幕座標 → 圖片像素座標（150 DPI image space）
  StrokePoint _screenToImage(Offset screen, Rect imageRect) {
    final displayScale = imageRect.width / _imageWidth;
    return StrokePoint(
      x: (screen.dx - imageRect.left) / displayScale,
      y: (screen.dy - imageRect.top) / displayScale,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadStrokes();
  }

  /// 載入當前頁面的筆觸
  Future<void> _loadStrokes() async {
    setState(() => _isLoading = true);

    // 同時載入筆觸、頁面圖片和插入的圖片
    final strokeResult = ApiService.getBrushStrokes(
      pdfId: widget.pdfFile.id,
      pageNumber: _currentPage,
    );
    final imageResult = ApiService.getPdfPageImage(
      pdfId: widget.pdfFile.id,
      pageNumber: _currentPage,
    );
    final pageImagesResult = ApiService.getPageImages(
      pdfId: widget.pdfFile.id,
      pageNumber: _currentPage,
    );

    final results = await Future.wait([strokeResult, imageResult, pageImagesResult]);
    final strokeRes = results[0] as ApiResult<List<BrushStrokeModel>>;
    final imageRes = results[1] as ApiResult<Uint8List>;
    final pageImagesRes = results[2] as ApiResult<List<Map<String, dynamic>>>;

    if (mounted) {
      setState(() {
        if (strokeRes.success && strokeRes.data != null) {
          _savedStrokes = strokeRes.data!;
          _localStrokes.clear();
          _undoStack = _savedStrokes
              .where((s) => s.strokeId != null)
              .map((s) => s.strokeId!)
              .toList();
        }
        if (imageRes.success && imageRes.data != null) {
          _pageImageBytes = imageRes.data!;
        } else {
          _pageImageBytes = null;
          _imageWidth = 0;
          _imageHeight = 0;
          debugPrint('PDF page image load failed: ${imageRes.message}');
        }

        // 載入插入的圖片列表
        if (pageImagesRes.success && pageImagesRes.data != null) {
          _pageImages = pageImagesRes.data!
              .map((e) => PageImageModel.fromJson(e))
              .toList();
        } else {
          _pageImages = [];
        }
        _selectedImageIndex = -1;
        _draggingImageIndex = -1;
        _resizingImageIndex = -1;
        _rotatingImageIndex = -1;

        _isLoading = false;
      });

      // 載入每張插入圖片的 bytes
      _pageImageData.clear();
      for (final img in _pageImages) {
        _loadInsertedImageData(img.imageId);
      }

      // 解碼圖片尺寸
      if (_pageImageBytes != null) {
        try {
          final codec = await ui.instantiateImageCodec(_pageImageBytes!);
          final frame = await codec.getNextFrame();
          _imageWidth = frame.image.width.toDouble();
          _imageHeight = frame.image.height.toDouble();
          frame.image.dispose();
        } catch (_) {
          _imageWidth = 0;
          _imageHeight = 0;
        }
      }

      // 如果圖片載入失敗，顯示提示
      if (!imageRes.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('頁面圖片載入失敗：${imageRes.message ?? "未知錯誤"}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 載入已插入圖片的實際 bytes
  Future<void> _loadInsertedImageData(int imageId) async {
    final result = await ApiService.getPageImageFile(imageId: imageId);
    if (result.success && result.data != null && mounted) {
      setState(() {
        _pageImageData[imageId] = result.data!;
      });
    }
  }

  /// 選擇並插入圖片
  Future<void> _pickAndInsertImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    if (file.bytes == null) return;

    // 預設尺寸（150 DPI image space）
    double imgW = 200;
    double imgH = 200;

    // 嘗試取得真實圖片比例
    try {
      final codec = await ui.instantiateImageCodec(file.bytes!);
      final frame = await codec.getNextFrame();
      final origW = frame.image.width.toDouble();
      final origH = frame.image.height.toDouble();
      frame.image.dispose();

      // 限制最大尺寸為圖片空間的一半
      final maxW = _imageWidth > 0 ? _imageWidth * 0.5 : 400;
      final maxH = _imageHeight > 0 ? _imageHeight * 0.5 : 400;
      final scale = (maxW / origW) < (maxH / origH) ? maxW / origW : maxH / origH;
      if (scale < 1.0) {
        imgW = origW * scale;
        imgH = origH * scale;
      } else {
        imgW = origW;
        imgH = origH;
      }
    } catch (_) {}

    // 放在畫面中央（image space）
    final cx = _imageWidth > 0 ? (_imageWidth - imgW) / 2 : 50;
    final cy = _imageHeight > 0 ? (_imageHeight - imgH) / 2 : 50;

    final result = await ApiService.insertImage(
      pdfId: widget.pdfFile.id,
      pageNumber: _currentPage,
      imageBytes: file.bytes!,
      filename: file.name,
      x: cx.toDouble(),
      y: cy.toDouble(),
      imgWidth: imgW,
      imgHeight: imgH,
    );

    if (result.success && mounted) {
      await _loadStrokes(); // 重新載入包含新圖片
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('圖片已插入 ✅'), backgroundColor: Colors.green),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('插入圖片失敗：${result.message ?? "未知錯誤"}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 更新圖片位置/尺寸/旋轉到後端
  Future<void> _updatePageImage(PageImageModel img) async {
    final saveFuture = ApiService.updatePageImage(
      imageId: img.imageId,
      x: img.x,
      y: img.y,
      imgWidth: img.imgWidth,
      imgHeight: img.imgHeight,
      rotation: img.rotation,
    );
    _pendingSaves.add(saveFuture);
    saveFuture.whenComplete(() => _pendingSaves.remove(saveFuture));
  }

  /// 刪除選中的圖片
  Future<void> _deleteSelectedImage() async {
    if (_selectedImageIndex < 0 || _selectedImageIndex >= _pageImages.length) return;

    final img = _pageImages[_selectedImageIndex];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除圖片'),
        content: const Text('確定要刪除這張插入的圖片嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final result = await ApiService.deletePageImage(imageId: img.imageId);
    if (result.success && mounted) {
      setState(() {
        _pageImages.removeAt(_selectedImageIndex);
        _pageImageData.remove(img.imageId);
        _selectedImageIndex = -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('圖片已刪除'), backgroundColor: Colors.green),
      );
    }
  }

  /// 筆觸結束時保存到後端
  Future<void> _saveCurrentStroke() async {
    if (_currentPoints.isEmpty) return;

    final stroke = BrushStrokeModel(
      pdfId: widget.pdfFile.id,
      pageNumber: _currentPage,
      color: '#${_currentColor.value.toRadixString(16).substring(2).toUpperCase()}',
      width: _currentWidth,
      opacity: _currentOpacity,
      tool: _currentTool,
      points: List.from(_currentPoints),
    );

    // 先加到本地列表即時顯示
    setState(() {
      _localStrokes.add(stroke);
      _currentPoints = [];
    });

    // 非同步保存到後端
    final saveFuture = _doSaveStroke(stroke);
    _pendingSaves.add(saveFuture);
    saveFuture.whenComplete(() => _pendingSaves.remove(saveFuture));
  }

  /// 實際執行筆觸保存
  Future<void> _doSaveStroke(BrushStrokeModel stroke) async {
    final result = await ApiService.saveBrushStroke(stroke);

    if (result.success && result.data != null) {
      final strokeId = result.data!['data']?['stroke_id'];
      if (strokeId != null) {
        setState(() {
          _undoStack.add(strokeId);
        });
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('筆觸保存失敗：${result.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Undo — 刪除最後一筆
  Future<void> _undo() async {
    if (_undoStack.isEmpty) return;

    final lastStrokeId = _undoStack.removeLast();

    final result = await ApiService.deleteBrushStroke(lastStrokeId);

    if (result.success) {
      // 重新載入筆觸
      await _loadStrokes();
    } else if (mounted) {
      // 還原 undo stack
      _undoStack.add(lastStrokeId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('撤銷失敗：${result.message}')),
      );
    }
  }

  /// 清除整頁筆觸
  Future<void> _clearPage() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清除整頁筆觸'),
        content: Text('確定要清除第 $_currentPage 頁的所有筆觸嗎？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final result = await ApiService.clearPageBrushStrokes(
      pdfId: widget.pdfFile.id,
      pageNumber: _currentPage,
    );

    if (result.success) {
      await _loadStrokes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清除'), backgroundColor: Colors.green),
        );
      }
    }
  }

  /// 切換頁面
  void _goToPage(int page) {
    if (page < 1 || page > widget.pdfFile.pageCount) return;
    setState(() {
      _currentPage = page;
      _currentPoints = [];
      _selectedImageIndex = -1;
      _draggingImageIndex = -1;
      _resizingImageIndex = -1;
      _rotatingImageIndex = -1;
    });
    _loadStrokes();
  }

  /// 下載編輯後的 PDF
  Future<void> _downloadPdf() async {
    setState(() => _isDownloading = true);

    // 等待所有筆觸保存完成
    if (_pendingSaves.isNotEmpty) {
      await Future.wait(List.from(_pendingSaves));
    }

    final result = await ApiService.downloadPdf(pdfId: widget.pdfFile.id);

    setState(() => _isDownloading = false);

    if (!mounted) return;

    if (result.success && result.data != null) {
      final filename = widget.pdfFile.filename.endsWith('.pdf')
          ? widget.pdfFile.filename
          : '${widget.pdfFile.filename}.pdf';

      if (kIsWeb) {
        download_helper.downloadFile(result.data!, filename);
      } else {
        // 非 Web 平台可擴展儲存到本地
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下載功能目前僅支援 Web 平台')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('下載成功 ✅'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('下載失敗：${result.message ?? "未知錯誤"}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 將 hex color 字串轉為 Color
  Color _hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pdfFile.filename),
        actions: [
          // 下載按鈕
          _isDownloading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: _downloadPdf,
                  tooltip: '下載 PDF',
                ),
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _undoStack.isEmpty ? null : _undo,
            tooltip: '撤銷',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearPage,
            tooltip: '清除整頁',
          ),
        ],
      ),
      body: Column(
        children: [
          // === 工具列 ===
          _buildToolbar(),

          // === 畫布區域 ===
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final widgetSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final imageRect = _getImageRect(widgetSize);

                      return Stack(
                        children: [
                          // ① PDF 頁面圖片背景
                          if (_pageImageBytes != null)
                            Positioned.fill(
                              child: Image.memory(
                                _pageImageBytes!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            )
                          else
                            Positioned.fill(
                              child: Container(
                                color: Colors.grey.shade100,
                                child: const Center(
                                  child: Text(
                                    '無法載入 PDF 頁面\n請確認後端已啟動且 PDF 檔案存在',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 14),
                                  ),
                                ),
                              ),
                            ),

                          // ② 繪圖手勢層（接收所有未被圖片攔截的觸控）
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) {
                                // 點擊空白處取消選中圖片
                                if (_selectedImageIndex >= 0) {
                                  setState(
                                      () => _selectedImageIndex = -1);
                                }
                              },
                              onPanStart: (details) {
                                setState(() {
                                  _currentPoints.add(
                                    _screenToImage(
                                        details.localPosition, imageRect),
                                  );
                                });
                              },
                              onPanUpdate: (details) {
                                setState(() {
                                  _currentPoints.add(
                                    _screenToImage(
                                        details.localPosition, imageRect),
                                  );
                                });
                              },
                              onPanEnd: (_) => _saveCurrentStroke(),
                            ),
                          ),

                          // ③ 插入的圖片層（在繪圖層之上，可攔截觸控）
                          ..._buildInsertedImages(imageRect),

                          // ④ 筆觸渲染層（最上層顯示，但不接收觸控）
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _StrokePainter(
                                  savedStrokes: _savedStrokes,
                                  localStrokes: _localStrokes,
                                  currentPoints: _currentPoints,
                                  currentColor: _currentColor,
                                  currentWidth: _currentWidth,
                                  currentOpacity: _currentOpacity,
                                  hexToColor: _hexToColor,
                                  imageRect: imageRect,
                                  imageWidth: _imageWidth,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),

          // === 頁碼切換 ===
          _buildPageNavigator(),
        ],
      ),
    );
  }

  /// 工具列：pen / highlighter / eraser / 顏色 / 寬度
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.grey.shade100,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 工具選擇
            _toolButton('pen', Icons.edit, 'Pen'),
            _toolButton('highlighter', Icons.highlight, 'Highlighter'),

            const SizedBox(width: 8),

            // 插入圖片按鈕
            IconButton(
              icon: const Icon(Icons.add_photo_alternate),
              tooltip: '插入圖片',
              onPressed: _pickAndInsertImage,
            ),

            // 刪除選中圖片
            if (_selectedImageIndex >= 0)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: '刪除選中圖片',
                onPressed: _deleteSelectedImage,
              ),

            const SizedBox(width: 8),

            // 顏色選擇
            ...[Colors.black, Colors.red, Colors.blue, Colors.green]
                .map((c) => _colorButton(c)),

            const SizedBox(width: 8),

            // 線寬
            const Text('寬度：', style: TextStyle(fontSize: 12)),
            SizedBox(
              width: 120,
              child: Slider(
                value: _currentWidth,
                min: 1.0,
                max: 20.0,
                onChanged: (v) => setState(() => _currentWidth = v),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(String tool, IconData icon, String tooltip) {
    final isActive = _currentTool == tool;
    return IconButton(
      icon: Icon(icon, color: isActive ? Colors.blue : Colors.grey),
      tooltip: tooltip,
      onPressed: () {
        setState(() {
          _currentTool = tool;
          if (tool == 'highlighter') {
            _currentOpacity = 0.4;
            _currentWidth = 12.0;
          } else if (tool == 'eraser') {
            _currentColor = Colors.white;
            _currentOpacity = 1.0;
            _currentWidth = 15.0;
          } else {
            _currentOpacity = 1.0;
            _currentWidth = 3.0;
          }
        });
      },
    );
  }

  Widget _colorButton(Color color) {
    final isActive = _currentColor == color && _currentTool != 'eraser';
    return GestureDetector(
      onTap: () {
        if (_currentTool == 'eraser') return;
        setState(() => _currentColor = color);
      },
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? Colors.blue : Colors.grey.shade300,
            width: isActive ? 3 : 1,
          ),
        ),
      ),
    );
  }

  /// 構建插入的圖片 Widget 列表（可拖曳 / 縮放 / 旋轉）
  ///
  /// 每張圖片拆成多個獨立的 [Positioned] 子元件：
  ///   - 圖片本體（可拖曳）
  ///   - 縮放手柄（右下角藍色圓）
  ///   - 旋轉手柄（上方綠色圓 + 連線）
  /// 這樣每個元件都是 Stack 的一級 child，
  /// hit-test 不會被父 Positioned 的邊界裁切。
  List<Widget> _buildInsertedImages(Rect imageRect) {
    if (_imageWidth == 0) return [];
    final displayScale = imageRect.width / _imageWidth;
    const double handleSize = 28;
    const double handleHalf = handleSize / 2;
    const double rotateArmLen = 40; // 旋轉手柄離圖片頂端的距離

    final widgets = <Widget>[];
    for (int i = 0; i < _pageImages.length; i++) {
      final img = _pageImages[i];
      final bytes = _pageImageData[img.imageId];
      if (bytes == null) continue;

      final left = img.x * displayScale + imageRect.left;
      final top = img.y * displayScale + imageRect.top;
      final width = img.imgWidth * displayScale;
      final height = img.imgHeight * displayScale;
      final isSelected = _selectedImageIndex == i;
      final rotRad = img.rotation * math.pi / 180.0;
      final cx = left + width / 2;
      final cy = top + height / 2;

      // ───────── ① 圖片本體 ─────────
      widgets.add(
        Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: Transform.rotate(
            angle: rotRad,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _selectedImageIndex = i),
              onPanStart: (_) => setState(() {
                _selectedImageIndex = i;
                _draggingImageIndex = i;
              }),
              onPanUpdate: (details) {
                if (_draggingImageIndex != i) return;
                setState(() {
                  img.x += details.delta.dx / displayScale;
                  img.y += details.delta.dy / displayScale;
                });
              },
              onPanEnd: (_) {
                _draggingImageIndex = -1;
                _updatePageImage(img);
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.memory(bytes,
                        fit: BoxFit.fill, gaplessPlayback: true),
                  ),
                  if (isSelected)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      if (!isSelected) continue;

      // ── 工具函式：將相對於圖片中心的偏移量旋轉到螢幕座標 ──
      Offset _rotatedOffset(double relX, double relY) {
        return Offset(
          cx + relX * math.cos(rotRad) - relY * math.sin(rotRad),
          cy + relX * math.sin(rotRad) + relY * math.cos(rotRad),
        );
      }

      // ───────── ② 縮放手柄（右下角） ─────────
      final resizePos = _rotatedOffset(width / 2, height / 2);
      widgets.add(
        Positioned(
          left: resizePos.dx - handleHalf,
          top: resizePos.dy - handleHalf,
          width: handleSize,
          height: handleSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _resizingImageIndex = i,
            onPanUpdate: (details) {
              if (_resizingImageIndex != i) return;
              final cosA = math.cos(rotRad);
              final sinA = math.sin(rotRad);
              final localDx =
                  details.delta.dx * cosA + details.delta.dy * sinA;
              final localDy =
                  -details.delta.dx * sinA + details.delta.dy * cosA;
              setState(() {
                img.imgWidth += localDx / displayScale;
                img.imgHeight += localDy / displayScale;
                if (img.imgWidth < 30) img.imgWidth = 30;
                if (img.imgHeight < 30) img.imgHeight = 30;
              });
            },
            onPanEnd: (_) {
              _resizingImageIndex = -1;
              _updatePageImage(img);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black26, blurRadius: 3, spreadRadius: 1)
                ],
              ),
              child:
                  const Icon(Icons.open_in_full, size: 14, color: Colors.white),
            ),
          ),
        ),
      );

      // ───────── ③ 旋轉手柄（上方中央） ─────────
      final rotatePos = _rotatedOffset(0, -(height / 2 + rotateArmLen));
      final lineStart = _rotatedOffset(0, -(height / 2));
      widgets.add(
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _HandleLinePainter(
                start: lineStart,
                end: Offset(
                    rotatePos.dx, rotatePos.dy),
              ),
            ),
          ),
        ),
      );
      widgets.add(
        Positioned(
          left: rotatePos.dx - handleHalf,
          top: rotatePos.dy - handleHalf,
          width: handleSize,
          height: handleSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _rotatingImageIndex = i,
            onPanUpdate: (details) {
              if (_rotatingImageIndex != i) return;
              setState(() {
                img.rotation += details.delta.dx * 0.5;
                img.rotation = img.rotation % 360;
                if (img.rotation < 0) img.rotation += 360;
              });
            },
            onPanEnd: (_) {
              _rotatingImageIndex = -1;
              _updatePageImage(img);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black26, blurRadius: 3, spreadRadius: 1)
                ],
              ),
              child: const Icon(Icons.rotate_right,
                  size: 16, color: Colors.white),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  /// 頁碼導航
  Widget _buildPageNavigator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
          ),
          Text(
            '$_currentPage / ${widget.pdfFile.pageCount}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < widget.pdfFile.pageCount
                ? () => _goToPage(_currentPage + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

/// 自訂 Painter：渲染已保存 + 本地 + 當前正在畫的筆觸
/// 筆觸座標儲存在 150 DPI 圖片像素空間，繪製時轉換回螢幕座標
class _StrokePainter extends CustomPainter {
  final List<BrushStrokeModel> savedStrokes;
  final List<BrushStrokeModel> localStrokes;
  final List<StrokePoint> currentPoints;
  final Color currentColor;
  final double currentWidth;
  final double currentOpacity;
  final Color Function(String) hexToColor;
  final Rect imageRect;
  final double imageWidth;

  _StrokePainter({
    required this.savedStrokes,
    required this.localStrokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
    required this.currentOpacity,
    required this.hexToColor,
    required this.imageRect,
    required this.imageWidth,
  });

  /// 圖片像素座標 → 螢幕座標
  Offset _toScreen(StrokePoint pt) {
    if (imageWidth == 0) return Offset(pt.x, pt.y);
    final scale = imageRect.width / imageWidth;
    return Offset(
      pt.x * scale + imageRect.left,
      pt.y * scale + imageRect.top,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 繪製已保存的筆觸
    for (final stroke in savedStrokes) {
      _drawStroke(canvas, stroke.points, hexToColor(stroke.color),
          stroke.width, stroke.opacity);
    }

    // 繪製本地筆觸
    for (final stroke in localStrokes) {
      _drawStroke(canvas, stroke.points, hexToColor(stroke.color),
          stroke.width, stroke.opacity);
    }

    // 繪製當前正在畫的筆觸
    if (currentPoints.isNotEmpty) {
      _drawStroke(
          canvas, currentPoints, currentColor, currentWidth, currentOpacity);
    }
  }

  void _drawStroke(Canvas canvas, List<StrokePoint> points, Color color,
      double width, double opacity) {
    if (points.length < 2) return;

    // 筆觸寬度也跟隨縮放
    final displayScale = imageWidth > 0 ? imageRect.width / imageWidth : 1.0;

    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = width * displayScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final first = _toScreen(points.first);
    final path = Path();
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < points.length; i++) {
      final pt = _toScreen(points[i]);
      path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}

/// 繪製旋轉手柄與圖片頂端之間的連線
class _HandleLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;

  _HandleLinePainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(covariant _HandleLinePainter old) =>
      old.start != start || old.end != end;
}
