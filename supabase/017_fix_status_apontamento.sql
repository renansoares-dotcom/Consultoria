-- ============================================================================
-- MIGRAÇÃO 017 — Corrige erro de tipo no gatilho de apontamento
--
-- O CASE dentro do UPDATE retornava texto puro ('concluida'/'em_andamento'),
-- mas a coluna "status" é do tipo enum status_ordem_producao — precisa de
-- cast explícito. Só recria a função, não mexe em mais nada.
-- ============================================================================

create or replace function fn_processar_apontamento()
returns trigger as $$
declare
  v_op ordens_producao%rowtype;
begin
  select * into v_op from ordens_producao where id = new.ordem_producao_id;

  update ordens_producao
  set quantidade_produzida = quantidade_produzida + new.quantidade,
      status = (case when quantidade_produzida + new.quantidade >= quantidade_planejada then 'concluida' else 'em_andamento' end)::status_ordem_producao,
      data_conclusao = case when quantidade_produzida + new.quantidade >= quantidade_planejada then new.data else data_conclusao end
  where id = new.ordem_producao_id;

  insert into estoque_movimentacoes (tenant_id, produto_id, tipo, quantidade, origem, origem_id, data, criado_por)
  values (new.tenant_id, v_op.produto_id, 'entrada', new.quantidade, 'apontamento_producao', new.ordem_producao_id, new.data, new.criado_por);

  if v_op.pedido_venda_id is not null then
    update pedido_venda_itens
    set quantidade_atendida = quantidade_atendida + new.quantidade
    where pedido_venda_id = v_op.pedido_venda_id and produto_id = v_op.produto_id;
  end if;

  return new;
end;
$$ language plpgsql security definer;
