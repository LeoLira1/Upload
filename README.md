# CAMDA · Upload

App web minimalista (Streamlit) com **dois botões grandes** para enviar planilhas
que sincronizam automaticamente com o
[dashboard CAMDA](https://github.com/LeoLira1/camda-estoque):

| Botão | O que faz |
|-------|-----------|
| 📈 **VENDAS** | Atualiza a quantidade dos produtos **e** registra o histórico de vendas (alimenta reposição, variações etc. no dashboard). |
| 📦 **ESTOQUE PARCIAL** | Atualiza **apenas** a quantidade dos produtos presentes na planilha. Não mexe em vendas. |

## Como sincroniza com o dashboard

O app grava no **mesmo banco Turso** que o dashboard lê. Para garantir comportamento
**idêntico** ao upload feito dentro do dashboard, ele reaproveita a própria lógica
de importação do dashboard, sem reescrevê-la:

- `camda_core.py` é **gerado automaticamente** a partir do `app_turso.py` do
  dashboard (via `generate_core.py`). Ele contém só as definições de backend
  (conexão, parsers de planilha e funções de gravação) — sem a camada de UI.
- `db_mapa.py`, `mapa_3d_component.py`, `mural_tab.py` e
  `inventario_ciclico_tab.py` são os módulos irmãos que o backend importa.

Assim, vendas e estoque enviados aqui aparecem no dashboard automaticamente.

### Atualizar o backend quando o dashboard mudar

```bash
# baixe a versão mais recente do dashboard e regenere o camda_core.py
curl -sSL https://raw.githubusercontent.com/LeoLira1/camda-estoque/refs/heads/main/app_turso.py -o /tmp/dash.py
# (ajuste o caminho SRC no topo do script, se necessário)
python3 generate_core.py
```

## Configuração

Crie `.streamlit/secrets.toml` (use `.streamlit/secrets.toml.example` como base)
com as credenciais do **mesmo** banco Turso do dashboard:

```toml
TURSO_DATABASE_URL = "libsql://SEU-BANCO.turso.io"
TURSO_AUTH_TOKEN   = "SEU_TOKEN_AQUI"
```

Sem essas credenciais o app roda em **modo local** (`camda_local.db`) e **não**
sincroniza com o dashboard — útil só para testes.

## Rodar localmente

```bash
pip install -r requirements.txt
streamlit run app.py
```

## Publicar (Streamlit Community Cloud)

1. Faça push deste repositório para o GitHub.
2. Em https://share.streamlit.io, aponte para `app.py`.
3. Em **Settings → Secrets**, cole `TURSO_DATABASE_URL` e `TURSO_AUTH_TOKEN`.

## Formatos de planilha aceitos

- **Vendas**: relatório do TOTVS BI com colunas como `GRUPO DE PRODUTO`,
  `PRODUTO`, `QTDD - VENDIDA`, `QTDD ESTOQUE` (cabeçalho pode não estar na 1ª linha).
- **Estoque parcial**: colunas `CÓDIGO`, `PRODUTO`, `QUANTIDADE` (e opcionalmente `CUSTO`).

São exatamente os mesmos formatos que o dashboard já entende.
