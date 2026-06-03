import 'package:flutter/material.dart';
import '../config.dart';
import 'upload_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isCloud = false;

  @override
  void initState() {
    super.initState();
    Config.isConfigured().then((ok) => setState(() => _isCloud = ok));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
        title: const Text(
          'CAMDA · UPLOAD',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              final ok = await Config.isConfigured();
              setState(() => _isCloud = ok);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _isCloud
                      ? const Color(0xFF14532d)
                      : const Color(0xFF78350f),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isCloud
                      ? '☁️ CONECTADO AO TURSO · sincroniza com o dashboard'
                      : '⚠️ MODO LOCAL · configure as credenciais em ⚙️',
                  style: TextStyle(
                    color: _isCloud
                        ? const Color(0xFF86efac)
                        : const Color(0xFFfde68a),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            const SizedBox(height: 40),

            // VENDAS button
            Expanded(
              child: _BigButton(
                label: '📈\nVENDAS',
                subtitle: 'Atualiza estoque\n+ histórico de vendas',
                color: const Color(0xFF1d4ed8),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const UploadScreen(isVendas: true)),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ESTOQUE PARCIAL button
            Expanded(
              child: _BigButton(
                label: '📦\nESTOQUE PARCIAL',
                subtitle: 'Atualiza apenas as\nquantidades da planilha',
                color: const Color(0xFF065f46),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const UploadScreen(isVendas: false)),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _BigButton({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
