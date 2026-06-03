import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../models/product_record.dart';

// Produto groups → canonical categoria names (mirrors Python _GRUPO_MAP)
const _grupoMap = {
  'DEFENSIVOS AGRÍCOLAS': 'DEFENSIVOS',
  'DEFENSIVO AGRICOLA': 'DEFENSIVOS',
  'DEFENSIVOS': 'DEFENSIVOS',
  'HERBICIDAS': 'DEFENSIVOS',
  'FUNGICIDAS': 'DEFENSIVOS',
  'INSETICIDAS': 'DEFENSIVOS',
  'FERTILIZANTES': 'FERTILIZANTES',
  'FERTILIZANTE': 'FERTILIZANTES',
  'NUTRIÇÃO DE PLANTAS': 'FERTILIZANTES',
  'SEMENTES': 'SEMENTES',
  'SEMENTE': 'SEMENTES',
  'INOCULANTES': 'INOCULANTES',
  'ADJUVANTES': 'ADJUVANTES',
  'ADJUVANTE': 'ADJUVANTES',
  'EQUIPAMENTOS': 'EQUIPAMENTOS',
  'EPI': 'EPI',
  'EPIs': 'EPI',
};

const _defensivosKeywords = [
  'herbic',
  'fungic',
  'insetic',
  'nematic',
  'acaric',
  'mollus',
  'rodent',
  'feromô',
  'adjuv',
];

const _fertilizantesKeywords = ['fertil', 'adubo', 'nutrição', 'npk', 'kali'];
const _sementesKeywords = ['sement', 'seed', 'cultivar'];

String _classifyProduct(String nome) {
  final n = nome.toLowerCase();
  if (_defensivosKeywords.any((k) => n.contains(k))) return 'DEFENSIVOS';
  if (_fertilizantesKeywords.any((k) => n.contains(k))) return 'FERTILIZANTES';
  if (_sementesKeywords.any((k) => n.contains(k))) return 'SEMENTES';
  return 'OUTROS';
}

String _normalizeGrupo(String grupo) {
  final up = grupo.toUpperCase().trim();
  return _grupoMap[up] ?? _classifyProduct(grupo);
}

// Parse annotation like "falta 5 obs" or "sobra 3" → (qtdFisica, diferenca, obs, status)
(int, int, String, String) _parseAnnotation(String nota, int qtdSistema) {
  if (nota.isEmpty) return (qtdSistema, 0, '', 'ok');

  final t = nota.trim().toLowerCase();
  // falta N
  final faltaRe = RegExp(r'^falta\s+(\d+)\s*(.*)$');
  var m = faltaRe.firstMatch(t);
  if (m != null) {
    final f = int.parse(m.group(1)!);
    return (qtdSistema - f, -f, m.group(2)!.trim(), 'falta');
  }
  // sobra N
  final sobraRe = RegExp(r'^sobra\s+(\d+)\s*(.*)$');
  m = sobraRe.firstMatch(t);
  if (m != null) {
    final s = int.parse(m.group(1)!);
    return (qtdSistema + s, s, m.group(2)!.trim(), 'sobra');
  }
  // -N
  final negRe = RegExp(r'^-(\d+)');
  m = negRe.firstMatch(t);
  if (m != null) {
    final f = int.parse(m.group(1)!);
    return (qtdSistema - f, -f, nota, 'falta');
  }
  // +N
  final posRe = RegExp(r'^\+(\d+)');
  m = posRe.firstMatch(t);
  if (m != null) {
    final s = int.parse(m.group(1)!);
    return (qtdSistema + s, s, nota, 'sobra');
  }
  return (qtdSistema, 0, nota, 'ok');
}

String _str(Data? cell) => cell?.value?.toString().trim() ?? '';

List<List<String>> _toRaw(Sheet sheet) {
  return sheet.rows
      .map((row) => row.map((c) => _str(c)).toList())
      .toList();
}

