// ============================================================================
// TAX ENGINE (FIS-001) — motor único de cálculo tributário do Datativo.
//
// AVISO IMPORTANTE, leia antes de usar em produção: nenhuma alíquota ou
// regra aqui é valor real de ICMS/ISS/PIS/COFINS/IBS/CBS/Imposto Seletivo.
// São exemplos estruturais. A Reforma Tributária brasileira (EC 132/2023 e
// leis complementares) ainda está em fase de regulamentação, com transição
// gradual até 2033 — as alíquotas de IBS/CBS/Imposto Seletivo mudam por
// decreto/lei complementar ao longo desse período. Antes de usar em
// produção, toda regra parametrizada aqui precisa ser revisada e
// preenchida por um contador ou advogado tributário com acesso à
// legislação vigente. Este arquivo NUNCA deve conter alíquota real
// hardcoded — regras entram via banco/parametrização, nunca no código.
//
// "Nenhum cálculo tributário deverá existir fora do Tax Engine" — esta é a
// ÚNICA fonte de cálculo do sistema. Qualquer tela que precise de tributo
// chama as funções daqui, nunca reimplementa a lógica.
// ============================================================================

// Tipos de tributo suportados — desenhado pra CONVIVÊNCIA entre legislação
// atual e Reforma Tributária (os dois grupos coexistem durante a transição).
export const TIPOS_TRIBUTO = {
  atuais: ['ICMS', 'ISS', 'PIS', 'COFINS', 'IPI'],
  reforma: ['IBS', 'CBS', 'IMPOSTO_SELETIVO'],
};

// ============================================================================
// Regra tributária — versionada por vigência.
// { id, tipo, descricao, vigenciaInicio (YYYY-MM-DD), vigenciaFim (YYYY-MM-DD
//   | null = sem fim definido), parametros: { aliquota /* 0-1 */,
//   baseCalculoTipo }, ativa }
//
// Várias regras do MESMO tipo podem existir com vigências diferentes
// (histórico) — buscarRegraVigente() acha a certa pra uma data específica,
// o que permite recalcular corretamente uma nota fiscal antiga mesmo depois
// da alíquota ter mudado.
// ============================================================================

export function buscarRegraVigente(regras, tipo, dataReferencia) {
  const data = new Date(dataReferencia + 'T00:00:00');
  const candidatas = regras.filter(r =>
    r.tipo === tipo && r.ativa &&
    new Date(r.vigenciaInicio + 'T00:00:00') <= data &&
    (!r.vigenciaFim || new Date(r.vigenciaFim + 'T00:00:00') >= data)
  );
  // se mais de uma regra do mesmo tipo estiver vigente na mesma data (não
  // deveria acontecer com parametrização correta, mas o motor se defende),
  // usa a de vigência mais recente.
  candidatas.sort((a, b) => b.vigenciaInicio.localeCompare(a.vigenciaInicio));
  return candidatas[0] || null;
}

export function calcularTributo(baseCalculo, tipo, dataReferencia, regras) {
  const regra = buscarRegraVigente(regras, tipo, dataReferencia);
  if (!regra) {
    return { tipo, valor: 0, aliquota: null, regraAplicada: null, erro: `Nenhuma regra vigente para ${tipo} em ${dataReferencia}` };
  }
  const valor = Number(baseCalculo) * Number(regra.parametros.aliquota);
  return { tipo, valor, aliquota: regra.parametros.aliquota, regraAplicada: regra.id, regraDescricao: regra.descricao, baseCalculo: Number(baseCalculo), erro: null };
}

export function calcularMultiplosTributos(baseCalculo, tipos, dataReferencia, regras) {
  return tipos.map(tipo => calcularTributo(baseCalculo, tipo, dataReferencia, regras));
}

// Soma o resultado de calcularMultiplosTributos, ignorando os que deram erro
// (regra não encontrada) — retorna { total, detalhes, algumErro }
export function totalizarTributos(resultados) {
  const total = resultados.reduce((s, r) => s + (r.erro ? 0 : r.valor), 0);
  const algumErro = resultados.some(r => r.erro);
  return { total, detalhes: resultados, algumErro };
}
