// ============================================================================
// ANALYTICS ENGINE (Sprint 003) — motor único de cálculo analítico.
//
// Puro, sem DOM, sem chamada Supabase direta — recebe dado já buscado pela
// página (dadosCompartilhados) e devolve número/estrutura pronta. Quem
// desenha (Charts, KPIGrid, Score) e quem decide o que um clique faz
// (abrirDrilldown) fica na página — o motor nunca sabe de UI.
//
// "Nenhum cálculo tributário fora do Tax Engine" (js/tax-engine.js) tem o
// equivalente aqui: nenhum cálculo de KPI/Score/Insight/agregação fora
// deste arquivo, pra qualquer módulo que passar a usá-lo.
// ============================================================================

const MESES_ABR = ['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'];

// ---------- Período ----------

export function obterIntervaloPeriodo(periodo) {
  const hoje = new Date(); hoje.setHours(0, 0, 0, 0);
  if (periodo === 'ano') {
    const inicio = new Date(hoje.getFullYear(), hoje.getMonth() - 11, 1);
    return { inicio, fim: hoje };
  }
  const dias = { hoje: 0, '7dias': 6, '30dias': 29, '90dias': 89 }[periodo] ?? 6;
  const inicio = new Date(hoje); inicio.setDate(hoje.getDate() - dias);
  return { inicio, fim: hoje };
}

// Baldes (intervalos) do eixo X conforme o período — 'ano' agrupa por mês,
// os demais por dia (nunca mais que ~15 barras).
export function gerarBucketsPeriodo(periodo) {
  const hoje = new Date(); hoje.setHours(0, 0, 0, 0);
  if (periodo === 'ano') {
    const buckets = [];
    for (let i = 11; i >= 0; i--) {
      const d = new Date(hoje.getFullYear(), hoje.getMonth() - i, 1);
      const fimMes = new Date(hoje.getFullYear(), hoje.getMonth() - i + 1, 0);
      const chave = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      buckets.push({ inicio: d, fim: fimMes, label: `${MESES_ABR[d.getMonth()]}/${String(d.getFullYear()).slice(2)}`, chave });
    }
    return buckets;
  }
  const diasPorPeriodo = { hoje: 1, '7dias': 7, '30dias': 30, '90dias': 90 };
  const totalDias = diasPorPeriodo[periodo] ?? 7;
  const diasPorBucket = Math.max(1, Math.ceil(totalDias / 15));
  const buckets = [];
  for (let offsetInicio = totalDias - 1; offsetInicio >= 0; offsetInicio -= diasPorBucket) {
    const offsetFim = Math.max(0, offsetInicio - diasPorBucket + 1);
    const dataInicio = new Date(hoje); dataInicio.setDate(hoje.getDate() - offsetInicio);
    const dataFim = new Date(hoje); dataFim.setDate(hoje.getDate() - offsetFim);
    const label = diasPorBucket === 1
      ? `${String(dataInicio.getDate()).padStart(2, '0')}/${String(dataInicio.getMonth() + 1).padStart(2, '0')}`
      : `${String(dataInicio.getDate()).padStart(2, '0')}-${String(dataFim.getDate()).padStart(2, '0')}/${String(dataFim.getMonth() + 1).padStart(2, '0')}`;
    buckets.push({ inicio: dataInicio, fim: dataFim, label });
  }
  return buckets;
}

export function filtrarRealizadoPorPeriodo(dadosCompartilhados, periodo) {
  const { inicio, fim } = obterIntervaloPeriodo(periodo);
  return dadosCompartilhados.realizado.filter(r => {
    if (r.tipo === 'transferencia' || !r.data_baixa) return false;
    const d = new Date(r.data_baixa + 'T00:00:00');
    return d >= inicio && d <= fim;
  });
}

// ---------- KPIs ----------