String _detectFormat(List<List<String>> rows) {
  for (int i = 0; i < rows.length && i < 10; i++) {
    final joined = rows[i].join(' ').toUpperCase();
    if (joined.contains('QTDD - VENDIDA') ||
        joined.contains('QTDD ESTOQUE') ||
        joined.contains('GRUPO DE PRODUTO')) {
      return 'vendas';
    }
    final up = rows[i].map((v) => v.toUpperCase()).toList();
    if (up.contains('PRODUTO') &&
        up.any((v) => v.contains('QUANTIDADE') || v == 'QTD')) {
      return 'estoque';
    }
  }
  return 'desconhecido';
}

int? _findHeader(List<List<String>> rows, bool Function(List<String>) check) {
  for (int i = 0; i < rows.length && i < 15; i++) {
    if (check(rows[i].map((v) => v.toUpperCase()).toList())) return i;
  }
  return null;
}

String _autoCode(String produto) {
  final clean = produto.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return 'AUTO_${clean.substring(0, clean.length < 20 ? clean.length : 20)}';
}

ParseResult _parseVendas(List<List<String>> rows) {
  final hIdx = _findHeader(
    rows,
    (vals) =>
        vals.contains('PRODUTO') &&
        (vals.join(' ').contains('QTDD') || vals.join(' ').contains('VENDIDA')),
  );
  if (hIdx == null) {
    return const ParseResult(
        ok: false, error: 'Cabeçalho não encontrado no formato vendas.');
  }

  final headers = rows[hIdx].map((v) => v.toUpperCase()).toList();
  int? colGrupo, colProduto, colVendida, colEstoque, colNota;
  for (int i = 0; i < headers.length; i++) {
    final h = headers[i];
    if (h.contains('GRUPO') && colGrupo == null) colGrupo = i;
    if (h == 'PRODUTO' && colProduto == null) colProduto = i;
    if (h.contains('VENDIDA') && colVendida == null) colVendida = i;
    if (h.contains('ESTOQUE') && colEstoque == null) colEstoque = i;
    if ((h.contains('OBS') || h.contains('NOTA') || h.contains('ANOTA')) &&
        colNota == null) colNota = i;
  }

  if (colProduto == null) {
    return const ParseResult(
        ok: false, error: "Coluna 'PRODUTO' não encontrada.");
  }

  final records = <ProductRecord>[];
  final zerados = <Map<String, dynamic>>[];
  var currentGrupo = 'OUTROS';
  // code-product regex: starts with digits
  final codProdRe = RegExp(r'^(\d[\d./-]*)\s+(.+)$');

  for (int i = hIdx + 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length <= colProduto!) continue;

    if (colGrupo != null && colGrupo < row.length) {
      final g = row[colGrupo].trim();
      if (g.isNotEmpty && g.toUpperCase() != 'NAN') currentGrupo = g;
    }

    final rawProd = row[colProduto].trim();
    if (rawProd.isEmpty ||
        ['NAN', 'NONE', 'ROLLUP'].contains(rawProd.toUpperCase())) continue;

    String codigo, produto;
    final m = codProdRe.firstMatch(rawProd);
    if (m != null) {
      codigo = m.group(1)!.trim();
      produto = m.group(2)!.trim();
    } else {
      codigo = _autoCode(rawProd);
      produto = rawProd;
    }

    int qtdSistema = 0, qtdVendida = 0;
    if (colEstoque != null && colEstoque < row.length) {
      qtdSistema = int.tryParse(row[colEstoque].replaceAll(',', '.').split('.').first) ?? 0;
    }
    if (colVendida != null && colVendida < row.length) {
      qtdVendida = int.tryParse(row[colVendida].replaceAll(',', '.').split('.').first) ?? 0;
    }

    if (qtdSistema <= 0) {
      if (qtdVendida > 0) {
        zerados.add({
          'codigo': codigo,
          'produto': produto,
          'grupo': _normalizeGrupo(currentGrupo),
          'qtd_vendida': qtdVendida,
          'qtd_estoque': 0,
        });
      }
      continue;
    }

    String notaRaw = '';
    if (colNota != null && colNota < row.length) {
      final nv = row[colNota].trim();
      if (nv.toUpperCase() != 'NAN' && nv.isNotEmpty && !RegExp(r'^\d+$').hasMatch(nv)) {
        notaRaw = nv;
      }
    }

    String categoria = _normalizeGrupo(currentGrupo);
    if (categoria == 'OUTROS' || categoria.isEmpty) {
      categoria = _classifyProduct(produto);
    }

    final (qtdFisica, diferenca, obs, status) = _parseAnnotation(notaRaw, qtdSistema);

    records.add(ProductRecord(
      codigo: codigo,
      produto: produto,
      categoria: categoria,
      qtdSistema: qtdSistema,
      qtdFisica: qtdFisica,
      diferenca: diferenca,
      nota: obs,
      status: status,
      qtdVendida: qtdVendida,
    ));
  }

  if (records.isEmpty) {
    return const ParseResult(
        ok: false, error: 'Nenhum dado válido na planilha de vendas.');
  }
  return ParseResult(ok: true, records: records, zerados: zerados);
}

