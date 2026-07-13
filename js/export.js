// ============================================================================
// Exportação de relatórios — CSV real (baixa .csv) e PDF via impressão do
// navegador (window.print, com folha de estilo @media print no CSS) — essa
// abordagem evita depender de bibliotecas externas pesadas.
// ============================================================================

export function exportarCSV(nomeArquivo, seletorTabela) {
  const tabela = document.querySelector(seletorTabela);
  if (!tabela) { alert('Não há dados carregados para exportar ainda.'); return; }

  const linhas = [...tabela.querySelectorAll('tr')]
    .filter(tr => tr.querySelectorAll('th,td').length > 1 || !tr.querySelector('.empty-state'))
    .map(tr =>
      [...tr.querySelectorAll('th,td')].map(celula => {
        const texto = celula.innerText.replace(/\s+/g, ' ').trim().replace(/"/g, '""');
        return `"${texto}"`;
      }).join(';')
    );

  if (!linhas.length) { alert('Não há dados carregados para exportar ainda.'); return; }

  const conteudo = '\uFEFF' + linhas.join('\r\n'); // BOM garante acentuação correta ao abrir no Excel
  const blob = new Blob([conteudo], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nomeArquivo.endsWith('.csv') ? nomeArquivo : `${nomeArquivo}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

export function exportarPDF() {
  window.print();
}

// Injeta os dois botões (CSV e PDF) dentro de um container já existente na página.
export function adicionarBotoesExportacao(seletorContainer, seletorTabela, nomeArquivo) {
  const container = document.querySelector(seletorContainer);
  if (!container) return;

  const btnCSV = document.createElement('button');
  btnCSV.type = 'button';
  btnCSV.className = 'btn ghost no-print';
  btnCSV.textContent = '⬇ CSV';
  btnCSV.addEventListener('click', () => exportarCSV(nomeArquivo, seletorTabela));

  const btnPDF = document.createElement('button');
  btnPDF.type = 'button';
  btnPDF.className = 'btn ghost no-print';
  btnPDF.textContent = '⬇ PDF';
  btnPDF.addEventListener('click', exportarPDF);

  container.appendChild(btnCSV);
  container.appendChild(btnPDF);
}
