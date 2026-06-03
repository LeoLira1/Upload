import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/product_record.dart';
import '../services/excel_parser.dart';
import '../services/turso_service.dart';
import '../widgets/records_table.dart';

class UploadScreen extends StatefulWidget {
  final bool isVendas;

  const UploadScreen({super.key, required this.isVendas});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  ParseResult? _result;
  String? _fileName;
  bool _parsing = false;
  bool _uploading = false;
  String? _uploadMsg;
  bool _uploadOk = false;
  bool _showTable = false;
  DateTime _dataRef = DateTime.now();

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null && file.path == null) return;

    setState(() {
      _parsing = true;
      _result = null;
      _uploadMsg = null;
      _fileName = file.name;
    });

    final bytes = file.bytes ??
        await File(file.path!).readAsBytes();
    final parsed = ExcelParser.parse(bytes, isVendas: widget.isVendas);

    setState(() {
      _result = parsed;
      _parsing = false;
    });
  }

  Future<void> _send() async {
    if (_result == null || !_result!.ok) return;

    final url = await Config.getUrl();
    final token = await Config.getToken();
    if (url.isEmpty || token.isEmpty) {
      setState(() {
        _uploadMsg = '⚠️ Configure as credenciais do Turso em Configurações antes de enviar.';
        _uploadOk = false;
      });
      return;
    }

    setState(() {
      _uploading = true;
      _uploadMsg = null;
    });

    final svc = TursoService(url: url, token: token);
    late (bool, String) res;

    if (widget.isVendas) {
      res = await svc.uploadParcial(
        _result!.records,
        _result!.zerados,
        DateFormat('yyyy-MM-dd').format(_dataRef),
      );
    } else {
      res = await svc.uploadParcialEstoque(_result!.records);
    }

    final (ok, msg) = res;
    setState(() {
      _uploading = false;
      _uploadOk = ok;
      _uploadMsg = ok ? '$msg · ☁️ Sincronizado com o dashboard.' : msg;
    });

    if (ok) {
      setState(() {
        _result = null;
        _fileName = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isVendas ? '📈 Planilha de Vendas' : '📦 Estoque Parcial';
    final caption = widget.isVendas
        ? 'Atualiza a quantidade dos produtos e registra o histórico de vendas.'
        : 'Atualiza apenas a quantidade dos produtos presentes na planilha.';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(caption,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),

            // Date picker (only for VENDAS)
            if (widget.isVendas) ...[
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dataRef,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: Color(0xFF2563eb),
                          surface: Color(0xFF1e293b),
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) setState(() => _dataRef = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1e293b),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.white54, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        '📅  ${DateFormat('dd/MM/yyyy').format(_dataRef)}',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // File picker button
            SizedBox(
              height: 64,
              child: OutlinedButton.icon(
                onPressed: _parsing ? null : _pickFile,
                icon: _parsing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                    : const Icon(Icons.upload_file, color: Colors.white70),
                label: Text(
                  _fileName ?? 'Selecionar planilha XLSX',
                  style: const TextStyle(color: Colors.white70),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white30),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Parse result
            if (_result != null) ...[
              if (!_result!.ok)
                _card(
                  color: const Color(0xFF7f1d1d),
                  child: Text('❌ ${_result!.error}',
                      style: const TextStyle(color: Colors.white)),
                )
              else ...[
                _card(
                  color: const Color(0xFF14532d),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('✅ ${_result!.records.length} produto(s) lido(s).',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                      if (_divergences > 0)
                        Text('⚠️ $_divergences divergência(s) detectada(s).',
                            style: const TextStyle(color: Color(0xFFfbbf24))),
                      if (_result!.zerados.isNotEmpty)
                        Text(
                            '🗑️ ${_result!.zerados.length} produto(s) com estoque zerado.',
                            style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => setState(() => _showTable = !_showTable),
                  child: Row(
                    children: [
                      Icon(_showTable ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white54, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        _showTable ? 'Ocultar pré-visualização' : '👁 Pré-visualizar dados',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                if (_showTable) ...[
                  const SizedBox(height: 8),
                  RecordsTable(records: _result!.records),
                ],

                const SizedBox(height: 16),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _uploading ? null : _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563eb),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _uploading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white)),
                              SizedBox(width: 10),
                              Text('Enviando...'),
                            ],
                          )
                        : const Text('🚀 ENVIAR',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],

            // Upload result
            if (_uploadMsg != null) ...[
              const SizedBox(height: 12),
              _card(
                color: _uploadOk ? const Color(0xFF14532d) : const Color(0xFF7f1d1d),
                child: Text(_uploadMsg!,
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  int get _divergences =>
      _result?.records.where((r) => r.status != 'ok').length ?? 0;

  Widget _card({required Color color, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
