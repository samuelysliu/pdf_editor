import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class UploadPdfPage extends StatefulWidget {
  final VoidCallback? onUploadSuccess;

  const UploadPdfPage({super.key, this.onUploadSuccess});

  @override
  State<UploadPdfPage> createState() => _UploadPdfPageState();
}

class _UploadPdfPageState extends State<UploadPdfPage> {
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  bool _isUploading = false;
  int? _currentQuota;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  Future<void> _loadQuota() async {
    final result = await ApiService.getQuota();
    if (result.success && mounted) {
      setState(() => _currentQuota = result.data);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _selectedFileBytes = result.files.single.bytes!;
        _selectedFileName = result.files.single.name;
      });
    }
  }

  Future<void> _uploadPdf() async {
    if (_selectedFileBytes == null || _selectedFileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇 PDF 文件')),
      );
      return;
    }

    setState(() => _isUploading = true);

    final result = await ApiService.uploadPdf(
      fileBytes: _selectedFileBytes!,
      fileName: _selectedFileName!,
    );

    setState(() => _isUploading = false);

    if (!mounted) return;

    if (result.success) {
      final data = result.data!['data'];
      final pdfFile = data['pdf_file'];
      final quotaRemaining = data['quota_remaining'];

      setState(() {
        _currentQuota = quotaRemaining;
        _selectedFileBytes = null;
        _selectedFileName = null;
      });

      // 通知首頁重新載入 PDF 列表
      widget.onUploadSuccess?.call();

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('上傳成功 ✅'),
          content: Text(
            '文件：${pdfFile['filename']}\n'
            '頁數：${pdfFile['page_count']}\n'
            '扣除額度：${pdfFile['quota_used']}\n'
            '剩餘額度：$quotaRemaining',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('確定'),
            ),
          ],
        ),
      );
    } else {
      String errorMsg = result.message ?? '上傳失敗';
      if (result.statusCode == 402) {
        errorMsg = '額度不足！請先充值再上傳。';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上傳 PDF'),
        actions: [
          // 額度顯示
          if (_currentQuota != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  avatar: const Icon(Icons.toll, size: 18),
                  label: Text('額度：$_currentQuota'),
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 選擇文件區域
            InkWell(
              onTap: _pickFile,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey.shade400,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _selectedFileName != null
                          ? Icons.picture_as_pdf
                          : Icons.cloud_upload_outlined,
                      size: 64,
                      color: _selectedFileName != null
                          ? Colors.red
                          : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedFileName ?? '點擊選擇 PDF 文件',
                      style: TextStyle(
                        fontSize: 16,
                        color: _selectedFileName != null
                            ? Colors.black87
                            : Colors.grey,
                      ),
                    ),
                    if (_selectedFileName != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _pickFile,
                        child: const Text('重新選擇'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // 上傳按鈕
            ElevatedButton.icon(
              onPressed: (_isUploading || _selectedFileBytes == null)
                  ? null
                  : _uploadPdf,
              icon: _isUploading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload),
              label: Text(
                _isUploading ? '上傳中...' : '上傳 PDF',
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),

            // 提示
            Text(
              '上傳 PDF 將按頁數扣除額度\n'
              '例：10 頁 PDF = 扣 10 額度',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