export function calcularKPIsFinanceiros(dadosCompartilhados) {
  const { contas, realizado, saldoLancamento, lancamentos } = dadosCompartilhados;
  const saldoInicialContas = contas.reduce((s, c) => s + Number(c.saldo_inicial || 0), 0);

  let realizadoTotal = saldoInicialContas;
  realizado.forEach(r => {
    if (r.tipo === 'transferencia' || !r.tipo) return;
    realizadoTotal += Number(r.valor_desembolsado) * (r.tipo === 'entrada' ? 1 : -1);
  });

  const infoPorLancamento = new Map(lancamentos.map(l => [l.id, l]));
  const saldos = saldoLancamento
    .filter(s => infoPorLancamento.has(s.lancamento_id))
    .map(s => ({ ...s, lancamentos: infoPorLancamento.get(s.lancamento_id) }));

  let aberto = 0, inadimplencia = 0;
  saldos.forEach(s => {
    const tipo = s.lancamentos?.plano_contas?.tipo;
    if (tipo === 'transferencia' || !tipo) return;
    const sinal = tipo === 'entrada' ? 1 : -1;
    if (s.status === 'em_aberto' || s.status === 'parcial') aberto += Number(s.saldo_aberto) * sinal;
    else if (s.status === 'inadimplente') inadimplencia += Number(s.saldo_aberto);
  });

  const projetado = realizadoTotal + aberto;
  return { realizado: realizadoTotal, aberto, projetado, inadimplencia };
}

// Tendência do hero — variação do saldo desde o início do período
// selecionado até agora (diferente da posição acumulada do KPI Realizado).
export function calcularTendenciaPeriodo(dadosCompartilhados, periodo) {
  const { inicio, fim } = obterIntervaloPeriodo(periodo);
  let netFlowPeriodo = 0;
  dadosCompartilhados.realizado.forEach(r => {
    if (r.tipo === 'transferencia' || !r.tipo || !r.data_baixa) return;
    const d = new Date(r.data_baixa + 'T00:00:00');
    if (d >= inicio && d <= fim) netFlowPeriodo += Number(r.valor_desembolsado) * (r.tipo === 'entrada' ? 1 : -1);
  });
  const { realizado: realizadoTotal } = calcularKPIsFinanceiros(dadosCompartilhados);
  const saldoInicioPeriodo = realizadoTotal - netFlowPeriodo;
  return { netFlowPeriodo, saldoInicioPeriodo, positivo: netFlowPeriodo >= 0 };
}

// Variação de um valor atual vs. 30 dias atrás — usado no drawer de KPI.
export function calcularVariacao30dias(dadosCompartilhados, valorAtual) {
  const { inicio, fim } = obterIntervaloPeriodo('30dias');
  let netFlow = 0;
  dadosCompartilhados.realizado.forEach(r => {
    if (r.tipo === 'transferencia' || !r.data_baixa) return;
    const d = new Date(r.data_baixa + 'T00:00:00');
    if (d >= inicio && d <= fim) netFlow += Number(r.valor_desembolsado) * (r.tipo === 'entrada' ? 1 : -1);
  });
  const valorAnterior = valorAtual - netFlow;
  if (Math.abs(valorAnterior) < 0.01) return null;
  return (netFlow / Math.abs(valorAnterior)) * 100;
}

// ---------- Agregações (gráficos + drill-down) ----------

export function agregarFluxoMensal(dadosCompartilhados, periodo) {
  const buckets = gerarBucketsPeriodo(periodo);
  buckets.forEach(b => { b.entrada = 0; b.saida = 0; b.linhas = []; });

  dadosCompartilhados.realizado.forEach(r => {
    if (r.tipo === 'transferencia' || !r.data_baixa) return;
    const dataR = new Date(r.data_baixa + 'T00:00:00');
    const bucket = buckets.find(b => dataR >= b.inicio && dataR <= b.fim);
    if (!bucket) return;
    bucket[r.tipo === 'entrada' ? 'entrada' : 'saida'] += Number(r.valor_desembolsado);
    bucket.linhas.push(r);
  });

  const max = Math.max(...buckets.flatMap(b => [b.entrada, b.saida]), 0.01);
  return { buckets, max };
}

export function calcularNetFlowMesAnoAnterior(dadosCompartilhados, chaveMes) {
  const [ano, mes] = chaveMes.split('-').map(Number);
  const inicio = new Date(ano - 1, mes - 1, 1);
  const fim = new Date(ano - 1, mes, 0);
  let net = 0, teveDado = false;
  dadosCompartilhados.realizado.forEach(r => {
    if (r.tipo === 'transferencia' || !r.data_baixa) return;
    const d = new Date(r.data_baixa + 'T00:00:00');
    if (d >= inicio && d <= fim) { net += Number(r.valor_desembolsado) * (r.tipo === 'entrada' ? 1 : -1); teveDado = true; }
  });
  return teveDado ? net : null;
}

