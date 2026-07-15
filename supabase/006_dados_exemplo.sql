-- ============================================================================
-- MIGRAÇÃO 006 — Dados de exemplo (10 compromissos completos)
-- Popula cadastros básicos + 10 lançamentos cobrindo: entrada, saída,
-- transferência, pago, parcial, em aberto, inadimplente, com baixas parciais,
-- rateio (distribuição) e todos os campos novos (documento, parcela,
-- prorrogação, aprovação, forma de pagamento).
--
-- Roda no SQL Editor do Supabase. Usa seu e-mail para achar o tenant certo.
-- ============================================================================

do $$
declare
  v_tenant_id uuid;
  v_usuario_id uuid;

  v_grupo_id uuid;
  v_banco_id uuid;
  v_caixa_id uuid;

  v_cc_adm uuid;
  v_cc_com uuid;
  v_cc_prod uuid;

  v_fav_fornecedor uuid;
  v_fav_cliente uuid;
  v_fav_func uuid;
  v_fav_socia uuid;
  v_fav_imob uuid;
  v_fav_energia uuid;

  v_pc_venda uuid;
  v_pc_servico uuid;
  v_pc_aluguel uuid;
  v_pc_agua uuid;
  v_pc_salarios uuid;
  v_pc_materiais uuid;
  v_pc_frete uuid;
  v_pc_transf uuid;

  v_l1 uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid; v_l5 uuid;
  v_l6 uuid; v_l7 uuid; v_l8 uuid; v_l9 uuid; v_l10 uuid;
