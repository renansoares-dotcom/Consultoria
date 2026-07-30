// ============================================================================
// DATATIVO DESIGN FRAMEWORK — BIBLIOTECA OFICIAL DE COMPONENTES (SYS-002)
//
// Todo componente aqui é puro: recebe dado + configuração, desenha HTML.
// Nenhum componente busca dado sozinho (sem chamada a Supabase aqui dentro)
// — quem chama decide de onde o dado vem (regra fixa, IA futura, o que for).
// Isso é o que já vínhamos fazendo espalhado em cada dashboard (Financeiro,
// Comercial) — este arquivo é a extração formal disso num lugar só, pra
// nunca mais duplicar a mesma função em dois arquivos (como já aconteceu:
// renderDonut, renderBarList, abrirDrilldown existiam copiados e colados
// entre Financeiro e Comercial antes deste arquivo existir).
//
// Requer que a página já tenha carregado css/design-system.css e
// css/dashboard-framework.css (ADR-004) — os componentes aqui usam as
// classes desses dois arquivos, não redefinem estilo nenhum.
//
// Uso: import { AttentionCenter, KPICard, ... } from '../../js/dtv-components.js';
// ============================================================================

export const CORES_SERIE = ['#1f7a5c', '#2f9e9e', '#b76e11', '#5b7fdb', '#8a63d2', '#c0392b', '#94a3b8'];

export function fmtMoeda(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2 });
}

function icones() { if (window.lucide) lucide.createIcons(); }

// ============================================================================
// 01. EXECUTIVE HEADER
// ExecutiveHeader(containerId, { titulo, breadcrumb, buscaPlaceholder,
//   onBusca, acoesRapidas: [{label, icone, href, onClick}], favoritoAtivo, onFavoritar })
// ============================================================================
export function ExecutiveHeader(containerId, opts) {
  const cont = document.getElementById(containerId);
  cont.innerHTML = `
    <div class="page-header">
      <div>
        <span class="eyebrow">${opts.breadcrumb || ''}</span>
        <h1>${opts.titulo}</h1>
      </div>
      <div class="dtv-cabecalho-executivo">
        ${(opts.onBusca || opts.buscaGlobal) ? `
        <div class="dtv-busca-global">
          <i data-lucide="search"></i>
          <input class="input" type="search" id="${containerId}-busca" placeholder="${opts.buscaPlaceholder || 'Buscar...'}">
          <div class="dtv-busca-dropdown" id="${containerId}-busca-dropdown"></div>
        </div>` : ''}
        ${opts.onFavoritar ? `<button type="button" class="dtv-favoritos-btn${opts.favoritoAtivo ? ' ativo' : ''}" id="${containerId}-favorito" title="Favoritar"><i data-lucide="star"></i></button>` : ''}
        <div class="dtv-acoes-rapidas">
          ${(opts.acoesRapidas || []).map((a, i) => `<a href="${a.href || '#'}" class="btn ${a.primario ? 'primary' : 'ghost'}" data-acao-idx="${i}">${a.icone ? `<i data-lucide="${a.icone}"></i> ` : ''}${a.label}</a>`).join('')}
        </div>
      </div>
    </div>`;
  if (opts.onBusca) document.getElementById(`${containerId}-busca`).addEventListener('input', (e) => opts.onBusca(e.target.value));
  if (opts.onFavoritar) document.getElementById(`${containerId}-favorito`).addEventListener('click', opts.onFavoritar);
  (opts.acoesRapidas || []).forEach((a, i) => {
    if (!a.onClick) return;
    const el = cont.querySelector(`[data-acao-idx="${i}"]`);
    el.addEventListener('click', (e) => { e.preventDefault(); a.onClick(); });
  });
  icones();
}

// ============================================================================
// 02. ATTENTION CENTER
// AttentionCenter(containerId, alertas: [{ tipo, prioridade: 'alta'|'media'|'baixa',
//   icone, mensagem, acaoSugerida, link }])
// ============================================================================
export function AttentionCenter(containerId, alertas) {
  const cont = document.getElementById(containerId);
  if (!alertas || !alertas.length) { EmptyState(containerId, 'Nenhum alerta no momento.'); return; }
  cont.innerHTML = alertas.map(a => `
    <div class="ca-item prioridade-${a.prioridade}">
      <div class="ca-icone"><i data-lucide="${a.icone}"></i></div>
      <div class="ca-corpo">
        <span class="ca-tipo">${a.tipo}</span>
        <div class="ca-mensagem">${a.mensagem}</div>
        ${a.acaoSugerida ? `<div class="ca-acao"><a href="${a.link || '#'}">${a.acaoSugerida} →</a></div>` : ''}
      </div>
    </div>`).join('');
  icones();
}

