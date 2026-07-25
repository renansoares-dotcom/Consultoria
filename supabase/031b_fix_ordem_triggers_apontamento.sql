-- ============================================================================
-- MIGRAÇÃO 031b — Correção: unifica criação de unidade_produzida dentro de
-- fn_processar_apontamento, em vez de trigger separado.
--
-- Causa raiz do bug encontrado em teste: triggers disparam em ordem
-- alfabética do NOME no Postgres, não ordem de criação —
-- trg_criar_unidade_produzida rodava ANTES de trg_processar_apontamento e
-- tentava ler uma inspeção de qualidade que ainda não existia (ficava com
-- inspecao_qualidade_id sempre nulo). Unificar num único trigger AFTER
-- INSERT elimina esse tipo de fragilidade de vez — este arquivo é a versão
-- final e correta de fn_processar_apontamento (substitui a de 016/017/026).
-- ============================================================================

drop trigger if exists trg_criar_unidade_produzida on apontamentos_producao;
drop function if exists fn_criar_unidade_produzida();

create or replace function fn_processar_apontamento()
returns trigger as $$
declare
  v_op ordens_producao%rowtype;
  v_exige_inspecao boolean;
  v_inspecao_id uuid;
begin
  select * into v_op from ordens_producao where id = new.ordem_producao_id;

  update ordens_producao
  set quantidade_produzida = quantidade_produzida + new.quantidade,
      status = (case when quantidade_produzida + new.quantidade >= quantidade_planejada then 'concluida' else 'em_andamento' end)::status_ordem_producao,
      data_conclusao = case when quantidade_produzida + new.quantidade >= quantidade_planejada then new.data else data_conclusao end
  where id = new.ordem_producao_id;

  select inspecao_producao into v_exige_inspecao from produtos where id = v_op.produto_id;

  if v_exige_inspecao then
    update produtos set saldo_bloqueado = saldo_bloqueado + new.quantidade where id = v_op.produto_id;
    insert into inspecoes_qualidade (tenant_id, produto_id, origem, origem_id, quantidade)
    values (new.tenant_id, v_op.produto_id, 'apontamento_producao', new.id, new.quantidade)
    returning id into v_inspecao_id;
  else
    insert into estoque_movimentacoes (tenant_id, produto_id, tipo, quantidade, origem, origem_id, data, criado_por)
    values (new.tenant_id, v_op.produto_id, 'entrada', new.quantidade, 'apontamento_producao', new.ordem_producao_id, new.data, new.criado_por);
  end if;

  if v_op.pedido_venda_id is not null then
    update pedido_venda_itens
    set quantidade_atendida = quantidade_atendida + new.quantidade
    where pedido_venda_id = v_op.pedido_venda_id and produto_id = v_op.produto_id;
  end if;

  insert into unidades_produzidas (
    tenant_id, apontamento_producao_id, ordem_producao_id, produto_id,
    lote_interno, quantidade, unidade_medida, data_producao,
    situacao_qualidade, inspecao_qualidade_id
  )
  select
    new.tenant_id, new.id, new.ordem_producao_id, v_op.produto_id,
    v_op.numero_op, new.quantidade, p.unidade_medida, new.data,
    (case when v_exige_inspecao then 'aguardando' else 'nao_aplicavel' end)::situacao_qualidade_unidade,
    v_inspecao_id
  from produtos p where p.id = v_op.produto_id;

  return new;
end;
$$ language plpgsql security definer;
