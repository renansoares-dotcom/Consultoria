-- ============================================================================
-- MIGRAÇÃO 025 — Módulo Compras (MVP): Pedido de Compra + Recebimento
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: fecha o ciclo
-- que a Fase 1 do Elo Produção↔Compras deixou em aberto — requisição
-- aprovada vira Pedido de Compra (consolidado por fornecedor), e o
-- recebimento gera entrada de estoque automaticamente, no mesmo padrão do
-- apontamento de produção (016). Sem cotação comparativa nesta versão
-- (registrada em Ideias Futuras).
-- ============================================================================

create type status_pedido_compra as enum ('aberto', 'enviado', 'recebido_parcial', 'recebido_total', 'cancelado');

create table pedidos_compra (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id  uuid references grupos_empresariais(id),
  numero_pedido         text,
  fornecedor_id         uuid not null references favorecidos(id),
  data_pedido           date not null default current_date,
  data_entrega_prevista date,
  status                status_pedido_compra not null default 'aberto',
  observacoes           text,
  criado_por            uuid references usuarios(id),
  criado_em             timestamptz not null default now()
);

create table pedido_compra_itens (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references tenants(id) on delete cascade,
  pedido_compra_id    uuid not null references pedidos_compra(id) on delete cascade,
  produto_id          uuid not null references produtos(id),
  quantidade          numeric(16,4) not null check (quantidade > 0),
  valor_unitario      numeric(16,4) not null default 0,
  quantidade_recebida numeric(16,4) not null default 0,
  requisicao_id       uuid references requisicoes_compra(id)   -- rastreabilidade: qual requisição originou este item (pode ser nulo — item avulso)
);

create index idx_pedidos_compra_status on pedidos_compra(tenant_id, status);
create index idx_pedido_compra_itens_pedido on pedido_compra_itens(pedido_compra_id);
create index idx_pedido_compra_itens_produto on pedido_compra_itens(produto_id);

alter table pedidos_compra enable row level security;
create policy tenant_isolation_pedidos_compra on pedidos_compra
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table pedido_compra_itens enable row level security;
create policy tenant_isolation_pedido_compra_itens on pedido_compra_itens
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- Recebimento: ao aumentar quantidade_recebida de um item, gera entrada de
-- estoque só pelo delta (evita duplicar se o valor for ajustado de novo), e
-- recalcula o status do pedido inteiro (parcial/total) automaticamente.
-- ----------------------------------------------------------------------------
create or replace function fn_processar_recebimento_item()
returns trigger as $$
declare
  v_total_itens numeric;
  v_total_recebido numeric;
begin
  if new.quantidade_recebida > old.quantidade_recebida then
    insert into estoque_movimentacoes (tenant_id, produto_id, tipo, quantidade, origem, origem_id)
    values (new.tenant_id, new.produto_id, 'entrada', new.quantidade_recebida - old.quantidade_recebida, 'recebimento_compra', new.pedido_compra_id);
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

create trigger trg_processar_recebimento_item
  after update of quantidade_recebida on pedido_compra_itens
  for each row execute function fn_processar_recebimento_item();