ParseResult _parseEstoque(List<List<String>> rows) {
  final hIdx = _findHeader(
    rows,
    (vals) =>
        vals.contains('PRODUTO') &&
        vals.any((v) => v.contains('QUANTIDADE') || v == 'QTD'),
  );
  if (hIdx == null) {
    return const ParseResult(
        ok: false,
        error: "Cabeçalho não encontrado. Preciso de 'Produto' e 'Quantidade'.");
  }

  final headers = rows[hIdx].map((v) => v.toUpperCase()).toList();
  int? colCodigo, colProduto, colQtd, colNota;
  for (int i = 0; i < headers.length; i++) {
    final h = headers[i];
    if ((h == 'CÓDIGO' || h == 'CODIGO' || h == 'COD') && colCodigo == null) colCodigo = i;
    if (h == 'PRODUTO' && colProduto == null) colProduto = i;
    if ((h.contains('QUANTIDADE') || h == 'QTD') && colQtd == null) colQtd = i;
    if ((h.contains('OBS') || h.contains('NOTA') || h.contains('DIFEREN') || h.contains('ANOTA')) &&
        colNota == null) colNota = i;
  }

  if (colProduto == null || colQtd == null) {
    return const ParseResult(
        ok: false, error: "Falta coluna 'Produto' ou 'Quantidade'.");
  }

  final records = <ProductRecord>[];
  for (int i = hIdx + 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length <= colProduto!) continue;

    final produto = row[colProduto].trim();
    if (produto.isEmpty ||
        ['NAN', 'NONE', 'TOTAL', 'PRODUTO', 'ROLLUP'].contains(produto.toUpperCase())) {
      continue;
    }

    if (colQtd! >= row.length) continue;
    final qtdStr = row[colQtd].replaceAll(',', '.').split('.').first;
    final qtdSistema = int.tryParse(qtdStr) ?? -1;
    if (qtdSistema <= 0) continue;

    String codigo = '';
    if (colCodigo != null && colCodigo < row.length) {
      codigo = row[colCodigo].trim();
      if (codigo.toUpperCase() == 'NAN') codigo = '';
    }
    if (codigo.isEmpty) codigo = _autoCode(produto);

    String notaRaw = '';
    if (colNota != null && colNota < row.length) {
      final nv = row[colNota].trim();
      if (nv.toUpperCase() != 'NAN' && nv.isNotEmpty && !RegExp(r'^\d+$').hasMatch(nv)) {
        notaRaw = nv;
      }
    }

    final categoria = _classifyProduct(produto);
    final (qtdFisica, diferenca, obs, status) = _parseAnnotation(notaRaw, qtdSistema);

    records.add(ProductRecord(
      codigo: codigo,
      produto: produto,
      categoria: categoria,
      qtdSistema: qtdSistema,
      qtdFisica: qtdFisica,
      diferenca: diferenca,
      nota: obs,
      status: status,
    ));
  }

  if (records.isEmpty) {
    return const ParseResult(
        ok: false, error: 'Nenhum dado válido na planilha de estoque.');
  }
  return ParseResult(ok: true, records: records);
}

