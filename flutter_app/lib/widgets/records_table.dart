import 'package:flutter/material.dart';
import '../models/product_record.dart';

class RecordsTable extends StatelessWidget {
  final List<ProductRecord> records;

  const RecordsTable({super.key, required this.records});

  Color _statusColor(String status) {
    switch (status) {
      case 'falta':
        return const Color(0xFFef4444);
      case 'sobra':
        return const Color(0xFFf59e0b);
      default:
        return const Color(0xFF22c55e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF1e293b)),
          dataRowColor: WidgetStateProperty.resolveWith((states) =>
              const Color(0xFF0f172a)),
          border: TableBorder.all(color: Colors.white12),
          columnSpacing: 12,
          headingTextStyle: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 11),
          dataTextStyle: const TextStyle(color: Colors.white, fontSize: 11),
          columns: const [
            DataColumn(label: Text('Código')),
            DataColumn(label: Text('Produto')),
            DataColumn(label: Text('Cat.')),
            DataColumn(label: Text('Sist.'), numeric: true),
            DataColumn(label: Text('Fís.'), numeric: true),
            DataColumn(label: Text('Dif.'), numeric: true),
            DataColumn(label: Text('Status')),
          ],
          rows: records.map((r) {
            return DataRow(cells: [
              DataCell(Text(r.codigo,
                  style: const TextStyle(fontSize: 10, color: Colors.white54))),
              DataCell(
                SizedBox(
                  width: 160,
                  child: Text(r.produto,
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                ),
              ),
              DataCell(Text(r.categoria,
                  style: const TextStyle(fontSize: 10))),
              DataCell(Text(r.qtdSistema.toString())),
              DataCell(Text(r.qtdFisica.toString())),
              DataCell(Text(
                r.diferenca == 0
                    ? '—'
                    : (r.diferenca > 0 ? '+${r.diferenca}' : '${r.diferenca}'),
                style: TextStyle(
                  color: r.diferenca == 0
                      ? Colors.white54
                      : r.diferenca < 0
                          ? const Color(0xFFef4444)
                          : const Color(0xFFf59e0b),
                  fontWeight: FontWeight.bold,
                ),
              )),
              DataCell(
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor(r.status).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: _statusColor(r.status).withOpacity(0.5)),
                  ),
                  child: Text(
                    r.status,
                    style: TextStyle(
                        color: _statusColor(r.status),
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
