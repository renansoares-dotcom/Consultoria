// ============================================================================
// Relatório em PDF de um projeto de Pré-impressão/Aprovação de Arte —
// compartilhado entre Portal do Cliente e sistema interno.
// Usa jsPDF (carregado via <script> na página que importa este módulo,
// precisa estar disponível como window.jspdf.jsPDF).
// ============================================================================

const LABEL_STATUS = { em_andamento: 'Em Andamento', aguardando_aprovacao: 'Aguardando Aprovação', aprovado: 'Aprovado', reprovado: 'Reprovado', cancelado: 'Cancelado' };
const LABEL_DECISAO = { aprovado: 'Aprovado', reprovado: 'Reprovado', solicitar_alteracao: 'Alteração solicitada' };

function fmtDataHora(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('pt-BR');
}

async function urlParaDataUrl(url) {
  try {
    const resposta = await fetch(url);
    const blob = await resposta.blob();
    return await new Promise((resolve, reject) => {
      const leitor = new FileReader();
      leitor.onload = () => resolve(leitor.result);
      leitor.onerror = reject;
      leitor.readAsDataURL(blob);
    });
  } catch {
    return null;
  }
}

// versoes: [{ numero_versao, arquivo_nome, arquivo_tipo, arquivo_path, observacoes, criado_em, autor, decisoes: [{decisao, comentario, criado_em, autor}] }]
export async function gerarRelatorioArtePDF({ supabase, projeto, clienteNome, versoes }) {
  if (!window.jspdf) throw new Error('jsPDF não carregado.');
  const { jsPDF } = window.jspdf;
  const doc = new jsPDF();
  const margemEsquerda = 14;
  const larguraUtil = 182;
  let y = 20;

  function novaPaginaSeNecessario(alturaNecessaria) {
    if (y + alturaNecessaria > 280) { doc.addPage(); y = 20; }
  }

  doc.setFontSize(17);
  doc.setFont(undefined, 'bold');
  doc.text(projeto.nome, margemEsquerda, y);
  y += 8;

  doc.setFontSize(10);
  doc.setFont(undefined, 'normal');
  doc.text(`Cliente: ${clienteNome ?? 'Não informado'}`, margemEsquerda, y); y += 5;
  doc.text(`Status atual: ${LABEL_STATUS[projeto.status] ?? projeto.status}`, margemEsquerda, y); y += 5;
  doc.text(`Relatório gerado em: ${fmtDataHora(new Date().toISOString())}`, margemEsquerda, y); y += 10;

  doc.setDrawColor(200);
  doc.line(margemEsquerda, y, margemEsquerda + larguraUtil, y);
  y += 8;

  doc.setFontSize(13);
  doc.setFont(undefined, 'bold');
  doc.text('Histórico de Versões e Decisões', margemEsquerda, y);
  y += 8;

  const versoesOrdenadas = [...versoes].sort((a, b) => b.numero_versao - a.numero_versao);

  for (const v of versoesOrdenadas) {
    novaPaginaSeNecessario(45);
    const yInicioBloco = y;
    const ehImagem = (v.arquivo_tipo || '').startsWith('image/');
    let dataUrl = null;

    if (ehImagem) {
      try {
        const { data: signed } = await supabase.storage.from('anexos').createSignedUrl(v.arquivo_path, 300);
        if (signed?.signedUrl) dataUrl = await urlParaDataUrl(signed.signedUrl);
      } catch { /* segue sem miniatura */ }
    }

    const xTexto = dataUrl ? margemEsquerda + 38 : margemEsquerda;
    const larguraTexto = dataUrl ? larguraUtil - 38 : larguraUtil;

    if (dataUrl) {
      try { doc.addImage(dataUrl, 'PNG', margemEsquerda, y, 32, 32); } catch { /* formato não suportado, ignora imagem */ }
    }

    doc.setFontSize(11);
    doc.setFont(undefined, 'bold');
    doc.text(`Versão ${v.numero_versao} — ${v.arquivo_nome}`, xTexto, y + 4);
    doc.setFontSize(9);
    doc.setFont(undefined, 'normal');
    doc.text(`Enviado por: ${v.autor ?? 'Não identificado'}  ·  ${fmtDataHora(v.criado_em)}`, xTexto, y + 10);

    let yTexto = y + 16;
    if (v.observacoes) {
      const linhas = doc.splitTextToSize(`Observação: ${v.observacoes}`, larguraTexto);
      doc.text(linhas, xTexto, yTexto);
      yTexto += linhas.length * 4.5;
    }

    const alturaImagem = dataUrl ? y + 34 : y;
    y = Math.max(yTexto, alturaImagem) + 3;

    for (const d of (v.decisoes || [])) {
      novaPaginaSeNecessario(16);
      doc.setFontSize(9);
      doc.setFont(undefined, 'bold');
      doc.text(`→ ${LABEL_DECISAO[d.decisao] ?? d.decisao}`, xTexto, y);
      doc.setFont(undefined, 'normal');
      doc.text(`por ${d.autor ?? 'Não identificado'} em ${fmtDataHora(d.criado_em)}`, xTexto + 38, y);
      y += 5;
      if (d.comentario) {
        const linhasComentario = doc.splitTextToSize(d.comentario, larguraTexto);
        doc.text(linhasComentario, xTexto, y);
        y += linhasComentario.length * 4.5;
      }
    }

    y = Math.max(y, yInicioBloco + 8) + 4;
    doc.setDrawColor(230);
    doc.line(margemEsquerda, y, margemEsquerda + larguraUtil, y);
    y += 6;
  }

  const nomeArquivo = `relatorio-arte-${projeto.nome.replace(/[^a-zA-Z0-9]+/g, '-').toLowerCase()}.pdf`;
  doc.save(nomeArquivo);
}
