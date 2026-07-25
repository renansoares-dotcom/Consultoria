// ============================================================================
// Parser de extrato OFX — lê o texto do arquivo e devolve as transações.
//
// OFX vem em duas variações na prática: OFX 1.x (SGML, tags sem fechamento —
// ex: <DTPOSTED>20260701) e OFX 2.x (XML de verdade, com fechamento). Este
// parser não tenta validar a estrutura inteira do arquivo — ele isola cada
// bloco <STMTTRN>...</STMTTRN> (esse par sempre existe, mesmo no OFX 1.x) e
// extrai os campos de dentro por regex. É uma abordagem tolerante, testada
// contra exports reais de bancos brasileiros, e propositalmente simples: não
// depende de nenhuma biblioteca externa.
// ============================================================================

function pegarTag(texto, tag) {
  const m = texto.match(new RegExp(`<${tag}>\\s*([^\\r\\n<]*)`, 'i'));
  return m ? m[1].trim() : null;
}

function ofxDataParaISO(raw) {
  if (!raw || raw.length < 8) return null;
  const ano = raw.slice(0, 4);
  const mes = raw.slice(4, 6);
  const dia = raw.slice(6, 8);
  return `${ano}-${mes}-${dia}`;
}

/**
 * @param {string} texto - conteúdo bruto do arquivo .ofx
 * @returns {{ transacoes: Array<{fitid: string|null, data: string, valor: number, tipoOfx: string|null, descricao: string}>, saldoFinal: number|null, contaOfx: string|null }}
 */
export function parseOFX(texto) {
  if (!texto || !texto.includes('<STMTTRN>')) {
    throw new Error('Arquivo não parece ser um extrato OFX válido (bloco <STMTTRN> não encontrado).');
  }

  const transacoes = [];
  const blocos = texto.split(/<STMTTRN>/i).slice(1);

  for (const bloco of blocos) {
    const fimIdx = bloco.search(/<\/STMTTRN>/i);
    const corpo = fimIdx >= 0 ? bloco.slice(0, fimIdx) : bloco;

    const dtRaw = pegarTag(corpo, 'DTPOSTED');
    const valorRaw = pegarTag(corpo, 'TRNAMT');
    const data = ofxDataParaISO(dtRaw);
    const valor = valorRaw !== null ? parseFloat(valorRaw.replace(',', '.')) : NaN;

    if (!data || Number.isNaN(valor)) continue; // linha sem data ou valor utilizável — ignora

    transacoes.push({
      fitid: pegarTag(corpo, 'FITID'),
      data,
      valor,
      tipoOfx: pegarTag(corpo, 'TRNTYPE'),
      descricao: pegarTag(corpo, 'MEMO') || pegarTag(corpo, 'NAME') || '(sem descrição)',
    });
  }

  if (!transacoes.length) {
    throw new Error('Nenhuma transação foi encontrada dentro do arquivo. Confira se o .ofx não está vazio ou corrompido.');
  }

  const saldoRaw = pegarTag(texto, 'BALAMT');
  const saldoFinal = saldoRaw !== null ? parseFloat(saldoRaw.replace(',', '.')) : null;
  const contaOfx = pegarTag(texto, 'ACCTID');

  return { transacoes, saldoFinal, contaOfx };
}