// ============================================================================
// 03. INSIGHT CARD
// InsightCard(insight: { categoria, texto, tendencia?, grauConfianca?, origem })
// -> retorna o HTML de UM card (uso: montar grid com .map(InsightCard).join(''))
// InsightGrid(containerId, insights) -> desenha o grid inteiro direto
// ============================================================================
export function InsightCard(ins) {
  const seta = ins.tendencia && ins.tendencia !== 'neutra' ? `<span class="in-seta ${ins.tendencia}">${ins.tendencia === 'alta' ? '▲' : '▼'}</span> ` : '';
  const confianca = ins.grauConfianca != null ? `
    <div class="in-confianca" style="display:flex; align-items:center; gap:6px; margin-top:8px;">
      <div class="in-confianca-trilho" style="flex:1; height:4px; border-radius:999px; background:var(--paper); overflow:hidden;"><div style="height:100%; width:${ins.grauConfianca}%; background:var(--accent); border-radius:999px;"></div></div>
      <span style="font-size:10px; font-weight:600; color:var(--ink-faint); white-space:nowrap;">${ins.grauConfianca}%</span>
    </div>` : '';
  return `
    <div class="insight-card">
      <div class="in-topo"><span class="in-categoria">${ins.categoria}</span><span class="in-origem${ins.origem === 'IA' ? ' origem-ia' : ''}">${ins.origem}</span></div>
      <div class="in-texto">${seta}${ins.texto}</div>
      ${confianca}
    </div>`;
}
export function InsightGrid(containerId, insights) {
  const cont = document.getElementById(containerId);
  if (!insights || !insights.length) { EmptyState(containerId, 'Sem insights no momento.'); return; }
  cont.innerHTML = insights.map(InsightCard).join('');
}

// ============================================================================
// 04. KPI CARD / 13. METRIC CARD
// KPICard(opts: { id, nome, icone, tom, valorTexto, clicavel }) -> HTML de 1 card
// MetricCard(opts: { nome, valorTexto }) -> versão simples, sem ícone, não clicável
// KPIGrid(containerId, listaDeKPICard, onClickKpi?) -> desenha o grid + liga clique/ripple
// ============================================================================
export function KPICard(k) {
  return `
    <div class="card kpi-card${k.clicavel ? ' kpi-clicavel' : ''}"${k.id ? ` data-kpi="${k.id}"` : ''}>
      <div class="label">${k.icone ? `<i data-lucide="${k.icone}" class="kpi-icone ${k.tom || 'tom-verde'}"></i> ` : ''}${k.nome}</div>
      <div class="big valor">${k.valorTexto}</div>
    </div>`;
}
export function MetricCard(opts) {
  return `<div class="card kpi-card"><div class="label">${opts.nome}</div><div class="big valor">${opts.valorTexto}</div></div>`;
}
export function KPIGrid(containerId, kpis, onClickKpi) {
  const cont = document.getElementById(containerId);
  cont.innerHTML = kpis.map(KPICard).join('');
  icones();
  if (!onClickKpi) return;
  cont.addEventListener('click', (e) => {
    const card = e.target.closest('.kpi-card[data-kpi]');
    if (!card) return;
    _ripple(card, e);
    onClickKpi(card.dataset.kpi);
  });
}
function _ripple(card, e) {
  const ripple = document.createElement('span');
  ripple.className = 'kpi-ripple';
  const rect = card.getBoundingClientRect();
  ripple.style.left = (e.clientX - rect.left - 10) + 'px';
  ripple.style.top = (e.clientY - rect.top - 10) + 'px';
  ripple.style.width = ripple.style.height = '20px';
  card.appendChild(ripple);
  setTimeout(() => ripple.remove(), 500);
}