export function agregarSaldoPorConta(dadosCompartilhados) {
  const { contas, realizado } = dadosCompartilhados;
  const saldos = {};
  contas.forEach(c => { saldos[c.id] = Number(c.saldo_inicial || 0); });
  realizado.forEach(r => {
    const v = Number(r.valor_desembolsado);
    if (r.tipo === 'transferencia') {
      if (saldos[r.conta_bancaria_id] !== undefined) saldos[r.conta_bancaria_id] -= v;
      if (saldos[r.conta_destino_id] !== undefined) saldos[r.conta_destino_id] += v;
    } else if (saldos[r.conta_bancaria_id] !== undefined) {
      saldos[r.conta_bancaria_id] += v * (r.tipo === 'entrada' ? 1 : -1);
    }
  });
  const totalGeral = Object.values(saldos).reduce((s, v) => s + v, 0);
  const segmentos = contas.map(c => ({
    id: c.id, nome: c.nome, valor: Math.max(saldos[c.id], 0), saldoReal: saldos[c.id],
    linhas: realizado.filter(r => r.conta_bancaria_id === c.id || r.conta_destino_id === c.id)
      .sort((a, b) => (b.data_baixa || '').localeCompare(a.data_baixa || '')),
  }));
  return { totalGeral, segmentos };
}

export function agregarAgingRecebiveis(dadosCompartilhados) {
  const { saldoLancamento, lancamentos } = dadosCompartilhados;
  const infoPorLancamento = new Map(lancamentos.filter(l => l.plano_contas?.tipo === 'entrada').map(l => [l.id, l]));
  const data = saldoLancamento
    .filter(s => infoPorLancamento.has(s.lancamento_id))
    .map(s => ({ saldo_aberto: s.saldo_aberto, lancamentos: infoPorLancamento.get(s.lancamento_id) }));

  const hoje = new Date(); hoje.setHours(0, 0, 0, 0);
  const buckets = {
    atual: { valor: 0, linhas: [] }, d30: { valor: 0, linhas: [] }, d60: { valor: 0, linhas: [] },
    d90: { valor: 0, linhas: [] }, vencido: { valor: 0, linhas: [] },
  };
  data.forEach(r => {
    const venc = r.lancamentos?.data_vencimento ? new Date(r.lancamentos.data_vencimento + 'T00:00:00') : null;
    const valor = Number(r.saldo_aberto || 0);
    if (valor <= 0) return;
    let chave;
    if (!venc) chave = 'atual';
    else {
      const dias = Math.round((venc - hoje) / 86400000);
      chave = dias < 0 ? 'vencido' : dias <= 30 ? 'atual' : dias <= 60 ? 'd30' : dias <= 90 ? 'd60' : 'd90';
    }
    buckets[chave].valor += valor;
    buckets[chave].linhas.push(r);
  });
  const total = Object.values(buckets).reduce((s, b) => s + b.valor, 0);
  return { total, buckets };
}

export function agregarTopFavorecidos(realizadoFiltrado, nomesPorId, limite = 5) {
  const porFavorecido = {};
  realizadoFiltrado.forEach(r => {
    const nome = nomesPorId[r.favorecido_id];
    if (!nome) return;
    if (!porFavorecido[r.favorecido_id]) porFavorecido[r.favorecido_id] = { nome, valor: 0, linhas: [] };
    porFavorecido[r.favorecido_id].valor += Number(r.valor_desembolsado);
    porFavorecido[r.favorecido_id].linhas.push(r);
  });
  return Object.values(porFavorecido).sort((a, b) => b.valor - a.valor).slice(0, limite);
}

export function agregarDistribuicaoPlanoContas(realizadoFiltrado, limite = 6) {
  const porPlano = {};
  realizadoFiltrado.forEach(r => {
    const nome = r.nome_conta;
    if (!nome) return;
    const chave = r.plano_conta_id || nome;
    if (!porPlano[chave]) porPlano[chave] = { nome, valor: 0, linhas: [] };
    porPlano[chave].valor += Number(r.valor_desembolsado);
    porPlano[chave].linhas.push(r);
  });
  return Object.values(porPlano).sort((a, b) => b.valor - a.valor).slice(0, limite);
}

// ---------- Score ----------
// calcularScore = calcularScoreEngine, movido de dtv-components.js pra cá.
// A Component Library NUNCA deve calcular sozinha — dtv-components.js
// re-exporta esta função com o nome antigo (calcularScoreEngine) só por
// compatibilidade, todos os 10 dashboards que já usam Score({fatores})
// continuam funcionando sem alteração.
export function calcularScore(fatores) {
  if (!fatores || !fatores.length) return 0;
  const somaPesos = fatores.reduce((s, f) => s + (f.peso ?? 1), 0) || 1;
  const nota = fatores.reduce((s, f) => s + f.valor * (f.peso ?? 1), 0) / somaPesos;
  return Math.max(0, Math.min(100, Math.round(nota)));
}

