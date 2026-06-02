"""
CAMDA · Upload
==============
App minimalista com dois botões grandes para enviar planilhas:

  📈 VENDAS            → atualiza estoque + histórico de vendas
  📦 ESTOQUE PARCIAL   → atualiza apenas a quantidade dos produtos da planilha

Grava no MESMO banco Turso usado pelo dashboard, reaproveitando exatamente a
mesma lógica de importação (módulo camda_core, extraído do dashboard). Assim os
dados aparecem no dashboard automaticamente.

Configure as credenciais do Turso em .streamlit/secrets.toml (ou variáveis de
ambiente) para sincronizar com o dashboard:

    TURSO_DATABASE_URL = "libsql://..."
    TURSO_AUTH_TOKEN   = "..."

Sem essas credenciais o app roda em modo LOCAL (banco camda_local.db) e NÃO
sincroniza com o dashboard.
"""
from datetime import datetime

import pandas as pd
import streamlit as st

import camda_core as core

st.set_page_config(page_title="CAMDA · Upload", page_icon="📤", layout="centered")

# ──────────────────────────────────────────────────────────────────────────────
# Estilo — botões grandes, layout para celular
# ──────────────────────────────────────────────────────────────────────────────
st.markdown(
    """
    <style>
      .block-container { padding-top: 2rem; max-width: 540px; }
      /* Botões grandes da tela inicial */
      div[data-testid="stButton"] > button {
          height: 7rem;
          font-size: 1.7rem;
          font-weight: 800;
          border-radius: 18px;
          border: 3px solid #1e293b;
          line-height: 1.2;
      }
      div[data-testid="stButton"] > button:hover {
          border-color: #2563eb;
          color: #2563eb;
      }
      .titulo { text-align:center; font-size:2rem; font-weight:900;
                letter-spacing:1px; margin-bottom:.2rem; }
      .badge  { text-align:center; font-size:.8rem; font-weight:700;
                padding:.35rem; border-radius:8px; margin-bottom:1.2rem; }
      .badge-cloud { background:#dcfce7; color:#166534; }
      .badge-local { background:#fef9c3; color:#854d0e; }
    </style>
    """,
    unsafe_allow_html=True,
)


def _badge():
    if core._using_cloud:
        st.markdown(
            '<div class="badge badge-cloud">☁️ CONECTADO AO TURSO · '
            "sincroniza com o dashboard</div>",
            unsafe_allow_html=True,
        )
    else:
        st.markdown(
            '<div class="badge badge-local">⚠️ MODO LOCAL · sem credenciais do '
            "Turso, não sincroniza com o dashboard</div>",
            unsafe_allow_html=True,
        )


def _rack_sync_best_effort():
    """Atualiza o mapa do rack após o upload (igual ao dashboard, sem travar)."""
    try:
        core.sync_quantidades_from_estoque(core.get_db())
    except Exception:
        pass


def _voltar():
    for k in ("modo", "parsed", "file_id"):
        st.session_state.pop(k, None)
    st.rerun()


# ──────────────────────────────────────────────────────────────────────────────
# Estado
# ──────────────────────────────────────────────────────────────────────────────
if "modo" not in st.session_state:
    st.session_state.modo = None

st.markdown('<div class="titulo">CAMDA · UPLOAD</div>', unsafe_allow_html=True)
_badge()


# ──────────────────────────────────────────────────────────────────────────────
# Tela inicial — dois botões grandes
# ──────────────────────────────────────────────────────────────────────────────
if st.session_state.modo is None:
    if st.button("📈 VENDAS", use_container_width=True, key="btn_vendas"):
        st.session_state.modo = "vendas"
        st.rerun()
    st.write("")
    if st.button("📦 ESTOQUE PARCIAL", use_container_width=True, key="btn_parcial"):
        st.session_state.modo = "parcial"
        st.rerun()
    st.stop()


# ──────────────────────────────────────────────────────────────────────────────
# Tela de upload (comum aos dois modos)
# ──────────────────────────────────────────────────────────────────────────────
is_vendas = st.session_state.modo == "vendas"

if is_vendas:
    st.subheader("📈 Planilha de Vendas")
    st.caption(
        "Atualiza a quantidade dos produtos e registra o histórico de vendas. "
        "Os produtos fora da planilha permanecem inalterados."
    )
    data_planilha = st.date_input(
        "📅 Data da planilha",
        value=datetime.now(tz=core._BRT).date(),
        max_value=datetime.now(tz=core._BRT).date(),
        help="Data a que esta planilha se refere. Use para planilhas de dias anteriores.",
    )
else:
    st.subheader("📦 Estoque Parcial")
    st.caption(
        "Atualiza apenas a quantidade dos produtos presentes na planilha. "
        "Não mexe em vendas, observações nem reposição."
    )

uploaded = st.file_uploader(
    "Planilha XLSX", type=["xlsx", "xls"], label_visibility="collapsed", key="uploader"
)

if uploaded:
    file_id = f"{uploaded.name}_{uploaded.size}_{st.session_state.modo}"
    if st.session_state.get("file_id") != file_id:
        # Parseia uma única vez e guarda
        try:
            if is_vendas:
                ok, result, zerados = core.read_excel_to_records(uploaded)
            else:
                df_raw = pd.read_excel(uploaded, sheet_name=0, header=None)
                ok, result = core.parse_parcial_estoque(df_raw)
                zerados = []
        except Exception as e:
            ok, result, zerados = False, f"Erro ao ler arquivo: {e}", []
        st.session_state.parsed = (ok, result, zerados)
        st.session_state.file_id = file_id

    ok, result, zerados = st.session_state.parsed

    if not ok:
        st.error(result)
    else:
        records = result
        n_div = sum(1 for r in records if r["status"] != "ok")

        st.success(f"✅ {len(records)} produto(s) lido(s) na planilha.")
        if n_div:
            st.warning(f"⚠️ {n_div} divergência(s) detectada(s).")
        if zerados:
            st.info(f"🗑️ {len(zerados)} produto(s) com estoque zerado serão removidos do mestre.")

        with st.expander("👁️ Pré-visualizar dados"):
            cols = ["codigo", "produto", "categoria", "qtd_sistema",
                    "qtd_fisica", "diferenca", "nota", "status"]
            st.dataframe(
                pd.DataFrame(records)[cols],
                hide_index=True, use_container_width=True, height=280,
            )

        if st.button("🚀 ENVIAR", type="primary", use_container_width=True):
            with st.spinner("Enviando..."):
                if is_vendas:
                    up_ok, msg = core.upload_parcial(records, zerados)
                    if up_ok:
                        try:
                            core.save_vendas_historico(
                                records, core._GRUPO_MAP, zerados,
                                is_mestre=False, data_ref=data_planilha.isoformat(),
                            )
                        except Exception as e:
                            st.warning(f"Histórico de vendas não salvo: {e}")
                else:
                    up_ok, msg = core.upload_parcial_estoque(records)

                if up_ok:
                    _rack_sync_best_effort()

            if up_ok:
                st.session_state.pop("parsed", None)
                st.session_state.pop("file_id", None)
                extra = " · ☁️ Sincronizado com o dashboard." if core._using_cloud else ""
                st.success(msg + extra)
                st.balloons()
            else:
                st.error(msg)

st.write("")
if st.button("⬅️ Voltar", use_container_width=True):
    _voltar()