// ============================================================================
// 05. SMART KPI
// Um KPICard clicável já ligado a um Drawer (ver componente 07). Combina
// KPIGrid + createDetailDrawer numa chamada só — é o padrão "KPI que abre
// painel de detalhe", usado no FIN-010/COM-001.
// SmartKPI(kpiGridContainerId, drawerIds, registry: { [id]: {nome, valorTexto, composicao:[{nome,valorTexto}]} })
// ============================================================================
export function SmartKPI(kpiGridContainerId, drawerIds, registry) {
  const drawer = createDetailDrawer(drawerIds);
  const kpis = Object.entries(registry).map(([id, k]) => ({ id, nome: k.nome, icone: k.icone, tom: k.tom, valorTexto: k.valorTexto, clicavel: true }));
  KPIGrid(kpiGridContainerId, kpis, (id) => {
    const k = registry[id];
    drawer.abrir(k.nome, k.valorTexto, k.composicao || []);
  });
  return drawer;
}

// ============================================================================
// 06. TIMELINE
// Timeline(containerId, itens: [{ hora, tipo, desc, sub, valorTexto, corValor }])
// ============================================================================
export function Timeline(containerId, itens) {
  const cont = document.getElementById(containerId);
  if (!itens || !itens.length) { EmptyState(containerId, 'Nenhuma movimentação encontrada.'); return; }
  cont.innerHTML = itens.map(t => `
    <div class="tl-item">
      <div class="tl-hora">${t.hora || '--:--'}</div>
      <div class="tl-marcador" style="${t.corMarcador ? `background:${t.corMarcador};` : ''}"></div>
      <div class="tl-corpo">
        <div class="tl-topo"><span class="tl-desc">${t.desc}</span>${t.valorTexto ? `<span class="tl-valor mono" style="${t.corValor ? `color:${t.corValor};` : ''}">${t.valorTexto}</span>` : ''}</div>
        ${t.sub ? `<div class="tl-sub">${t.sub}</div>` : ''}
      </div>
    </div>`).join('');
}

// ============================================================================
// 07. DRAWER
// Dois níveis, ambos como factory (pra poder ter mais de um por página sem
// colidir IDs, embora o uso normal seja um de cada por página):
//
// createSimpleDrawer(ids: {fundo, painel, titulo, resumo, lista, fechar})
//   -> { abrir(titulo, resumo, linhas), fechar() } — painel leve, uso: clique
//      num gráfico/lista abrindo o detalhe daquele ponto (drill-down).
//
// createDetailDrawer(ids: {fundo, painel, nome, valor, fechar, composicao,
//   recomendacoesSecao?, recomendacoesCorpo?, analiseSecao?, analiseCorpo?})
//   -> { abrir(nome, valorTexto, composicao, opts?) } — painel completo de
//      KPI, com Composição sempre visível e Recomendações/Análise Inteligente
//      reservadas (display:none no framework CSS até existir regra/IA real).
// ============================================================================
export function createSimpleDrawer(ids) {
  const fundo = document.getElementById(ids.fundo);
  const painel = document.getElementById(ids.painel);
  function abrir(titulo, resumo, linhas) {
    document.getElementById(ids.titulo).textContent = titulo;
    document.getElementById(ids.resumo).textContent = resumo;
    const listaEl = document.getElementById(ids.lista);
    listaEl.innerHTML = !linhas.length ? `<div class="dd-vazio">Nenhum dado neste recorte.</div>` : linhas.map(l => `
      <div class="dd-linha"><div><div class="dd-linha-desc">${l.desc}</div>${l.sub ? `<div class="dd-linha-sub">${l.sub}</div>` : ''}</div><span class="mono" style="color:${l.corValor || 'var(--ink)'}; font-weight:600; white-space:nowrap;">${l.valor}</span></div>`).join('');
    fundo.classList.add('aberto'); painel.classList.add('aberto');
    icones();
  }
  function fechar() { fundo.classList.remove('aberto'); painel.classList.remove('aberto'); }
  fundo.addEventListener('click', fechar);
  document.getElementById(ids.fechar).addEventListener('click', fechar);
  return { abrir, fechar };
}

export function createDetailDrawer(ids) {
  const fundo = document.getElementById(ids.fundo);
  const painel = document.getElementById(ids.painel);
  function abrir(nome, valorTexto, composicao) {
    document.getElementById(ids.nome).textContent = nome;
    document.getElementById(ids.valor).textContent = valorTexto;
    document.getElementById(ids.composicao).innerHTML = (composicao || []).map(c => `
      <div class="kpid-composicao-linha"><span>${c.nome}</span><span class="mono" style="font-weight:600;">${c.valorTexto}</span></div>`).join('');
    fundo.classList.add('aberto'); painel.classList.add('aberto');
    icones();
  }
  function fechar() { fundo.classList.remove('aberto'); painel.classList.remove('aberto'); }
  fundo.addEventListener('click', fechar);
  document.getElementById(ids.fechar).addEventListener('click', fechar);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') fechar(); });
  return { abrir, fechar };
}