// ---------- Health Score Financeiro (cálculo real, v1) ----------
// AVISO: fatores/pesos abaixo são uma heurística v1 razoável, não uma
// fórmula validada por contador/CFO — mesma ressalva já usada no Tax
// Engine pras alíquotas de exemplo. Fica marcado como tal na saída
// (fatorRealCalculado:true) pra quem consumir saber que já é cálculo de
// verdade, mesmo que os pesos ainda precisem de validação de negócio.
export function calcularHealthScoreFinanceiro(dadosCompartilhados) {
  const { realizado, aberto, projetado, inadimplencia } = calcularKPIsFinanceiros(dadosCompartilhados);

  const totalAReceberAberto = (() => {
    const { lancamentos, saldoLancamento } = dadosCompartilhados;
    const infoPorLancamento = new Map(lancamentos.map(l => [l.id, l]));
    return saldoLancamento
      .filter(s => infoPorLancamento.has(s.lancamento_id) && infoPorLancamento.get(s.lancamento_id)?.plano_contas?.tipo === 'entrada')
      .reduce((s, x) => s + Number(x.saldo_aberto || 0), 0);
  })();

  // Liquidez: saldo realizado cobre as saídas em aberto dos próximos 30 dias?
  const saidasEmAberto = Math.max(0, -Math.min(aberto, 0)) || Math.abs(Math.min(aberto, 0));
  const liquidez = saidasEmAberto <= 0 ? 100 : Math.max(0, Math.min(100, (realizado / saidasEmAberto) * 100));

  // Inadimplência: quanto do total a receber em aberto virou inadimplência.
  const baseInadimplencia = totalAReceberAberto + inadimplencia;
  const inadimplenciaPct = baseInadimplencia > 0 ? (inadimplencia / baseInadimplencia) * 100 : 0;
  const notaInadimplencia = Math.max(0, 100 - inadimplenciaPct * 2); // pesa 2x — inadimplência dói mais que a proporção linear

  // Capital de giro: saldo projetado positivo e crescente é saudável.
  const notaCapitalGiro = projetado >= 0 ? Math.min(100, 60 + (projetado / Math.max(realizado, 1)) * 40) : Math.max(0, 40 + projetado / Math.max(Math.abs(realizado), 1) * 40);

  // Concentração de cliente: maior favorecido de entrada vs. total recebido no período (30 dias).
  const recebidos30d = filtrarRealizadoPorPeriodo(dadosCompartilhados, '30dias').filter(r => r.tipo === 'entrada');
  const totalRecebido30d = recebidos30d.reduce((s, r) => s + Number(r.valor_desembolsado), 0);
  const porFavorecido30d = {};
  recebidos30d.forEach(r => { porFavorecido30d[r.favorecido_id] = (porFavorecido30d[r.favorecido_id] || 0) + Number(r.valor_desembolsado); });
  const maiorFavorecido30d = Math.max(0, ...Object.values(porFavorecido30d));
  const concentracaoPct = totalRecebido30d > 0 ? (maiorFavorecido30d / totalRecebido30d) * 100 : 0;
  const notaConcentracao = Math.max(0, 100 - concentracaoPct);

  const fatores = [
    { nome: 'Liquidez', valor: Math.round(liquidez), peso: 0.3 },
    { nome: 'Inadimplência', valor: Math.round(notaInadimplencia), peso: 0.25 },
    { nome: 'Capital de Giro', valor: Math.round(notaCapitalGiro), peso: 0.25 },
    { nome: 'Concentração de Cliente', valor: Math.round(notaConcentracao), peso: 0.2 },
  ];
  const nota = calcularScore(fatores);
  return {
    nota, fatorRealCalculado: true,
    subMetricas: [
      { nome: 'Liquidez', valorTexto: `${Math.round(liquidez)}%` },
      { nome: 'Inadimplência', valorTexto: `${inadimplenciaPct.toFixed(1)}%` },
      { nome: 'Capital de Giro', valorTexto: fmtCompacto(projetado) },
      { nome: 'Concentração', valorTexto: `${concentracaoPct.toFixed(1)}%` },
    ],
    fatores,
  };
}

function fmtCompacto(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 0, maximumFractionDigits: 0 });
}

