-- ============================================================================
-- DEMO COMPANY — Poliflex Embalagens (Sprint 005.2)
-- Script idempotente: pode rodar quantas vezes quiser, sempre apaga e
-- recria SÓ o que pertence ao tenant "Poliflex Embalagens (Demo)" — nunca
-- toca em dado de nenhum outro tenant (isolamento total via tenant_id).
-- ============================================================================

do $$
declare
  v_tenant_id uuid;
  v_grupo_id uuid;
  v_conta_itau uuid; v_conta_caixa uuid;
  v_plano_venda uuid; v_plano_compra_mp uuid; v_plano_folha uuid; v_plano_despesa uuid;
  v_prod_resina uuid; v_prod_masterbatch uuid; v_prod_filme uuid;
  v_forn_resina uuid; v_forn_masterbatch uuid;
  v_cli_distribuidora uuid; v_cli_mercado uuid;
  v_pc_id uuid; v_pci_id uuid;
  v_op_id uuid;
  v_pv_id uuid; v_pvi_id uuid;
  v_exp_id uuid;
begin
  -- ---------- 1. Tenant (idempotente por nome) ----------
  select id into v_tenant_id from tenants where nome = 'Poliflex Embalagens (Demo)';
  if v_tenant_id is null then
    insert into tenants (id, nome, cnpj, ativo) values (gen_random_uuid(), 'Poliflex Embalagens (Demo)', '00.000.000/0001-00', true)
    returning id into v_tenant_id;
  end if;

  -- ---------- 2. Limpa tudo que já existia deste tenant (idempotência real) ----------
  delete from reimpressoes_etiqueta where tenant_id = v_tenant_id;
  delete from unidades_produzidas where tenant_id = v_tenant_id;
  delete from apontamentos_producao where tenant_id = v_tenant_id;
  delete from requisicao_compra_origem where tenant_id = v_tenant_id;
  delete from paradas_producao where tenant_id = v_tenant_id;
  delete from estoque_reservas where tenant_id = v_tenant_id;
  delete from expedicao_itens where tenant_id = v_tenant_id;
  delete from expedicoes where tenant_id = v_tenant_id;
  delete from pedido_venda_itens where tenant_id = v_tenant_id;
  delete from pedidos_venda where tenant_id = v_tenant_id;
  delete from ordens_producao where tenant_id = v_tenant_id;
  delete from pedido_compra_itens where tenant_id = v_tenant_id;
  delete from pedidos_compra where tenant_id = v_tenant_id;
  delete from estoque_movimentacoes where tenant_id = v_tenant_id;
  delete from estrutura_produto_itens where tenant_id = v_tenant_id;
  delete from lancamentos where tenant_id = v_tenant_id;
  delete from produtos where tenant_id = v_tenant_id;
  delete from favorecidos where tenant_id = v_tenant_id;
  delete from plano_contas where tenant_id = v_tenant_id;
  delete from contas_bancarias where tenant_id = v_tenant_id;
  delete from grupos_empresariais where tenant_id = v_tenant_id;

  -- ---------- 3. Grupo empresarial ----------
  insert into grupos_empresariais (id, tenant_id, nome, ativo) values (gen_random_uuid(), v_tenant_id, 'Poliflex Matriz', true)
  returning id into v_grupo_id;

  -- ---------- 4. Contas bancárias ----------
  insert into contas_bancarias (id, tenant_id, nome, saldo_inicial) values (gen_random_uuid(), v_tenant_id, 'Banco Itaú', 50000) returning id into v_conta_itau;
  insert into contas_bancarias (id, tenant_id, nome, saldo_inicial) values (gen_random_uuid(), v_tenant_id, 'Caixa Interno', 3000) returning id into v_conta_caixa;

  -- ---------- 5. Plano de contas ----------
  insert into plano_contas (id, tenant_id, nome_conta, tipo, ativo) values (gen_random_uuid(), v_tenant_id, 'Venda de Produtos', 'entrada', true) returning id into v_plano_venda;
  insert into plano_contas (id, tenant_id, nome_conta, tipo, ativo) values (gen_random_uuid(), v_tenant_id, 'Compra de Matéria-Prima', 'saida', true) returning id into v_plano_compra_mp;
  insert into plano_contas (id, tenant_id, nome_conta, tipo, ativo) values (gen_random_uuid(), v_tenant_id, 'Folha de Pagamento', 'saida', true) returning id into v_plano_folha;
  insert into plano_contas (id, tenant_id, nome_conta, tipo, ativo) values (gen_random_uuid(), v_tenant_id, 'Despesas Operacionais', 'saida', true) returning id into v_plano_despesa;

  -- ---------- 6. Produtos (2 matérias-primas + 1 produto acabado) ----------
  insert into produtos (id, tenant_id, codigo, nome, tipo, unidade_medida, saldo_atual, saldo_minimo, estoque_maximo, custo_medio, gera_estoque, ativo)
  values (gen_random_uuid(), v_tenant_id, 'MP-001', 'Resina PEBD', 'materia_prima', 'KG', 0, 100, 2000, 6.80, true, true) returning id into v_prod_resina;
  insert into produtos (id, tenant_id, codigo, nome, tipo, unidade_medida, saldo_atual, saldo_minimo, estoque_maximo, custo_medio, gera_estoque, ativo)
  values (gen_random_uuid(), v_tenant_id, 'MP-002', 'Masterbatch Azul', 'materia_prima', 'KG', 0, 10, 200, 22.50, true, true) returning id into v_prod_masterbatch;
  insert into produtos (id, tenant_id, codigo, nome, tipo, unidade_medida, saldo_atual, saldo_minimo, estoque_maximo, custo_medio, gera_estoque, ativo, preco_venda)
  values (gen_random_uuid(), v_tenant_id, 'PA-001', 'Filme Stretch 50cm x 300m', 'produto_acabado', 'UN', 0, 20, 500, 45.00, true, true, 78.90) returning id into v_prod_filme;

  -- ---------- 7. Estrutura de produto (BOM): 1 rolo = 5kg resina + 0.2kg masterbatch ----------
  insert into estrutura_produto_itens (tenant_id, produto_id, componente_id, quantidade_por_unidade)
  values (v_tenant_id, v_prod_filme, v_prod_resina, 5), (v_tenant_id, v_prod_filme, v_prod_masterbatch, 0.2);

  -- ---------- 8. Favorecidos (2 fornecedores + 2 clientes) ----------
  insert into favorecidos (id, tenant_id, nome, tipo, cnpj_cpf, cidade, uf, ativo) values (gen_random_uuid(), v_tenant_id, 'Petroquímica Sul Ltda', 'fornecedores', '11.111.111/0001-11', 'Triunfo', 'RS', true) returning id into v_forn_resina;
  insert into favorecidos (id, tenant_id, nome, tipo, cnpj_cpf, cidade, uf, ativo) values (gen_random_uuid(), v_tenant_id, 'Cores & Pigmentos ME', 'fornecedores', '22.222.222/0001-22', 'Diadema', 'SP', true) returning id into v_forn_masterbatch;
  insert into favorecidos (id, tenant_id, nome, tipo, cnpj_cpf, cidade, uf, ativo) values (gen_random_uuid(), v_tenant_id, 'Distribuidora Embalagens SP', 'clientes', '33.333.333/0001-33', 'São Paulo', 'SP', true) returning id into v_cli_distribuidora;
  insert into favorecidos (id, tenant_id, nome, tipo, cnpj_cpf, cidade, uf, ativo) values (gen_random_uuid(), v_tenant_id, 'Mercado Central Atacado', 'clientes', '44.444.444/0001-44', 'Campinas', 'SP', true) returning id into v_cli_mercado;

  -- ---------- 9. Pedido de Compra recebido (dispara entrada real via trigger) ----------
  insert into pedidos_compra (id, tenant_id, grupo_empresarial_id, numero_pedido, fornecedor_id, status, data_pedido)
  values (gen_random_uuid(), v_tenant_id, v_grupo_id, 'PC-DEMO-001', v_forn_resina, 'recebido_total', current_date - 10) returning id into v_pc_id;
  insert into pedido_compra_itens (id, tenant_id, pedido_compra_id, produto_id, quantidade, quantidade_recebida, valor_unitario)
  values (gen_random_uuid(), v_tenant_id, v_pc_id, v_prod_resina, 600, 0, 6.80) returning id into v_pci_id;
  -- UPDATE separado do INSERT de propósito: fn_processar_recebimento_item dispara em AFTER UPDATE, não INSERT
  update pedido_compra_itens set quantidade_recebida = 600 where id = v_pci_id;

  insert into pedidos_compra (id, tenant_id, grupo_empresarial_id, numero_pedido, fornecedor_id, status, data_pedido)
  values (gen_random_uuid(), v_tenant_id, v_grupo_id, 'PC-DEMO-002', v_forn_masterbatch, 'recebido_total', current_date - 10) returning id into v_pc_id;
  insert into pedido_compra_itens (id, tenant_id, pedido_compra_id, produto_id, quantidade, quantidade_recebida, valor_unitario)
  values (gen_random_uuid(), v_tenant_id, v_pc_id, v_prod_masterbatch, 30, 0, 22.50) returning id into v_pci_id;
  update pedido_compra_itens set quantidade_recebida = 30 where id = v_pci_id;

  -- ---------- 10. Ordem de Produção (dispara reserva real via trigger Sprint 005.1) ----------
  insert into ordens_producao (id, tenant_id, grupo_empresarial_id, numero_op, produto_id, quantidade_planejada, status, data_abertura)
  values (gen_random_uuid(), v_tenant_id, v_grupo_id, 'OP-DEMO-001', v_prod_filme, 100, 'planejada', current_date - 5) returning id into v_op_id;

  -- ---------- 11. Pedido de Venda ----------
  insert into pedidos_venda (id, tenant_id, grupo_empresarial_id, numero_pedido, cliente_id, status, data_pedido, data_entrega_prevista)
  values (gen_random_uuid(), v_tenant_id, v_grupo_id, 'PV-DEMO-001', v_cli_distribuidora, 'em_producao', current_date - 4, current_date + 10) returning id into v_pv_id;
  insert into pedido_venda_itens (id, tenant_id, pedido_venda_id, produto_id, quantidade, valor_unitario)
  values (gen_random_uuid(), v_tenant_id, v_pv_id, v_prod_filme, 80, 78.90) returning id into v_pvi_id;

  -- ---------- 12. Apontamento parcial de produção (60 de 100 rolos) ----------
  insert into apontamentos_producao (tenant_id, ordem_producao_id, quantidade, data)
  values (v_tenant_id, v_op_id, 60, current_date - 1);

  -- ---------- 13. Expedição parcial (30 dos 60 rolos já produzidos, pro cliente) ----------
  insert into expedicoes (id, tenant_id, grupo_empresarial_id, numero_expedicao, pedido_venda_id, status, data_expedicao)
  values (gen_random_uuid(), v_tenant_id, v_grupo_id, 'EXP-DEMO-001', v_pv_id, 'entregue', current_date) returning id into v_exp_id;
  insert into expedicao_itens (id, tenant_id, expedicao_id, pedido_venda_item_id, produto_id, quantidade)
  values (gen_random_uuid(), v_tenant_id, v_exp_id, v_pvi_id, v_prod_filme, 30);

  -- ---------- 14. Financeiro: contas a pagar (compras) e a receber (venda) ----------
  insert into lancamentos (id, tenant_id, grupo_empresarial_id, descricao, valor, data, data_vencimento, plano_conta_id, favorecido_id, conta_bancaria_id, status)
  values
    (gen_random_uuid(), v_tenant_id, v_grupo_id, 'Compra de resina PEBD - PC-DEMO-001', 4080.00, current_date - 10, current_date + 20, v_plano_compra_mp, v_forn_resina, v_conta_itau, 'em_aberto'),
    (gen_random_uuid(), v_tenant_id, v_grupo_id, 'Compra de masterbatch - PC-DEMO-002', 675.00, current_date - 10, current_date + 20, v_plano_compra_mp, v_forn_masterbatch, v_conta_itau, 'em_aberto'),
    (gen_random_uuid(), v_tenant_id, v_grupo_id, 'Venda parcial Filme Stretch - PV-DEMO-001', 2367.00, current_date, current_date + 30, v_plano_venda, v_cli_distribuidora, v_conta_itau, 'em_aberto');
  -- tipo (entrada/saida) não é coluna própria de lancamentos — vem por join com plano_contas.tipo

  raise notice 'Demo Company criada: tenant_id = %', v_tenant_id;
end $$;