// ============================================================================
// 08. DECISION CENTER
// DecisionCenter(containerId, recomendacoes: [{ titulo, descricao, origem,
//   impactoTexto, urgencia: 'alta'|'media'|'baixa', confianca /* 0-100 */,
//   acaoSugerida, exemplo?, onExecutar? }])
//
// origem é o nome do módulo de onde a recomendação veio (Financeiro,
// Comercial, Compras, Produção, Estoque, RH, Qualidade, IA — ver SYS-004,
// Decision Center: centro único agregando recomendação de todos os
// módulos). Cada origem ganha uma cor fixa (ORIGEM_CORES) pra escanear
// rápido de onde vem cada item numa lista com fontes misturadas.
// ============================================================================
export const ORIGEM_CORES = {
  'Financeiro': '#1f7a5c', 'Comercial': '#2f9e9e', 'Compras': '#b76e11', 'Produção': '#5b7fdb',
  'Estoque': '#8a63d2', 'RH': '#c0392b', 'Qualidade': '#0f766e', 'IA': '#8b5cf6',
};
export function DecisionCenter(containerId, recomendacoes) {
  const cont = document.getElementById(containerId);
  if (!recomendacoes || !recomendacoes.length) { EmptyState(containerId, 'Nenhuma recomendação no momento.'); return; }
  cont.innerHTML = recomendacoes.map((r, i) => {
    const corOrigem = ORIGEM_CORES[r.origem] || 'var(--ink-soft)';
    return `
    <div class="kpid-recomendacao" data-rec-idx="${i}" style="flex-direction:column; align-items:stretch; gap:8px;">
      <div style="display:flex; align-items:flex-start; justify-content:space-between; gap:10px;">
        <div>
          <div style="display:flex; align-items:center; gap:8px; flex-wrap:wrap; margin-bottom:4px;">
            <span style="font-size:9.5px; font-weight:700; text-transform:uppercase; letter-spacing:.04em; padding:2px 8px; border-radius:999px; background:${corOrigem}22; color:${corOrigem};">${r.origem}</span>
            <span class="ca-badge-urgencia urgencia-${r.urgencia}">${{alta:'Urgente', media:'Em breve', baixa:'Quando puder'}[r.urgencia] || r.urgencia}</span>
          </div>
          <div class="rec-titulo">${r.titulo}${r.exemplo ? ' <span class="ca-tag-exemplo">exemplo</span>' : ''}</div>
        </div>
        <button type="button" class="btn ghost"${r.onExecutar ? '' : ' disabled title="Sem ação ligada — estrutura pronta pra IA futura"'}>Executar</button>
      </div>
      <div class="rec-beneficio">${r.descricao}</div>
      <div style="display:flex; align-items:center; gap:16px; flex-wrap:wrap; font-size:11.5px; color:var(--ink-faint);">
        <span class="rec-impacto">Impacto: ${r.impactoTexto}</span>
        ${r.confianca != null ? `<span>Confiança: <b style="color:var(--ink-soft);">${r.confianca}%</b></span>` : ''}
        ${r.acaoSugerida ? `<span>Ação sugerida: <b style="color:var(--ink-soft);">${r.acaoSugerida}</b></span>` : ''}
      </div>
    </div>`;
  }).join('');
  recomendacoes.forEach((r, i) => {
    if (!r.onExecutar) return;
    cont.querySelector(`[data-rec-idx="${i}"] button`).addEventListener('click', r.onExecutar);
  });
}