ParseResult _parseParcialEstoque(List<List<String>> rows) {
  final hIdx = _findHeader(
    rows,
    (vals) =>
        vals.contains('PRODUTO') && vals.any((v) => v.contains('QUANTIDADE')),
  );
  if (hIdx == null) {
    return const ParseResult(
        ok: false,
        error: "Cabeçalho não encontrado. Preciso de 'Produto' e 'QUANTIDADE'.");
  }

  final headers = rows[hIdx].map((v) => v.toUpperCase()).toList();
  int? colCodigo, colProduto, colQtd, colNota;
  for (int i = 0; i < headers.length; i++) {
    final h = headers[i];
    if ((h == 'CÓDIGO' || h == 'CODIGO' || h == 'COD') && colCodigo == null) colCodigo = i;
    if (h == 'PRODUTO' && colProduto == null) colProduto = i;
    if (h.contains('QUANTIDADE') && colQtd == null) colQtd = i;
    if (h.contains('CUSTO') && colNota == null) colNota = i;
  }

  if (colProduto == null || colQtd == null) {
    return const ParseResult(
        ok: false, error: "Falta coluna 'Produto' ou 'QUANTIDADE'.");
  }

  final records = <ProductRecord>[];
  for (int i = hIdx + 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length <= colProduto!) continue;

    final produto = row[colProduto].trim();
    if (produto.isEmpty ||
        ['NAN', 'NONE', 'SUM', 'ROLLUP', 'TOTAL', 'PRODUTO'].contains(produto.toUpperCase())) {
      continue;
    }

    if (colQtd! >= row.length) continue;
    final qtdStr = row[colQtd].replaceAll(',', '.').split('.').first;
    final qtdSistema = int.tryParse(qtdStr) ?? -1;
    if (qtdSistema < 0) continue;

    String codigo = '';
    if (colCodigo != null && colCodigo < row.length) {
      codigo = row[colCodigo].trim();
      if (codigo.toUpperCase() == 'NAN') codigo = '';
    }
    if (codigo.isEmpty) codigo = _autoCode(produto);

    String notaRaw = '';
    if (colNota != null && colNota < row.length) {
      final nv = row[colNota].trim();
      if (nv.toUpperCase() != 'NAN' && nv.isNotEmpty && !RegExp(r'^\d+$').hasMatch(nv)) {
        notaRaw = nv;
      }
    }

    final categoria = _classifyProduct(produto);
    final (qtdFisica, diferenca, obs, status) = _parseAnnotation(notaRaw, qtdSistema);

    records.add(ProductRecord(
      codigo: codigo,
      produto: produto,
      categoria: categoria,
      qtdSistema: qtdSistema,
      qtdFisica: qtdFisica,
      diferenca: diferenca,
      nota: obs,
      status: status,
    ));
  }

  if (records.isEmpty) {
    return const ParseResult(
        ok: false, error: 'Nenhum dado válido na planilha de estoque parcial.');
  }
  return ParseResult(ok: true, records: records);
}

class ExcelParser {
  /// [isVendas] true = modo VENDAS, false = modo ESTOQUE PARCIAL
  static ParseResult parse(Uint8List bytes, {required bool isVendas}) {
    try {
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) {
        return const ParseResult(ok: false, error: 'Planilha vazia ou formato inválido.');
      }
      final sheet = excel.tables.values.first;
      final raw = _toRaw(sheet);

      if (isVendas) {
        final fmt = _detectFormat(raw);
        if (fmt == 'estoque') return _parseEstoque(raw);
        final result = _parseVendas(raw);
        if (!result.ok) return _parseEstoque(raw);
        return result;
      } else {
        return _parseParcialEstoque(raw);
      }
    } catch (e) {
      return ParseResult(ok: false, error: 'Erro ao ler arquivo: $e');
    }
  }
}