// ---------- Insights Financeiros (cálculo real, v1) ----------
// Mesma ressalva: regras simples e defensáveis, não IA — mas 100% real,
// nenhum texto de exemplo fixo. Só entra insight quando o dado sustenta a
// afirmação (nunca inventa tendência sem base de comparação).
export function gerarInsightsFinanceiros(dadosCompartilhados) {
  const insights = [];
  const periodoAtual = filtrarRealizadoPorPeriodo(dadosCompartilhados, '30dias');
  const entradas30d = periodoAtual.filter(r => r.tipo === 'entrada').reduce((s, r) => s + Number(r.valor_desembolsado), 0);
  const saidas30d = periodoAtual.filter(r => r.tipo === 'saida').reduce((s, r) => s + Number(r.valor_desembolsado), 0);

  // Comparação com os 30 dias anteriores aos últimos 30 (janela 31-60 dias atrás)
  const hoje = new Date(); hoje.setHours(0, 0, 0, 0);
  const inicioAnterior = new Date(hoje); inicioAnterior.setDate(hoje.getDate() - 59);
  const fimAnterior = new Date(hoje); fimAnterior.setDate(hoje.getDate() - 30);
  const periodoAnterior = dadosCompartilhados.realizado.filter(r => {
    if (r.tipo === 'transferencia' || !r.data_baixa) return false;
    const d = new Date(r.data_baixa + 'T00:00:00');
    return d >= inicioAnterior && d <= fimAnterior;
  });
  const entradasAnterior = periodoAnterior.filter(r => r.tipo === 'entrada').reduce((s, r) => s + Number(r.valor_desembolsado), 0);
  const saidasAnterior = periodoAnterior.filter(r => r.tipo === 'saida').reduce((s, r) => s + Number(r.valor_desembolsado), 0);

  if (entradasAnterior > 0) {
    const variacao = ((entradas30d - entradasAnterior) / entradasAnterior) * 100;
    if (Math.abs(variacao) >= 5) {
      insights.push({ categoria: 'Recebimentos', texto: `Recebimentos ${variacao >= 0 ? 'cresceram' : 'caíram'} ${Math.abs(variacao).toFixed(0)}% em relação aos 30 dias anteriores`, origem: 'Regra', grauConfianca: 90 });
    }
  }
  if (saidasAnterior > 0) {
    const variacao = ((saidas30d - saidasAnterior) / saidasAnterior) * 100;
    if (Math.abs(variacao) >= 5) {
      insights.push({ categoria: 'Pagamentos', texto: `Pagamentos ${variacao >= 0 ? 'aumentaram' : 'reduziram'} ${Math.abs(variacao).toFixed(0)}% em relação aos 30 dias anteriores`, origem: 'Regra', grauConfianca: 90 });
    }
  }

  const porFavorecido = {};
  periodoAtual.filter(r => r.tipo === 'entrada').forEach(r => { porFavorecido[r.favorecido_id] = (porFavorecido[r.favorecido_id] || 0) + Number(r.valor_desembolsado); });
  const maiorValor = Math.max(0, ...Object.values(porFavorecido));
  if (entradas30d > 0 && maiorValor / entradas30d >= 0.15) {
    insights.push({ categoria: 'Clientes', texto: `Maior cliente representa ${((maiorValor / entradas30d) * 100).toFixed(0)}% da receita dos últimos 30 dias`, origem: 'Regra', grauConfianca: 95 });
  }

  const { aging } = { aging: agregarAgingRecebiveis(dadosCompartilhados) };
  if (aging.buckets.vencido.valor > 0 && aging.total > 0 && (aging.buckets.vencido.valor / aging.total) >= 0.15) {
    insights.push({ categoria: 'Inadimplência', texto: `${((aging.buckets.vencido.valor / aging.total) * 100).toFixed(0)}% dos títulos a receber estão vencidos`, origem: 'Regra', grauConfianca: 92 });
  }

  return insights;
}

// ============================================================================
// ESTOQUE (Sprint 004) — mesmos princípios do Financeiro: puro, sem DOM,
// sem Supabase interno. Recebe produtos (tabela produtos, já tem
// saldo_atual/saldo_minimo/estoque_maximo/custo_medio/saldo_reservado
// prontos) e movimentacoes (estoque_movimentacoes, já filtradas por
// período pela página).
//
// "Acuracidade" NÃO está implementada abaixo — não existe tabela de
// inventário/contagem física no banco hoje (confirmado por auditoria,
// Sprint 004), então não há como calcular sistema vs. contagem real.
// Fica fora do motor até essa tabela existir — não inventamos o dado.
// ============================================================================

