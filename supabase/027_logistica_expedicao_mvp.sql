-- ============================================================================
-- MIGRAÇÃO 027 — Logística/Expedição (MVP)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: expedição gera
-- saída de estoque real e fecha o pedido de venda (status 'faturado' —
-- reaproveitado, sem novo enum) automaticamente quando tudo for despachado.
-- ============================================================================

create table expedicoes (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id  uuid references grupos_empresariais(id),
  numero_expedicao      text,
  pedido_venda_id       uuid not null references pedidos_venda(id),
  data_expedicao        date not null default current_date,
  transportadora        text,
  status                text not null default 'expedido' check (status in ('expedido','cancelado')),
  observacoes           text,
  criado_por            uuid references usuarios(id),
  criado_em             timestamptz not null default now()
);

create table expedicao_itens (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  expedicao_id          uuid not null references expedicoes(id) on delete cascade,
  pedido_venda_item_id  uuid not null references pedido_venda_itens(id),
  produto_id            uuid not null references produtos(id),
  quantidade            numeric(16,3) not null check (quantidade > 0)
);

create index idx_expedicoes_pedido on expedicoes(pedido_venda_id);
create index idx_expedicao_itens_expedicao on expedicao_itens(expedicao_id);
create index idx_expedicao_itens_pedido_item on expedicao_itens(pedido_venda_item_id);

alter table expedicoes enable row level security;
create policy tenant_isolation_expedicoes on expedicoes
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table expedicao_itens enable row level security;
create policy tenant_isolation_expedicao_itens on expedicao_itens
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- Ao expedir um item: gera saída de estoque real, e fecha o pedido de venda
-- (status 'faturado') quando a soma expedida cobrir o pedido inteiro.
-- ----------------------------------------------------------------------------
create or replace function fn_processar_expedicao_item()
returns trigger as $$
declare
  v_pedido_id uuid;
  v_total_pedido numeric;
  v_total_expedido numeric;
begin
  insert into estoque_movimentacoes (tenant_id, produto_id, tipo, quantidade, origem, origem_id, criado_por)
  values (new.tenant_id, new.produto_id, 'saida', new.quantidade, 'expedicao', new.expedicao_id, null);

  select pedido_venda_id into v_pedido_id from expedicoes where id = new.expedicao_id;

  select coalesce(sum(quantidade), 0) into v_total_pedido
  from pedido_venda_itens where pedido_venda_id = v_pedido_id;

  select coalesce(sum(ei.quantidade), 0) into v_total_expedido
  from expedicao_itens ei
  join expedicoes e on e.id = ei.expedicao_id
  where e.pedido_venda_id = v_pedido_id and e.status = 'expedido';

  if v_total_expedido >= v_total_pedido then
    update pedidos_venda set status = 'faturado' where id = v_pedido_id and status <> 'cancelado';
  end if;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_processar_expedicao_item
  after insert on expedicao_itens
  for each row execute function fn_processar_expedicao_item();

-- ----------------------------------------------------------------------------
-- Worklist: o que já foi produzido (quantidade_atendida) mas ainda não saiu
-- fisicamente pro cliente.
-- ----------------------------------------------------------------------------
create or replace view vw_pedido_venda_a_expedir as
select
  pvi.id as pedido_venda_item_id,
  pvi.tenant_id,
  pv.id as pedido_venda_id,
  pv.numero_pedido,
  pv.status as status_pedido,
  pv.cliente_id,
  pvi.produto_id,
  p.codigo, p.nome, p.unidade_medida,
  pvi.quantidade as quantidade_pedida,
  pvi.quantidade_atendida,
  coalesce(exp.total_expedido, 0) as quantidade_expedida,
  greatest(0, pvi.quantidade_atendida - coalesce(exp.total_expedido, 0)) as quantidade_disponivel_expedir
from pedido_venda_itens pvi
join pedidos_venda pv on pv.id = pvi.pedido_venda_id
join produtos p on p.id = pvi.produto_id
left join (
  select ei.pedido_venda_item_id, sum(ei.quantidade) as total_expedido
  from expedicao_itens ei
  join expedicoes e on e.id = ei.expedicao_id
  where e.status = 'expedido'
  group by ei.pedido_venda_item_id
) exp on exp.pedido_venda_item_id = pvi.id
where pv.status not in ('cancelado');

alter view vw_pedido_venda_a_expedir set (security_invoker = on);