// ============================================================================
// 09. SCORE (genérico — SYS-003: mesmo componente, mesma identidade visual,
// mesmo comportamento pra Health Score/Sales Score/Production Score/
// Inventory Score/Supplier Score/Quality Score/People Score). "nome" é o
// rótulo mostrado embaixo da nota (ex: "Saúde Financeira", "Saúde Comercial").
// Score(containerId, opts: { nome, nota /* 0-100 */, subMetricas: [{nome, valorTexto}] })
//
// HealthScore(containerId, nota, subMetricas) continua existindo como atalho
// pro caso espec\u00edfico do Financeiro (rótulo fixo "Saúde Financeira") — por
// baixo dos panos chama Score(), então corrigir o componente genérico
// corrige os dois ao mesmo tempo, nunca diverge.
// ============================================================================
export function Score(containerId, opts) {
  const { nome, nota, subMetricas } = opts;
  const tom = nota >= 80 ? 'excelente' : nota >= 60 ? 'boa' : nota >= 40 ? 'atencao' : 'critica';
  const texto = { excelente: 'Excelente', boa: 'Boa', atencao: 'Atenção', critica: 'Crítica' }[tom];
  document.getElementById(containerId).innerHTML = `
    <div class="hs-topo">
      <div class="hs-nota-box"><span class="hs-nota tom-${tom}">${nota}</span><span class="hs-nota-max">/100</span></div>
      <div class="hs-legenda"><div class="hs-rotulo-texto tom-${tom}">${texto}</div><div class="hs-rotulo-sub">${nome}</div></div>
      <div class="hs-barra-trilho"><div class="hs-barra-fill" style="width:${nota}%; background:var(--${tom === 'atencao' ? 'amber' : tom === 'critica' ? 'red' : 'accent'});"></div></div>
    </div>
    <div class="hs-grid">${subMetricas.map(m => `<div class="hs-card"><div class="hs-card-rotulo">${m.nome}</div><div class="hs-card-valor">${m.valorTexto}</div></div>`).join('')}</div>`;
}
export function HealthScore(containerId, nota, subMetricas) {
  Score(containerId, { nome: 'Saúde Financeira', nota, subMetricas });
}

// ============================================================================
// 10. TREND CARD
// TrendCard(valorTexto, positivo) -> retorna o HTML de uma linha de tendência
// (uso: injetar dentro de um Hero ou KPICard — não é um container próprio)
// ============================================================================
export function TrendCard(valorTexto, positivo) {
  return `<span style="color:${positivo ? 'var(--accent)' : 'var(--red)'}; font-weight:600;">${positivo ? '▲' : '▼'} ${valorTexto}</span>`;
}

// ============================================================================
// 11. ANALYSIS CARD
// AnalysisCard(containerId, analise: { resumo, positivos:[], atencao:[] })
// Bloco de leitura executiva (resumo + duas listas) — usado dentro de um
// Drawer (ver FinancialAnalysisDrawer) ou em qualquer outro lugar da página.
// ============================================================================
export function AnalysisCard(containerId, analise) {
  const cont = document.getElementById(containerId);
  cont.innerHTML = `
    <div class="kpid-resumo" style="margin-bottom:14px;">${analise.resumo}</div>
    ${analise.positivos ? `<ul class="fad-lista-check positivos" style="list-style:none; padding:0; margin:0 0 14px; display:flex; flex-direction:column; gap:8px;">${analise.positivos.map(t => `<li style="display:flex; gap:8px; font-size:13px;"><i data-lucide="check-circle-2" style="width:15px; height:15px; color:var(--accent); flex-shrink:0;"></i>${t}</li>`).join('')}</ul>` : ''}
    ${analise.atencao ? `<ul class="fad-lista-check atencao" style="list-style:none; padding:0; margin:0; display:flex; flex-direction:column; gap:8px;">${analise.atencao.map(t => `<li style="display:flex; gap:8px; font-size:13px;"><i data-lucide="alert-triangle" style="width:15px; height:15px; color:var(--amber); flex-shrink:0;"></i>${t}</li>`).join('')}</ul>` : ''}`;
  icones();
}

// ============================================================================
// 12. QUICK ACTION
// QuickAction(opts: { label, icone, href, onClick }) -> retorna o HTML de UM
// botão de ação rápida (uso: .map(QuickAction).join('') dentro de um
// container próprio, ex: .kpid-acoes-grid)
// ============================================================================
export function QuickAction(opts) {
  return `<a href="${opts.href || '#'}" class="kpid-acao-btn">${opts.icone ? `<i data-lucide="${opts.icone}"></i> ` : ''}${opts.label}</a>`;
}

// ============================================================================
// 14. EMPTY STATE / 15. LOADING STATE
// ============================================================================
export function EmptyState(containerId, mensagem) {
  document.getElementById(containerId).innerHTML = `<p style="color:var(--ink-soft); font-size:12.5px; padding:8px 0;">${mensagem || 'Nenhum dado encontrado.'}</p>`;
}
export function LoadingState(containerId, mensagem) {
  document.getElementById(containerId).innerHTML = `<p style="color:var(--ink-soft); font-size:12.5px; padding:8px 0;">${mensagem || 'Carregando…'}</p>`;
}

