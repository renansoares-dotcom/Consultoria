// ============================================================================
// DTV SEARCH PROVIDER (SYS-006) — busca de verdade, hoje via SQL direto.
//
// Esta é a peça DESACOPLADA do componente visual (GlobalSearch, em
// dtv-components.js): o componente só chama uma função `buscarFn(termo)` e
// desenha o que vier. Hoje essa função aqui roda 10 consultas .ilike() em
// paralelo. NO FUTURO, pra virar busca em linguagem natural, troca-se só
// esta função (ou substitui por uma que chama IA) — o componente visual
// nunca precisa mudar.
//
// Cobre 10 das 11 categorias pedidas com busca real:
//   Clientes, Fornecedores, Produtos, Pedidos (venda+compra), Notas,
//   Pagamentos, Recebimentos, Ordens (produção+manutenção), Usuários, Empresas
// "Documentos" fica de fora da busca real — não existe tabela de documentos
// no banco hoje (arquivos vivem no Storage, não são registro consultável
// por nome/texto). Categoria reservada, sem resultado, não removida.
// ============================================================================

export async function buscarGlobalReal(supabase, termo) {
  const like = `%${termo}%`;

  const [
    { data: favorecidos },
    { data: produtos },
    { data: pedidosVenda },
    { data: pedidosCompra },
    { data: notas },
    { data: lancamentos },
    { data: ordensProducao },
    { data: ordensManutencao },
    { data: usuarios },
    { data: empresas },
  ] = await Promise.all([
    supabase.from('favorecidos').select('id, nome, tipo').ilike('nome', like).limit(8),
    supabase.from('produtos').select('id, nome, codigo').or(`nome.ilike.${like},codigo.ilike.${like}`).limit(5),
    supabase.from('pedidos_venda').select('id, numero_pedido').ilike('numero_pedido', like).limit(5),
    supabase.from('pedidos_compra').select('id, numero_pedido').ilike('numero_pedido', like).limit(5),
    supabase.from('notas_fiscais').select('id, numero').ilike('numero', like).limit(5),
    // busca sem filtro de tipo na consulta — classifica Pagamento/Recebimento
    // no cliente, evita depender de filtro embutido em tabela unida (PostgREST
    // não garante que .eq() numa coluna de embed exclua a linha pai — lição
    // já registrada nesta sessão, ver DEBT/ADR anteriores).
    supabase.from('lancamentos').select('id, descricao, valor, plano_contas(tipo)').ilike('descricao', like).limit(10),
    supabase.from('ordens_producao').select('id, numero_op').ilike('numero_op', like).limit(5),
    supabase.from('ordens_manutencao').select('id, descricao_problema').ilike('descricao_problema', like).limit(5),
    supabase.from('usuarios').select('id, nome').ilike('nome', like).limit(5),
    supabase.from('grupos_empresariais').select('id, nome').ilike('nome', like).limit(5),
  ]);

  const pagamentos = (lancamentos || []).filter(l => l.plano_contas?.tipo === 'saida');
  const recebimentos = (lancamentos || []).filter(l => l.plano_contas?.tipo === 'entrada');

  return [
    { categoria: 'Clientes', itens: (favorecidos || []).filter(f => f.tipo === 'clientes').map(f => ({ texto: f.nome, href: `financeiro/cadastros.html#favorecidos` })) },
    { categoria: 'Fornecedores', itens: (favorecidos || []).filter(f => f.tipo === 'fornecedores').map(f => ({ texto: f.nome, href: `financeiro/cadastros.html#favorecidos` })) },
    { categoria: 'Produtos', itens: (produtos || []).map(p => ({ texto: p.nome, sub: p.codigo, href: `estoque/dashboard.html` })) },
    { categoria: 'Pedidos', itens: [
      ...(pedidosVenda || []).map(p => ({ texto: `Pedido de Venda ${p.numero_pedido}`, href: `vendas/pedidos.html` })),
      ...(pedidosCompra || []).map(p => ({ texto: `Pedido de Compra ${p.numero_pedido}`, href: `compras/dashboard.html` })),
    ]},
    { categoria: 'Notas', itens: (notas || []).map(n => ({ texto: `Nota Fiscal ${n.numero}`, href: `fiscal/dashboard.html` })) },
    { categoria: 'Pagamentos', itens: pagamentos.map(l => ({ texto: l.descricao || '(sem descrição)', href: `financeiro/lancamentos.html` })) },
    { categoria: 'Recebimentos', itens: recebimentos.map(l => ({ texto: l.descricao || '(sem descrição)', href: `financeiro/lancamentos.html` })) },
    { categoria: 'Ordens', itens: [
      ...(ordensProducao || []).map(o => ({ texto: `Ordem de Produção ${o.numero_op}`, href: `producao/dashboard.html` })),
      ...(ordensManutencao || []).map(o => ({ texto: o.descricao_problema, sub: 'Manutenção', href: `manutencao/dashboard.html` })),
    ]},
    { categoria: 'Usuários', itens: (usuarios || []).map(u => ({ texto: u.nome, href: `cadastro/dashboard.html` })) },
    { categoria: 'Empresas', itens: (empresas || []).map(e => ({ texto: e.nome, href: `financeiro/cadastros.html#grupos_empresariais` })) },
    { categoria: 'Documentos', itens: [] }, // reservado — sem tabela de documentos no banco hoje
  ];
}