export function calcularValorTotalEstoque(produtos) {
  return produtos.reduce((s, p) => s + Number(p.saldo_atual || 0) * Number(p.custo_medio || 0), 0);
}

export function calcularViolacoesEstoqueMinimo(produtos) {
  return produtos.filter(p => p.gera_estoque !== false && Number(p.saldo_minimo || 0) > 0 && Number(p.saldo_atual || 0) < Number(p.saldo_minimo));
}

export function calcularViolacoesEstoqueMaximo(produtos) {
  return produtos.filter(p => p.gera_estoque !== false && Number(p.estoque_maximo || 0) > 0 && Number(p.saldo_atual || 0) > Number(p.estoque_maximo));
}

export function calcularRuptura(produtos) {
  return produtos.filter(p => p.gera_estoque !== false && Number(p.saldo_atual || 0) <= 0);
}

// Giro = quanto saiu no período / saldo médio (aproximado pelo saldo atual,
// não há histórico de saldo diário pra média real ainda).
export function calcularGiroEstoque(produtos, movimentacoes) {
  const totalSaida = movimentacoes.filter(m => m.tipo === 'saida').reduce((s, m) => s + Number(m.quantidade || 0), 0);
  const saldoMedioAprox = produtos.reduce((s, p) => s + Number(p.saldo_atual || 0), 0);
  if (saldoMedioAprox <= 0) return 0;
  return totalSaida / saldoMedioAprox;
}

// Cobertura em dias = saldo_atual / consumo médio diário (baseado no
// período informado, em dias).
export function calcularCoberturaDias(produtos, movimentacoes, diasPeriodo) {
  const saidaPorProduto = {};
  movimentacoes.filter(m => m.tipo === 'saida').forEach(m => {
    saidaPorProduto[m.produto_id] = (saidaPorProduto[m.produto_id] || 0) + Number(m.quantidade || 0);
  });
  return produtos.map(p => {
    const consumoDiario = (saidaPorProduto[p.id] || 0) / Math.max(diasPeriodo, 1);
    const cobertura = consumoDiario > 0 ? Number(p.saldo_atual || 0) / consumoDiario : null; // null = sem consumo no período, cobertura indefinida
    return { produto: p, cobertura };
  });
}

// Curva ABC por valor (saldo_atual × custo_medio) — A = até 80% do valor
// acumulado, B = até 95%, C = resto. Padrão clássico de gestão de estoque.
export function calcularCurvaABC(produtos) {
  const comValor = produtos
    .map(p => ({ produto: p, valor: Number(p.saldo_atual || 0) * Number(p.custo_medio || 0) }))
    .filter(x => x.valor > 0)
    .sort((a, b) => b.valor - a.valor);
  const valorTotal = comValor.reduce((s, x) => s + x.valor, 0);
  if (valorTotal <= 0) return { A: [], B: [], C: [] };
  let acumulado = 0;
  const classificados = { A: [], B: [], C: [] };
  comValor.forEach(x => {
    acumulado += x.valor;
    const pctAcumulado = acumulado / valorTotal;
    const classe = pctAcumulado <= 0.8 ? 'A' : pctAcumulado <= 0.95 ? 'B' : 'C';
    classificados[classe].push(x);
  });
  return classificados;
}

// Produtos parados = sem NENHUMA saída dentro do período informado (dias).
export function calcularProdutosParados(produtos, movimentacoes, diasPeriodo) {
  const hoje = new Date(); hoje.setHours(0, 0, 0, 0);
  const limite = new Date(hoje); limite.setDate(limite.getDate() - diasPeriodo);
  const produtosComSaida = new Set(
    movimentacoes.filter(m => m.tipo === 'saida' && new Date(m.data + 'T00:00:00') >= limite).map(m => m.produto_id)
  );
  return produtos.filter(p => p.gera_estoque !== false && Number(p.saldo_atual || 0) > 0 && !produtosComSaida.has(p.id));
}

// Tendência = net flow (entrada-saída) do período, aproximação sem
// snapshot histórico de saldo diário (mesmo princípio do Financeiro).
export function calcularTendenciaEstoque(movimentacoes) {
  let netFlow = 0;
  movimentacoes.forEach(m => { netFlow += Number(m.quantidade || 0) * (m.tipo === 'entrada' ? 1 : -1); });
  return { netFlow, positivo: netFlow >= 0 };
}