// ============================================================================
// 16. CHARTS
// Charts.donut(containerId, segmentos:[{nome,valor,cor,onClick?}], totalLabel, totalTexto)
// Charts.barList(containerId, itens:[{nome,valor,onClick?}])
// Charts.barChart(containerId, pontos:[{label,valor}]) — barra vertical simples
// ============================================================================
function _conicGradient(segmentos) {
  const total = segmentos.reduce((s, x) => s + x.valor, 0) || 1;
  let acc = 0;
  return `conic-gradient(${segmentos.map(seg => {
    const inicio = (acc / total * 100).toFixed(2);
    acc += Math.max(seg.valor, 0);
    return `${seg.cor} ${inicio}% ${(acc / total * 100).toFixed(2)}%`;
  }).join(', ')})`;
}
export const Charts = {
  donut(containerId, segmentos, totalLabel, totalTexto) {
    const cont = document.getElementById(containerId);
    const validos = segmentos.filter(s => s.valor > 0);
    if (!validos.length) { EmptyState(containerId, 'Sem dados no período.'); return; }
    cont.innerHTML = `
      <div class="donut-box"><div class="donut" style="background:${_conicGradient(validos)};"></div><div class="donut-hole"><div class="big">${totalTexto}</div><div class="small">${totalLabel}</div></div></div>
      <div class="chart-legend">${validos.map((s, i) => `<div class="item${s.onClick ? ' grafico-clicavel' : ''}" data-idx="${i}"><span class="dot" style="background:${s.cor};"></span><span class="nome">${s.nome}</span><span class="valor">${fmtMoeda(s.valor)}</span></div>`).join('')}</div>`;
    cont.querySelectorAll('.item[data-idx]').forEach(el => { const s = validos[Number(el.dataset.idx)]; if (s.onClick) el.addEventListener('click', s.onClick); });
  },
  barList(containerId, itens) {
    const cont = document.getElementById(containerId);
    if (!itens.length) { EmptyState(containerId, 'Sem dados no período.'); return; }
    const max = itens[0].valor || 1;
    cont.innerHTML = itens.map((it, i) => `
      <div class="linha${it.onClick ? ' grafico-clicavel' : ''}" data-idx="${i}">
        <div class="topo"><span class="nome">${it.nome}</span><span class="valor">${fmtMoeda(it.valor)}</span></div>
        <div class="trilho"><div class="fill" style="width:${(it.valor / max * 100).toFixed(1)}%; background:${CORES_SERIE[i % CORES_SERIE.length]};"></div></div>
      </div>`).join('');
    cont.querySelectorAll('.linha[data-idx]').forEach(el => { const it = itens[Number(el.dataset.idx)]; if (it.onClick) el.addEventListener('click', it.onClick); });
  },
  barChart(containerId, pontos) {
    const cont = document.getElementById(containerId);
    if (!pontos.length) { EmptyState(containerId, 'Sem dados no período.'); return; }
    const max = Math.max(...pontos.map(p => p.valor), 1);
    cont.innerHTML = pontos.map((p, i) => `
      <div class="grupo-mes${p.onClick ? ' grafico-clicavel' : ''}" data-idx="${i}">
        <div class="barras"><div class="barra bg-serie-1" style="height:${Math.max(3, p.valor / max * 130)}px;"></div></div>
        <span class="mes-label">${p.label}</span>
      </div>`).join('');
    cont.querySelectorAll('.grupo-mes[data-idx]').forEach(el => { const p = pontos[Number(el.dataset.idx)]; if (p.onClick) el.addEventListener('click', p.onClick); });
  },
};

