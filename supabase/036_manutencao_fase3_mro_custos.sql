-- ============================================================================
-- MIGRAÇÃO 036 — Manutenção Fase 3 (Peças MRO, Compras e Custos)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026. Reaproveita
-- Estoque/Compras/Elo Produção↔Compras já construídos — não duplica
-- infraestrutura. 100% aditivo.
-- ============================================================================

create type status_peca_os as enum ('reservada', 'consumida', 'cancelada');

alter table produtos add column saldo_reservado numeric(16,3) not null default 0;

alter table ordens_manutencao
  add column custo_servico_externo numeric(16,2) not null default 0,
  add column custo_parada_estimado numeric(16,2) not null default 0;

alter table requisicoes_compra add column ordem_manutencao_id uuid references ordens_manutencao(id);

create table pecas_os (
  id                        uuid primary key default gen_random_uuid(),
  tenant_id                 uuid not null references tenants(id) on delete cascade,
  ordem_manutencao_id       uuid not null references ordens_manutencao(id) on delete cascade,
  produto_id                uuid not null references produtos(id),
  quantidade                numeric(16,3) not null check (quantidade > 0),
  valor_unitario_estimado   numeric(16,4) not null default 0,
  status                    status_peca_os not null default 'reservada',
  registrado_por            uuid references usuarios(id),
  criado_em                 timestamptz not null default now()
);
create index idx_pecas_os_ordem on pecas_os(ordem_manutencao_id);
create index idx_pecas_os_produto on pecas_os(produto_id);

alter table pecas_os enable row level security;
create policy tenant_isolation_pecas_os on pecas_os
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- Ao reservar (insert), separa o saldo pra essa OS sem ainda baixar do estoque.
create or replace function fn_reservar_peca_os()
returns trigger as $$
begin
  update produtos set saldo_reservado = saldo_reservado + new.quantidade where id = new.produto_id;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_reservar_peca_os
  after insert on pecas_os
  for each row execute function fn_reservar_peca_os();

-- Ao consumir: libera a reserva, baixa o estoque de verdade (mesmo padrão de
-- toda saída do sistema) e soma no custo de peças da OS automaticamente.
-- Ao cancelar: só libera a reserva, nada foi consumido.
create or replace function fn_processar_mudanca_status_peca_os()
returns trigger as $$
begin
  if old.status = 'reservada' and new.status in ('consumida', 'cancelada') then
    update produtos set saldo_reservado = saldo_reservado - new.quantidade where id = new.produto_id;

    if new.status = 'consumida' then
      insert into estoque_movimentacoes (tenant_id, produto_id, tipo, quantidade, origem, origem_id, criado_por)
      values (new.tenant_id, new.produto_id, 'saida', new.quantidade, 'consumo_manutencao', new.ordem_manutencao_id, new.registrado_por);

      update ordens_manutencao
      set custo_pecas = custo_pecas + (new.quantidade * new.valor_unitario_estimado)
      where id = new.ordem_manutencao_id;
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_processar_mudanca_status_peca_os
  after update of status on pecas_os
  for each row execute function fn_processar_mudanca_status_peca_os();

-- Necessidade consolidada: novo saldo_reservado é acrescentado NO FINAL da
-- lista de colunas (regra do Postgres para CREATE OR REPLACE VIEW).
create or replace view vw_necessidade_consolidada as
select
  p.id as produto_id,
  p.tenant_id,
  p.codigo,
  p.nome,
  p.unidade_medida,
  p.saldo_atual,
  coalesce(p.saldo_minimo, 0) as saldo_minimo,
  coalesce(nm.necessidade_total, 0) as necessidade_producao,
  coalesce(rc.ja_requisitado, 0) as ja_requisitado_em_aberto,
  greatest(0,
    coalesce(nm.necessidade_total, 0) + coalesce(p.saldo_minimo, 0) - p.saldo_atual - coalesce(rc.ja_requisitado, 0) + coalesce(p.saldo_reservado, 0)
  ) as necessidade_liquida,
  p.saldo_reservado
from produtos p
left join (
  select componente_id, tenant_id, sum(necessidade_bruta) as necessidade_total
  from vw_necessidade_op_material
  group by componente_id, tenant_id
) nm on nm.componente_id = p.id and nm.tenant_id = p.tenant_id
left join (
  select produto_id, tenant_id, sum(quantidade_solicitada) as ja_requisitado
  from requisicoes_compra
  where status in ('pendente', 'aprovada')
  group by produto_id, tenant_id
) rc on rc.produto_id = p.id and rc.tenant_id = p.tenant_id
where p.tipo in ('materia_prima', 'insumo', 'peca_manutencao') and p.ativo = true;

alter view vw_necessidade_consolidada set (security_invoker = on);

create or replace view vw_custo_manutencao as
select
  om.id as ordem_manutencao_id,
  om.tenant_id,
  om.tipo,
  om.prioridade,
  om.causa,
  om.status,
  om.data_abertura,
  om.data_conclusao,
  om.equipamento_id,
  eq.codigo as equipamento_codigo,
  eq.nome as equipamento_nome,
  eq.centro_custo_id,
  cc.nome as centro_custo_nome,
  om.custo_pecas,
  om.custo_mao_obra,
  om.custo_servico_externo,
  om.custo_parada_estimado,
  (om.custo_pecas + om.custo_mao_obra + om.custo_servico_externo + om.custo_parada_estimado) as custo_total
from ordens_manutencao om
join equipamentos eq on eq.id = om.equipamento_id
left join centros_custo cc on cc.id = eq.centro_custo_id;

alter view vw_custo_manutencao set (security_invoker = on);
