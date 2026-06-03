import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_record.dart';

class TursoService {
  final String url;
  final String token;

  TursoService({required this.url, required this.token});

  Map<String, dynamic> _arg(String type, String value) =>
      {'type': type, 'value': value};

  Map<String, dynamic> _textArg(String v) => _arg('text', v);
  Map<String, dynamic> _intArg(int v) => _arg('integer', v.toString());
  Map<String, dynamic> _nullArg() => {'type': 'null'};

  Future<(bool, String)> _pipeline(List<Map<String, dynamic>> stmts) async {
    final requests = [
      ...stmts.map((s) => {'type': 'execute', 'stmt': s}),
      {'type': 'close'},
    ];

    try {
      final resp = await http.post(
        Uri.parse('$url/v2/pipeline'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'requests': requests}),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = body['results'] as List? ?? [];
        for (final r in results) {
          if (r is Map && r['type'] == 'error') {
            return (false, 'Turso error: ${r['error']}');
          }
        }
        return (true, '');
      }
      return (false, 'HTTP ${resp.statusCode}: ${resp.body}');
    } catch (e) {
      return (false, 'Conexão falhou: $e');
    }
  }

  Future<(bool, String)> uploadParcial(
    List<ProductRecord> records,
    List<Map<String, dynamic>> zerados,
    String dataRef,
  ) async {
    final now = _nowBrt();
    final stmts = <Map<String, dynamic>>[];

    // Remove zeroed products
    for (final z in zerados) {
      stmts.add({
        'sql': 'DELETE FROM estoque_mestre WHERE codigo = ?',
        'args': [_textArg(z['codigo'] as String)],
      });
    }

    // Upsert each record (preserving divergences like the Python code)
    for (final r in records) {
      stmts.add({
        'sql': '''
INSERT INTO estoque_mestre
  (codigo, produto, categoria, qtd_sistema, qtd_fisica, diferenca, nota, status, ultima_contagem, criado_em)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(codigo) DO UPDATE SET
  produto           = excluded.produto,
  categoria         = excluded.categoria,
  qtd_sistema       = excluded.qtd_sistema,
  qtd_fisica        = CASE WHEN status IN ('falta','sobra')
                        THEN excluded.qtd_sistema + diferenca
                        ELSE excluded.qtd_fisica END,
  diferenca         = CASE WHEN status IN ('falta','sobra')
                        THEN diferenca
                        ELSE excluded.diferenca END,
  nota              = excluded.nota,
  status            = CASE WHEN status IN ('falta','sobra')
                        THEN status
                        ELSE excluded.status END,
  ultima_contagem   = excluded.ultima_contagem
''',
        'args': [
          _textArg(r.codigo),
          _textArg(r.produto),
          _textArg(r.categoria),
          _intArg(r.qtdSistema),
          _intArg(r.qtdFisica),
          _intArg(r.diferenca),
          _textArg(r.nota),
          _textArg(r.status),
          _textArg(now),
          _textArg(now),
        ],
      });
    }

    // Sales history
    for (final r in records) {
      if (r.qtdVendida > 0) {
        stmts.add({
          'sql': '''
INSERT INTO vendas_historico (codigo, produto, categoria, qtd_vendida, qtd_estoque, data_upload, criado_em)
VALUES (?, ?, ?, ?, ?, ?, ?)
''',
          'args': [
            _textArg(r.codigo),
            _textArg(r.produto),
            _textArg(r.categoria),
            _intArg(r.qtdVendida),
            _intArg(r.qtdSistema),
            _textArg(dataRef),
            _textArg(now),
          ],
        });
      }
    }

    // historico_uploads
    final nDiv = records.where((r) => r.status != 'ok').length;
    stmts.add({
      'sql': '''
INSERT INTO historico_uploads (data, tipo, arquivo, total_produtos_lote, novos, atualizados, divergentes)
VALUES (?, ?, ?, ?, ?, ?, ?)
''',
      'args': [
        _textArg(now),
        _textArg('PARCIAL'),
        _textArg(''),
        _intArg(records.length),
        _intArg(0),
        _intArg(records.length),
        _intArg(nDiv),
      ],
    });

    return _executeBatch(stmts, '✅ Parcial: ${records.length} produto(s) enviado(s).');
  }

  Future<(bool, String)> uploadParcialEstoque(List<ProductRecord> records) async {
    final now = _nowBrt();
    final stmts = <Map<String, dynamic>>[];

    for (final r in records) {
      if (r.nota.isNotEmpty) {
        // Has annotation: overwrite everything
        stmts.add({
          'sql': '''
INSERT INTO estoque_mestre
  (codigo, produto, categoria, qtd_sistema, qtd_fisica, diferenca, nota, status, ultima_contagem, criado_em)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(codigo) DO UPDATE SET
  produto         = excluded.produto,
  categoria       = excluded.categoria,
  qtd_sistema     = excluded.qtd_sistema,
  qtd_fisica      = excluded.qtd_fisica,
  diferenca       = excluded.diferenca,
  nota            = excluded.nota,
  status          = excluded.status,
  ultima_contagem = excluded.ultima_contagem
''',
          'args': [
            _textArg(r.codigo),
            _textArg(r.produto),
            _textArg(r.categoria),
            _intArg(r.qtdSistema),
            _intArg(r.qtdFisica),
            _intArg(r.diferenca),
            _textArg(r.nota),
            _textArg(r.status),
            _textArg(now),
            _textArg(now),
          ],
        });
      } else {
        // No annotation: update only qtd_sistema (preserve existing divergences)
        stmts.add({
          'sql': '''
INSERT INTO estoque_mestre
  (codigo, produto, categoria, qtd_sistema, qtd_fisica, diferenca, nota, status, ultima_contagem, criado_em)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(codigo) DO UPDATE SET
  produto         = excluded.produto,
  categoria       = excluded.categoria,
  qtd_sistema     = excluded.qtd_sistema,
  qtd_fisica      = CASE WHEN status IN ('falta','sobra')
                    THEN excluded.qtd_sistema + diferenca
                    ELSE excluded.qtd_sistema END,
  diferenca       = CASE WHEN status IN ('falta','sobra') THEN diferenca ELSE 0 END,
  nota            = CASE WHEN status IN ('falta','sobra') THEN nota ELSE '' END,
  status          = CASE WHEN status IN ('falta','sobra') THEN status ELSE 'ok' END,
  ultima_contagem = excluded.ultima_contagem
''',
          'args': [
            _textArg(r.codigo),
            _textArg(r.produto),
            _textArg(r.categoria),
            _intArg(r.qtdSistema),
            _intArg(r.qtdSistema),
            _intArg(0),
            _textArg(''),
            _textArg('ok'),
            _textArg(now),
            _textArg(now),
          ],
        });
      }
    }

    final nDiv = records.where((r) => r.status != 'ok').length;
    stmts.add({
      'sql': '''
INSERT INTO historico_uploads (data, tipo, arquivo, total_produtos_lote, novos, atualizados, divergentes)
VALUES (?, ?, ?, ?, ?, ?, ?)
''',
      'args': [
        _textArg(now),
        _textArg('PARCIAL_ESTOQUE'),
        _textArg(''),
        _intArg(records.length),
        _intArg(0),
        _intArg(records.length),
        _intArg(nDiv),
      ],
    });

    return _executeBatch(stmts, '✅ Estoque parcial: ${records.length} produto(s) enviado(s).');
  }

  Future<(bool, String)> _executeBatch(
    List<Map<String, dynamic>> stmts,
    String successMsg,
  ) async {
    const chunkSize = 50;
    for (int i = 0; i < stmts.length; i += chunkSize) {
      final chunk = stmts.sublist(
          i, i + chunkSize > stmts.length ? stmts.length : i + chunkSize);
      final (ok, err) = await _pipeline(chunk);
      if (!ok) return (false, '❌ Erro: $err');
    }
    return (true, successMsg);
  }

  Future<bool> testConnection() async {
    try {
      final resp = await http.post(
        Uri.parse('$url/v2/pipeline'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'requests': [
            {
              'type': 'execute',
              'stmt': {'sql': 'SELECT 1'}
            },
            {'type': 'close'}
          ]
        }),
      );
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static String _nowBrt() {
    final now = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return '${now.year.toString().padLeft(4, '0')}'
        '-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}'
        ' ${now.hour.toString().padLeft(2, '0')}'
        ':${now.minute.toString().padLeft(2, '0')}'
        ':${now.second.toString().padLeft(2, '0')}';
  }
}
