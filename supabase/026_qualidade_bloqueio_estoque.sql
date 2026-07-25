-- ============================================================================
-- MIGRAÇÃO 026 — Qualidade: bloqueio real de estoque via inspeção
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: dá significado
-- real às flags inspecao_aquisicao/inspecao_producao (existiam desde a
-- migration 018, sem lógica nenhuma). Quando ativas, o material entra em
-- saldo_bloqueado em vez de saldo_atual até ser inspecionado. Produtos sem
-- essas flags (padrão) continuam exatamente como antes — mudança opt-in,
-- sem regressão nos fluxos de Compras/Produção já em produção.
-- ============================================================================

alter table produtos add column saldo_bloqueado numeric(16,3) not null default 0;

create type status_inspecao_qualidade as enum ('pendente', 'aprovada', 'reprovada', 'aprovada_parcial');
create type origem_inspecao_qualidade as enum ('recebimento_compra', 'apontamento_producao');

create table inspecoes_qualidade (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references tenants(id) on delete cascade,
  produto_id          uuid not null references produtos(id),
  origem              origem_inspecao_qualidade not null,
  origem_id           uuid not null,   -- id do pedido_compra_itens ou do apontamento_producao que gerou a necessidade de inspeção
  quantidade          numeric(16,4) not null check (quantidade > 0),
  status              status_inspecao_qualidade not null default 'pendente',
  quantidade_aprovada numeric(16,4) not null default 0,
  quantidade_reprovada numeric(16,4) not null default 0,
  motivo_reprovacao   text,
  inspecionado_por    uuid references usuarios(id),
  inspecionado_em     timestamptz,
  criado_em           timestamptz not null default now()
);

create index idx_inspecoes_qualidade_status on inspecoes_qualidade(tenant_id, status);
create index idx_inspecoes_qualidade_produto on inspecoes_qualidade(produto_id);

alter table inspecoes_qualidade enable row level security;
create policy tenant_isolation_inspecoes_qualidade on inspecoes_qualidade
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- Recebimento de compra: se o produto exige inspeção na aquisição, o delta
-- recebido vai pro saldo_bloqueado + gera inspeção pendente, em vez de
-- entrar direto no estoque disponível.
-- ----------------------------------------------------------------------------
create or replace function fn_processar_recebimento_item()
returns trigger as $$
declare
  v_total_itens numeric;
  v_total_recebido numeric;
  v_exige_inspecao boolean;
begin
  if new.quantidade_recebida > old.quantidade_recebida then
    select inspecao_aquisicao into v_exige_inspecao from produtos where id = new.produto_id;

    if v_exige_inspecao then
      update produtos set saldo_bloqueado = saldo_bloqueado + (new.quantidade_recebida - old.quantidade_recebida) where id = new.produto_id;
      insert into inspecoes_qualidade (tenant_id, produto_id, origem, origem_id, quantidade)
      values (new.tenant_id, new.produto_id, 'recebimento_compra', new.id, new.quantidade_recebida - old.quantidade_recebida);
    else
      insert into estoque_movimentacoes (tenant_id, produto_id, tipo, quantidade, origem, origem_id)
      values (new.tenant_id, new.produto_id, 'entrada', new.quantidade_recebida - old.quantidade_recebida, 'recebimento_compra', new.pedido_compra_id);
    end if;
  end if;

  select sum(quantidade), sum(quantidade_recebida) into v_total_itens, v_total_recebido
  from pedido_compra_itens where pedido_compra_id = new.pedido_compra_id;

  update pedidos_compra
  set status = (case
    when v_total_recebido >= v_total_itens then 'recebido_total'
    when v_total_recebido > 0 then 'recebido_parcial'
    else status
  end)::status_pedido_compra
  where id = new.pedido_compra_id;

  return new;
end;
$$ language plpgsql security definer;

-- ----------------------------------------------------------------------------
-- Apontamento de produção: se o produto acabado exige inspeção, a produção
-- apontada vai pro saldo_bloqueado + gera inspeção pendente, em vez de
-- entrar direto no estoque disponível (mesma lógica do recebimento).
-- ----------------------------------------------------------------------------
create or replace function fn_processar_apontamento()
returns trigger as $$
declare
  v_op ordens_producao%rowtype;
  v_exige_inspecao boolean;
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
    values (new.tenant_id, v_op.produto_id, 'apontamento_producao', new.id, new.quantidade);
  else
    insert into estoque_movimentacoes (tenant_id, produto_id, tipo, quantidade, origem, origem_id, data, criado_por)
    values (new.tenant_id, v_op.produto_id, 'entrada', new.quantidade, 'apontamento_producao', new.ordem_producao_id, new.data, new.criado_por);
  end if;

  if v_op.pedido_venda_id is not null then
    update pedido_venda_itens
    set quantidade_atendida = quantidade_atendida + new.quantidade
    where pedido_venda_id = v_op.pedido_venda_id and produto_id = v_op.produto_id;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- ----------------------------------------------------------------------------
-- Decisão da inspeção: sai do bloqueado; o que for aprovado vira estoque
-- disponível de verdade (nova movimentação); o reprovado só sai do
-- bloqueado e nunca chega ao saldo_atual (perda/descarte).
-- ----------------------------------------------------------------------------
create or replace function fn_processar_decisao_inspecao()
returns trigger as $$
begin
  if old.status = 'pendente' and new.status in ('aprovada', 'reprovada', 'aprovada_parcial') then
    update produtos set saldo_bloqueado = saldo_bloqueado - new.quantidade where id = new.produto_id;

    if new.quantidade_aprovada > 0 then
      insert into estoque_movimentacoes (tenant_id, produto_id, tipo, quantidade, origem, origem_id, criado_por)
      values (new.tenant_id, new.produto_id, 'entrada', new.quantidade_aprovada, 'liberacao_qualidade', new.id, new.inspecionado_por);
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_processar_decisao_inspecao
  after update of status on inspecoes_qualidade
  for each row execute function fn_processar_decisao_inspecao();
