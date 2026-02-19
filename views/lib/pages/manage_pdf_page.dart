import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/pdf_model.dart';
import '../services/api_service.dart';
import '../services/billing_service.dart';
import 'pdf_editor_page.dart';
import 'web_download_stub.dart'
    if (dart.library.html) 'web_download.dart' as download_helper;

/// 管理 PDF 頁面
/// 功能：列表、刪除、合併、轉 Word、額度顯示、充值
class ManagePdfPage extends StatefulWidget {
  const ManagePdfPage({super.key});

  @override
  State<ManagePdfPage> createState() => ManagePdfPageState();
}

class ManagePdfPageState extends State<ManagePdfPage> {
  List<PdfFileModel> _pdfFiles = [];
  int? _quota;
  bool _isLoading = true;

  /// 供外部呼叫重新載入資料
  void refresh() => _loadData();

  // 合併模式
  bool _isMergeMode = false;
  final Set<int> _selectedForMerge = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // 同時載入 PDF 列表和額度
    final pdfResult = await ApiService.getPdfList();
    final quotaResult = await ApiService.getQuota();

    if (mounted) {
      setState(() {
        if (pdfResult.success && pdfResult.data != null) {
          _pdfFiles = pdfResult.data!;
        }
        if (quotaResult.success && quotaResult.data != null) {
          _quota = quotaResult.data!;
        }
        _isLoading = false;
      });
    }
  }

  /// 刪除 PDF
  Future<void> _deletePdf(PdfFileModel pdf) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除 PDF'),
        content: Text('確定要刪除「${pdf.filename}」嗎？'),
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

    final result = await ApiService.deletePdf(pdf.id);
    if (result.success) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已刪除'), backgroundColor: Colors.green),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刪除失敗：${result.message}'), backgroundColor: Colors.red),
      );
    }
  }

  /// 合併選中的 PDF
  Future<void> _mergePdfs() async {
    if (_selectedForMerge.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少選擇 2 個 PDF 文件')),
      );
      return;
    }

    // 讓用戶輸入合併後的檔名
    final filenameController = TextEditingController(text: 'merged');
    final filename = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('合併 PDF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('已選擇 ${_selectedForMerge.length} 個文件'),
            const SizedBox(height: 16),
            TextField(
              controller: filenameController,
              decoration: const InputDecoration(
                labelText: '輸出檔名',
                suffixText: '.pdf',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, filenameController.text.trim()),
            child: const Text('合併'),
          ),
        ],
      ),
    );

    if (filename == null || filename.isEmpty) return;

    final result = await ApiService.mergePdfs(
      pdfIds: _selectedForMerge.toList(),
      outputFilename: filename,
    );

    if (result.success && mounted) {
      setState(() {
        _isMergeMode = false;
        _selectedForMerge.clear();
      });
      await _loadData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('合併成功！新文件：${result.data?.filename}'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('合併失敗：${result.message}'), backgroundColor: Colors.red),
      );
    }
  }

  bool _isConverting = false;

  /// 轉 Word 並下載
  Future<void> _convertToWord(PdfFileModel pdf) async {
    setState(() => _isConverting = true);

    final result = await ApiService.convertToWord(pdfId: pdf.id);

    setState(() => _isConverting = false);

    if (!mounted) return;

    if (result.success && result.data != null) {
      final outputName = pdf.filename.replaceAll('.pdf', '.docx');
      if (kIsWeb) {
        download_helper.downloadFile(
          result.data!,
          outputName,
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下載功能目前僅支援 Web 平台')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('轉換成功，已下載：$outputName'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('轉換失敗：${result.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 模擬購買額度
  Future<void> _showPurchaseDialog() async {
    // 先取得商品列表和訂閱狀態
    final productsResult = await ApiService.getProducts();
    final subStatusResult = await ApiService.getSubscriptionStatus();
    final billing = BillingService();

    if (!productsResult.success || productsResult.data == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法載入商品列表')),
        );
      }
      return;
    }

    if (!mounted) return;

    final products = productsResult.data!;
    final isSubscribed = subStatusResult.success &&
        subStatusResult.data != null &&
        (subStatusResult.data!['is_subscribed'] == true);
    final subscriptionEndDate = subStatusResult.data?['end_date'];

    // 分為一次性商品和訂閱商品
    final oneTimeProducts = products.where((p) => !p.isSubscription).toList();
    final subscriptionProducts = products.where((p) => p.isSubscription).toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('購買額度'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // === 訂閱制區塊 ===
                if (isSubscribed) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 32),
                        const SizedBox(height: 4),
                        const Text(
                          '訂閱中 — 無限使用',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (subscriptionEndDate != null)
                          Text(
                            '到期日：${subscriptionEndDate.toString().substring(0, 10)}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else if (subscriptionProducts.isNotEmpty) ...[
                  const Text(
                    '⭐ 訂閱方案',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  ...subscriptionProducts.map((p) => Card(
                    color: Colors.amber.shade50,
                    child: ListTile(
                      leading: const Icon(Icons.all_inclusive, color: Colors.deepOrange),
                      title: Text(p.description ?? '月訂閱 — 無限使用'),
                      subtitle: Text('${p.amountFormatted}  ·  每月吃到飽'),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          await _purchaseSubscription(p.productId);
                        },
                        child: Text(
                          billing.isAvailable
                              ? (billing.getPrice(p.productId) ?? '訂閱')
                              : '訂閱',
                        ),
                      ),
                    ),
                  )),
                  const Divider(height: 24),
                ],

                // === 一次性購買區塊 ===
                const Text(
                  '💰 單次購買',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                ...oneTimeProducts.map((p) => ListTile(
                  title: Text('${p.quota} 頁'),
                  subtitle: Text(
                    billing.isAvailable
                        ? (billing.getPrice(p.productId) ?? p.amountFormatted)
                        : p.amountFormatted,
                  ),
                  trailing: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _purchaseOneTime(p.productId, p.quota);
                    },
                    child: const Text('購買'),
                  ),
                )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  /// 購買一次性商品
  Future<void> _purchaseOneTime(String productId, int quota) async {
    final billing = BillingService();

    if (billing.isAvailable) {
      // 真實 Google Play 購買
      await billing.buyOneTimeProduct(
        productId,
        onComplete: (success, message) async {
          if (success && mounted) {
            await _loadData();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('購買成功！+$quota 頁'),
                backgroundColor: Colors.green,
              ),
            );
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );
    } else {
      // Web / 桌面版 fallback 到 mock
      final result = await ApiService.mockPurchase(productId);
      if (result.success && mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('購買成功！+$quota 頁'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('購買失敗：${result.message ?? "未知錯誤"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 購買訂閱方案
  Future<void> _purchaseSubscription(String productId) async {
    final billing = BillingService();

    if (billing.isAvailable) {
      // 真實 Google Play 訂閱
      await billing.buySubscription(
        productId,
        onComplete: (success, message) async {
          if (success && mounted) {
            await _loadData();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('訂閱成功！已啟用無限使用 🎉'),
                backgroundColor: Colors.green,
              ),
            );
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );
    } else {
      // Web / 桌面版 fallback 到 mock
      final result = await ApiService.mockSubscriptionPurchase(productId);
      if (result.success && mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('訂閱成功！已啟用無限使用 🎉'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('訂閱失敗：${result.message ?? "未知錯誤"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 打開編輯頁面
  void _openEditor(PdfFileModel pdf) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PdfEditorPage(pdfFile: pdf)),
    ).then((_) => _loadData()); // 返回時重新載入
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理 PDF'),
        actions: [
          // 額度
          if (_quota != null)
            GestureDetector(
              onTap: _showPurchaseDialog,
              child: Chip(
                avatar: const Icon(Icons.toll, size: 18),
                label: Text('$_quota 頁'),
              ),
            ),
          const SizedBox(width: 8),

          // 合併模式切換
          if (!_isMergeMode)
            IconButton(
              icon: const Icon(Icons.merge),
              tooltip: '合併 PDF',
              onPressed: () => setState(() => _isMergeMode = true),
            )
          else ...[
            TextButton(
              onPressed: _mergePdfs,
              child: Text('合併 (${_selectedForMerge.length})'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _isMergeMode = false;
                _selectedForMerge.clear();
              }),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pdfFiles.isEmpty
              ? const Center(
                  child: Text('尚無 PDF 文件\n請先上傳', textAlign: TextAlign.center),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    itemCount: _pdfFiles.length,
                    itemBuilder: (_, index) {
                      final pdf = _pdfFiles[index];
                      final isSelected = _selectedForMerge.contains(pdf.id);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: _isMergeMode
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedForMerge.add(pdf.id);
                                      } else {
                                        _selectedForMerge.remove(pdf.id);
                                      }
                                    });
                                  },
                                )
                              : const Icon(Icons.picture_as_pdf,
                                  color: Colors.red, size: 36),
                          title: Text(
                            pdf.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${pdf.pageCount} 頁 · 額度扣除 ${pdf.quotaUsed}',
                          ),
                          trailing: _isMergeMode
                              ? null
                              : PopupMenuButton<String>(
                                  onSelected: (action) {
                                    switch (action) {
                                      case 'edit':
                                        _openEditor(pdf);
                                        break;
                                      case 'word':
                                        _convertToWord(pdf);
                                        break;
                                      case 'delete':
                                        _deletePdf(pdf);
                                        break;
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(
                                        leading: Icon(Icons.edit),
                                        title: Text('編輯'),
                                        dense: true,
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'word',
                                      child: ListTile(
                                        leading: Icon(Icons.description),
                                        title: Text('轉 Word'),
                                        dense: true,
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(
                                        leading: Icon(Icons.delete,
                                            color: Colors.red),
                                        title: Text('刪除',
                                            style:
                                                TextStyle(color: Colors.red)),
                                        dense: true,
                                      ),
                                    ),
                                  ],
                                ),
                          onTap: _isMergeMode
                              ? () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedForMerge.remove(pdf.id);
                                    } else {
                                      _selectedForMerge.add(pdf.id);
                                    }
                                  });
                                }
                              : () => _openEditor(pdf),
                        ),
                      );
                    },
                  ),
                ),
          // 轉換中的遮罩
          if (_isConverting)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('正在轉換為 Word…',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
