"""Gera camda_core.py a partir do app_turso.py do dashboard, mantendo APENAS
as definicoes (imports, funcoes, classes, constantes) e descartando toda a
execucao de UI no nivel do modulo. Assim o app de upload reaproveita a logica
de gravacao no banco identica a do dashboard, sem efeitos colaterais de UI."""
import ast
import os
import sys

# Caminho do app_turso.py do dashboard (baixe antes de rodar). Pode passar via argv.
SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/dash.py"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "camda_core.py")

src = open(SRC, encoding="utf-8").read()
lines = src.splitlines(keepends=True)
tree = ast.parse(src)

KEEP_TYPES = (ast.Import, ast.ImportFrom, ast.FunctionDef,
              ast.AsyncFunctionDef, ast.ClassDef, ast.Try)

# Limite: assigns de constantes ficam na regiao de definicoes (< 7000).
# Assigns na regiao de UI (>= 7000) sao estado de tela e devem cair.
UI_REGION = 7000

kept_segments = []
dropped = []

def node_start(node):
    if getattr(node, "decorator_list", None):
        return min(d.lineno for d in node.decorator_list)
    return node.lineno

for node in tree.body:
    keep = False
    if isinstance(node, KEEP_TYPES):
        keep = True
    elif isinstance(node, (ast.Assign, ast.AnnAssign)):
        keep = node.lineno < UI_REGION
    if keep:
        start = node_start(node)
        end = node.end_lineno
        kept_segments.append((start, end))
    else:
        first = lines[node.lineno - 1].strip()
        dropped.append((type(node).__name__, node.lineno, first[:80]))

# Emite os segmentos mantidos preservando o texto original (comentarios/format).
kept_segments.sort()
header = (
    '"""camda_core.py — GERADO automaticamente a partir do app_turso.py do '
    'dashboard CAMDA.\n\n'
    'Contem APENAS as definicoes de backend (conexao Turso, parsers de planilha\n'
    'e funcoes de gravacao) extraidas verbatim do dashboard, sem a camada de UI.\n'
    'O app de upload importa este modulo para gravar no MESMO banco com a MESMA\n'
    'logica do dashboard. Para atualizar, rode generate_core.py sobre a versao\n'
    'mais recente do app_turso.py.\n'
    '"""\n'
)
out = [header]
prev_end = 0
for start, end in kept_segments:
    out.append("".join(lines[start - 1:end]))
    out.append("\n\n")

open(OUT, "w", encoding="utf-8").write("".join(out))

print(f"KEPT {len(kept_segments)} top-level definitions")
print(f"DROPPED {len(dropped)} top-level statements:")
for t, ln, txt in dropped:
    print(f"  L{ln:<6} {t:<12} {txt}")
