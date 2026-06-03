class ProductRecord {
  final String codigo;
  final String produto;
  final String categoria;
  final int qtdSistema;
  final int qtdFisica;
  final int diferenca;
  final String nota;
  final String status;
  final int qtdVendida;

  const ProductRecord({
    required this.codigo,
    required this.produto,
    required this.categoria,
    required this.qtdSistema,
    required this.qtdFisica,
    required this.diferenca,
    required this.nota,
    required this.status,
    this.qtdVendida = 0,
  });

  Map<String, dynamic> toMap() => {
        'codigo': codigo,
        'produto': produto,
        'categoria': categoria,
        'qtd_sistema': qtdSistema,
        'qtd_fisica': qtdFisica,
        'diferenca': diferenca,
        'nota': nota,
        'status': status,
        'qtd_vendida': qtdVendida,
      };
}

class ParseResult {
  final bool ok;
  final List<ProductRecord> records;
  final List<Map<String, dynamic>> zerados;
  final String? error;

  const ParseResult({
    required this.ok,
    this.records = const [],
    this.zerados = const [],
    this.error,
  });
}