// ============================================================================
// 17. DATA GRID
// DataGrid(containerId, colunas: [{titulo, alinhamento?: 'num'}], linhas:
//   [{ celulas: [textoOuHtml], onClick? }])
// ============================================================================
export function DataGrid(containerId, colunas, linhas) {
  const cont = document.getElementById(containerId);
  const cabecalho = `<thead><tr>${colunas.map(c => `<th${c.alinhamento ? ` class="${c.alinhamento}"` : ''}>${c.titulo}</th>`).join('')}</tr></thead>`;
  if (!linhas.length) {
    cont.innerHTML = `<table>${cabecalho}<tbody><tr><td colspan="${colunas.length}" class="empty-state">Nenhum registro encontrado.</td></tr></tbody></table>`;
    return;
  }
  const corpo = linhas.map((l, i) => `<tr${l.onClick ? ` data-linha-idx="${i}" style="cursor:pointer;"` : ''}>${l.celulas.map((c, j) => `<td${colunas[j]?.alinhamento ? ` class="${colunas[j].alinhamento}"` : ''}>${c}</td>`).join('')}</tr>`).join('');
  cont.innerHTML = `<table>${cabecalho}<tbody>${corpo}</tbody></table>`;
  linhas.forEach((l, i) => { if (l.onClick) cont.querySelector(`[data-linha-idx="${i}"]`).addEventListener('click', l.onClick); });
}

// ============================================================================
// GLOBAL SEARCH (SYS-006)
// Componente puro — não sabe de onde vêm os resultados. Recebe uma função
// `buscarFn(termo) -> Promise<[{ categoria, itens: [{texto, sub, href}] }]>`
// e só desenha o que ela devolver. Isso é o ponto-chave pra "preparar pra
// IA": hoje buscarFn faz consultas SQL diretas (ver js/dtv-search-provider.js),
// no futuro pode virar uma função que interpreta linguagem natural e chama
// um modelo — o componente nunca muda, só o que é passado como buscarFn.
//
// GlobalSearch(inputId, dropdownId, buscarFn, opts?: { debounceMs, minChars })
// Atalhos: Ctrl/Cmd+K foca o campo; ↑/↓ navega; Enter abre o item
// selecionado; Esc fecha.
// ============================================================================
export function GlobalSearch(inputId, dropdownId, buscarFn, opts = {}) {
  const input = document.getElementById(inputId);
  const dropdown = document.getElementById(dropdownId);
  const debounceMs = opts.debounceMs ?? 250;
  const minChars = opts.minChars ?? 2;
  let timer = null, selecionado = -1, itensAtuais = [];

  function fechar() { dropdown.style.display = 'none'; dropdown.innerHTML = ''; selecionado = -1; itensAtuais = []; }

  function renderResultados(grupos) {
    itensAtuais = grupos.flatMap(g => g.itens.map(it => ({ ...it, categoria: g.categoria })));
    if (!itensAtuais.length) { dropdown.innerHTML = `<div class="dtv-busca-vazio">Nenhum resultado.</div>`; dropdown.style.display = 'block'; return; }
    let idx = 0;
    dropdown.innerHTML = grupos.filter(g => g.itens.length).map(g => `
      <div class="dtv-busca-grupo">
        <div class="dtv-busca-grupo-titulo">${g.categoria}</div>
        ${g.itens.map(it => `<a href="${it.href || '#'}" class="dtv-busca-item" data-idx="${idx++}"><span class="dtv-busca-item-texto">${it.texto}</span>${it.sub ? `<span class="dtv-busca-item-sub">${it.sub}</span>` : ''}</a>`).join('')}
      </div>`).join('');
    dropdown.style.display = 'block';
  }

  function marcarSelecionado() {
    dropdown.querySelectorAll('.dtv-busca-item').forEach((el, i) => el.classList.toggle('ativo', i === selecionado));
    const ativo = dropdown.querySelector('.dtv-busca-item.ativo');
    if (ativo) ativo.scrollIntoView({ block: 'nearest' });
  }

  input.addEventListener('input', () => {
    clearTimeout(timer);
    const termo = input.value.trim();
    if (termo.length < minChars) { fechar(); return; }
    timer = setTimeout(async () => {
      const grupos = await buscarFn(termo);
      renderResultados(grupos);
    }, debounceMs);
  });

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { fechar(); input.blur(); return; }
    if (!itensAtuais.length) return;
    if (e.key === 'ArrowDown') { e.preventDefault(); selecionado = Math.min(selecionado + 1, itensAtuais.length - 1); marcarSelecionado(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); selecionado = Math.max(selecionado - 1, 0); marcarSelecionado(); }
    else if (e.key === 'Enter' && selecionado >= 0) { e.preventDefault(); const item = itensAtuais[selecionado]; if (item?.href) window.location.href = item.href; }
  });

  document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); input.focus(); input.select(); }
  });
  document.addEventListener('click', (e) => { if (!input.contains(e.target) && !dropdown.contains(e.target)) fechar(); });

  return { fechar };
}