begin
  select tenant_id, id into v_tenant_id, v_usuario_id
  from usuarios where email = 'renansoaresgualberto@gmail.com';

  if v_tenant_id is null then
    raise exception 'Usuário não encontrado — confira o e-mail antes de rodar.';
  end if;

  -- ---------------------------------------------------------------------
  -- CADASTROS BASE
  -- ---------------------------------------------------------------------
  insert into grupos_empresariais (tenant_id, nome) values (v_tenant_id, 'Matriz')
    returning id into v_grupo_id;

  insert into contas_bancarias (tenant_id, grupo_empresarial_id, nome, disponibilidade, saldo_inicial, data_saldo_inicial)
    values (v_tenant_id, v_grupo_id, 'Banco Principal', 'Conta com recursos disponíveis', 10000, '2026-01-01')
    returning id into v_banco_id;
  insert into contas_bancarias (tenant_id, grupo_empresarial_id, nome, disponibilidade, saldo_inicial, data_saldo_inicial)
    values (v_tenant_id, v_grupo_id, 'Caixa Interno', 'Conta com recursos disponíveis', 2000, '2026-01-01')
    returning id into v_caixa_id;

  insert into centros_custo (tenant_id, nome) values (v_tenant_id, 'Administrativo') returning id into v_cc_adm;
  insert into centros_custo (tenant_id, nome) values (v_tenant_id, 'Comercial') returning id into v_cc_com;
  insert into centros_custo (tenant_id, nome) values (v_tenant_id, 'Produção') returning id into v_cc_prod;

  insert into favorecidos (tenant_id, tipo, nome, cnpj_cpf) values (v_tenant_id, 'fornecedores', 'Fornecedor ABC Materiais', '11.222.333/0001-44') returning id into v_fav_fornecedor;
  insert into favorecidos (tenant_id, tipo, nome, cnpj_cpf) values (v_tenant_id, 'clientes', 'Cliente XYZ Comércio', '22.333.444/0001-55') returning id into v_fav_cliente;
  insert into favorecidos (tenant_id, tipo, nome, cnpj_cpf) values (v_tenant_id, 'funcionarios', 'João Silva', '111.222.333-44') returning id into v_fav_func;
  insert into favorecidos (tenant_id, tipo, nome, cnpj_cpf) values (v_tenant_id, 'socios', 'Maria Sócia', '222.333.444-55') returning id into v_fav_socia;
  insert into favorecidos (tenant_id, tipo, nome, cnpj_cpf) values (v_tenant_id, 'fornecedores', 'Imobiliária Central Ltda', '33.444.555/0001-66') returning id into v_fav_imob;
  insert into favorecidos (tenant_id, tipo, nome, cnpj_cpf) values (v_tenant_id, 'fornecedores', 'Concessionária Elétrica SA', '44.555.666/0001-77') returning id into v_fav_energia;

  -- ---------------------------------------------------------------------
  -- PLANO DE CONTAS
  -- ---------------------------------------------------------------------
  insert into plano_contas (tenant_id, tipo, codigo_grupo, nome_grupo, codigo_conta, nome_conta)
    values (v_tenant_id, 'entrada', '1.01', 'Receita de Vendas', '1.01.01', 'Venda de Produtos') returning id into v_pc_venda;
  insert into plano_contas (tenant_id, tipo, codigo_grupo, nome_grupo, codigo_conta, nome_conta)
    values (v_tenant_id, 'entrada', '1.02', 'Receita de Serviços', '1.02.01', 'Prestação de Serviços') returning id into v_pc_servico;

  insert into plano_contas (tenant_id, tipo, codigo_grupo, nome_grupo, codigo_conta, nome_conta)
    values (v_tenant_id, 'saida', '2.01', 'Despesas Administrativas', '2.01.01', 'Aluguel') returning id into v_pc_aluguel;
  insert into plano_contas (tenant_id, tipo, codigo_grupo, nome_grupo, codigo_conta, nome_conta)
    values (v_tenant_id, 'saida', '2.01', 'Despesas Administrativas', '2.01.02', 'Água e Luz') returning id into v_pc_agua;
  insert into plano_contas (tenant_id, tipo, codigo_grupo, nome_grupo, codigo_conta, nome_conta)
    values (v_tenant_id, 'saida', '2.02', 'Despesas com Pessoal', '2.02.01', 'Salários') returning id into v_pc_salarios;
  insert into plano_contas (tenant_id, tipo, codigo_grupo, nome_grupo, codigo_conta, nome_conta)
    values (v_tenant_id, 'saida', '2.03', 'Despesas com Fornecedores', '2.03.01', 'Compra de Materiais') returning id into v_pc_materiais;
  insert into plano_contas (tenant_id, tipo, codigo_grupo, nome_grupo, codigo_conta, nome_conta)
    values (v_tenant_id, 'saida', '2.03', 'Despesas com Fornecedores', '2.03.02', 'Frete e Logística') returning id into v_pc_frete;

  insert into plano_contas (tenant_id, tipo, codigo_grupo, nome_grupo, codigo_conta, nome_conta)
    values (v_tenant_id, 'transferencia', '3.01', 'Movimentação Interna', '3.01.01', 'Transferência entre Contas') returning id into v_pc_transf;

  -- ---------------------------------------------------------------------
  -- 1. ENTRADA — venda paga (baixa completa)
  -- ---------------------------------------------------------------------
  insert into lancamentos (tenant_id, grupo_empresarial_id, data, data_emissao, plano_conta_id, descricao,
      favorecido_id, centro_custo_id, status, conta_bancaria_id, valor, data_vencimento,
      numero_documento, parcela_numero, parcela_total, forma_pagamento, criado_por)
    values (v_tenant_id, v_grupo_id, '2026-06-10', '2026-06-08', v_pc_venda, 'Venda de produtos — pedido 1001',
      v_fav_cliente, v_cc_com, 'em_aberto', v_banco_id, 5000, '2026-06-20',
      'NF 1001', 1, 1, 'PIX', v_usuario_id)
    returning id into v_l1;
  insert into baixas (tenant_id, lancamento_id, data, valor_pago, forma_pagamento, conta_bancaria_id, criado_por)
    values (v_tenant_id, v_l1, '2026-06-18', 5000, 'PIX', v_banco_id, v_usuario_id);
  -- rateio de exemplo: 100% Comercial
  insert into lancamento_distribuicao_conta (tenant_id, lancamento_id, plano_conta_id, percentual, valor)
    values (v_tenant_id, v_l1, v_pc_venda, 100, 5000);
  insert into lancamento_distribuicao_cc (tenant_id, lancamento_id, centro_custo_id, percentual, valor)
    values (v_tenant_id, v_l1, v_cc_com, 100, 5000);

  -- ---------------------------------------------------------------------
  -- 2. ENTRADA — serviço com baixa PARCIAL
  -- ---------------------------------------------------------------------
  insert into lancamentos (tenant_id, grupo_empresarial_id, data, data_emissao, plano_conta_id, descricao,
      favorecido_id, centro_custo_id, status, conta_bancaria_id, valor, data_vencimento,
      numero_documento, parcela_numero, parcela_total, forma_pagamento, criado_por)
    values (v_tenant_id, v_grupo_id, '2026-06-25', '2026-06-25', v_pc_servico, 'Prestação de serviço de consultoria',
      v_fav_cliente, v_cc_com, 'em_aberto', v_banco_id, 3000, '2026-07-10',
      'NF 1002', 1, 1, 'Boleto', v_usuario_id)
    returning id into v_l2;
  insert into baixas (tenant_id, lancamento_id, data, valor_pago, forma_pagamento, conta_bancaria_id, observacoes, criado_por)
    values (v_tenant_id, v_l2, '2026-07-05', 1500, 'Boleto', v_banco_id, 'Pagamento parcial combinado com cliente', v_usuario_id);

  -- ---------------------------------------------------------------------
  -- 3. ENTRADA — em aberto, vencimento futuro (sem baixa)
  -- ---------------------------------------------------------------------
  insert into lancamentos (tenant_id, grupo_empresarial_id, data, data_emissao, plano_conta_id, descricao,
      favorecido_id, centro_custo_id, status, conta_bancaria_id, valor, data_vencimento,
      numero_documento, parcela_numero, parcela_total, forma_pagamento, criado_por)
    values (v_tenant_id, v_grupo_id, '2026-07-05', '2026-07-05', v_pc_venda, 'Venda de produtos — pedido 1010',
      v_fav_cliente, v_cc_com, 'em_aberto', v_banco_id, 2000, '2026-08-15',
      'NF 1010', 1, 1, 'PIX', v_usuario_id)
    returning id into v_l3;

  -- ---------------------------------------------------------------------
  -- 4. SAÍDA — aluguel pago
  -- ---------------------------------------------------------------------
  insert into lancamentos (tenant_id, grupo_empresarial_id, data, data_emissao, plano_conta_id, descricao,
      favorecido_id, centro_custo_id, status, conta_bancaria_id, valor, data_vencimento,
      numero_documento, parcela_numero, parcela_total, forma_pagamento, criado_por)
    values (v_tenant_id, v_grupo_id, '2026-07-01', '2026-07-01', v_pc_aluguel, 'Aluguel do escritório — julho/2026',
      v_fav_imob, v_cc_adm, 'em_aberto', v_banco_id, -1800, '2026-07-05',
      'REC-ALUGUEL-07', 1, 1, 'Débito Automático', v_usuario_id)
    returning id into v_l4;
  insert into baixas (tenant_id, lancamento_id, data, valor_pago, forma_pagamento, conta_bancaria_id, criado_por)
    values (v_tenant_id, v_l4, '2026-07-04', 1800, 'Débito Automático', v_banco_id, v_usuario_id);

  -- ---------------------------------------------------------------------
  -- 5. SAÍDA — água e luz INADIMPLENTE (venceu, não pago)
  -- ---------------------------------------------------------------------
  insert into lancamentos (tenant_id, grupo_empresarial_id, data, data_emissao, plano_conta_id, descricao,
      favorecido_id, centro_custo_id, status, conta_bancaria_id, valor, data_vencimento,
      numero_documento, parcela_numero, parcela_total, forma_pagamento, criado_por)
    values (v_tenant_id, v_grupo_id, '2026-06-15', '2026-06-15', v_pc_agua, 'Conta de energia elétrica — junho/2026',
      v_fav_energia, v_cc_adm, 'inadimplente', v_banco_id, -450, '2026-06-30',
      'FAT-ENERGIA-06', 1, 1, 'Boleto', v_usuario_id)
    returning id into v_l5;

  -- ---------------------------------------------------------------------
  -- 6. SAÍDA — salários pagos
  -- ---------------------------------------------------------------------
  insert into lancamentos (tenant_id, grupo_empresarial_id, data, data_emissao, plano_conta_id, descricao,
      favorecido_id, centro_custo_id, status, conta_bancaria_id, valor, data_vencimento,
      numero_documento, parcela_numero, parcela_total, forma_pagamento, criado_por)
    values (v_tenant_id, v_grupo_id, '2026-06-30', '2026-06-30', v_pc_salarios, 'Folha de pagamento — junho/2026',
      v_fav_func, v_cc_prod, 'em_aberto', v_banco_id, -8000, '2026-06-30',
      'FOLHA-06-2026', 1, 1, 'TED', v_usuario_id)
    returning id into v_l6;
  insert into baixas (tenant_id, lancamento_id, data, valor_pago, forma_pagamento, conta_bancaria_id, criado_por)
    values (v_tenant_id, v_l6, '2026-06-30', 8000, 'TED', v_banco_id, v_usuario_id);

  -- ---------------------------------------------------------------------
  -- 7. SAÍDA — compra de materiais com baixa PARCIAL + rateio (conta e CC)
  -- ---------------------------------------------------------------------
  insert into lancamentos (tenant_id, grupo_empresarial_id, data, data_emissao, plano_conta_id, descricao,
      favorecido_id, centro_custo_id, status, conta_bancaria_id, valor, data_vencimento,
      numero_documento, parcela_numero, parcela_total, forma_pagamento, criado_por)
    values (v_tenant_id, v_grupo_id, '2026-07-02', '2026-07-02', v_pc_materiais, 'Compra de matéria-prima + frete',
      v_fav_fornecedor, v_cc_prod, 'em_aberto', v_banco_id, -6000, '2026-07-20',
      'NF-FORN-3345', 1, 1, 'Boleto', v_usuario_id)
    returning id into v_l7;
  insert into baixas (tenant_id, lancamento_id, data, valor_pago, forma_pagamento, conta_bancaria_id, observacoes, criado_por)
    values (v_tenant_id, v_l7, '2026-07-08', 3000, 'Boleto', v_banco_id, 'Primeira parcela do acordo com fornecedor', v_usuario_id);
  insert into lancamento_distribuicao_conta (tenant_id, lancamento_id, plano_conta_id, percentual, valor) values
    (v_tenant_id, v_l7, v_pc_materiais, 70, 4200),
    (v_tenant_id, v_l7, v_pc_frete, 30, 1800);
  insert into lancamento_distribuicao_cc (tenant_id, lancamento_id, centro_custo_id, percentual, valor) values
    (v_tenant_id, v_l7, v_cc_prod, 50, 3000),
    (v_tenant_id, v_l7, v_cc_adm, 50, 3000);

  -- ---------------------------------------------------------------------
  -- 8. TRANSFERÊNCIA — Banco Principal → Caixa Interno (paga)
  -- ---------------------------------------------------------------------
  insert into lancamentos (tenant_id, grupo_empresarial_id, data, data_emissao, plano_conta_id, descricao,
      status, conta_bancaria_id, conta_destino_id, valor, data_vencimento,
      numero_documento, forma_pagamento, criado_por)
    values (v_tenant_id, v_grupo_id, '2026-07-10', '2026-07-10', v_pc_transf, 'Transferência para suprir caixa interno',
      'em_aberto', v_banco_id, v_caixa_id, 1000, '2026-07-10',
      'TRF-INTERNA-01', 'TED', v_usuario_id)
    returning id into v_l8;
  insert into baixas (tenant_id, lancamento_id, data, valor_pago, forma_pagamento, criado_por)
    values (v_tenant_id, v_l8, '2026-07-10', 1000, 'TED', v_usuario_id);

  -- ---------------------------------------------------------------------
  -- 9. SAÍDA — parcelada 2/3, com PRORROGAÇÃO de vencimento (em aberto)
  -- ---------------------------------------------------------------------
  insert into lancamentos (tenant_id, grupo_empresarial_id, data, data_emissao, plano_conta_id, descricao,
      favorecido_id, centro_custo_id, status, conta_bancaria_id, valor, data_vencimento,
      data_prorrogacao_vencimento, motivo_prorrogacao,
      numero_documento, parcela_numero, parcela_total, forma_pagamento, criado_por)
    values (v_tenant_id, v_grupo_id, '2026-07-12', '2026-07-12', v_pc_materiais, 'Compra de insumos — parcela 2 de 3',
      v_fav_fornecedor, v_cc_prod, 'em_aberto', v_banco_id, -1200, '2026-07-25',
      '2026-08-05', 'Negociação de prazo com o fornecedor',
      'NF-FORN-3346', 2, 3, 'Boleto', v_usuario_id)
    returning id into v_l9;

  -- ---------------------------------------------------------------------
  -- 10. ENTRADA — venda aprovada, baixa com juros e desconto (paga)
  -- ---------------------------------------------------------------------
  insert into lancamentos (tenant_id, grupo_empresarial_id, data, data_emissao, plano_conta_id, descricao,
      favorecido_id, centro_custo_id, status, conta_bancaria_id, valor, data_vencimento,
      numero_documento, parcela_numero, parcela_total, forma_pagamento, aprovado_por, aprovado_em, criado_por)
    values (v_tenant_id, v_grupo_id, '2026-07-11', '2026-07-11', v_pc_venda, 'Venda de produtos — pedido 1020 (grande cliente)',
      v_fav_cliente, v_cc_com, 'em_aberto', v_banco_id, 4200, '2026-07-18',
      'NF 1020', 1, 1, 'Cartão', v_usuario_id, now(), v_usuario_id)
    returning id into v_l10;
  insert into baixas (tenant_id, lancamento_id, data, valor_pago, juros, desconto, forma_pagamento, conta_bancaria_id, observacoes, criado_por)
    values (v_tenant_id, v_l10, '2026-07-17', 4180, 50, 20, 'Cartão', v_banco_id, 'Pago com pequeno desconto por antecipação, taxa de cartão cobrada à parte', v_usuario_id);

  raise notice 'Dados de exemplo criados com sucesso para o tenant %', v_tenant_id;
end $$;
