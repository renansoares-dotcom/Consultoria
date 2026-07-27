-- ============================================================================
-- Migration: 040_casa_tintas_estoque_insumo
-- Módulo: Qualidade > Casa de Tintas (Slice 2 — Estoque de insumo, Natureza A)
-- Data: 2026-07-26
--
-- Contexto: hoje o sistema NÃO tem conceito de lote em lugar nenhum —
-- produtos.saldo_atual é um agregado único, atualizado por
-- fn_atualizar_saldo_produto() a partir de estoque_movimentacoes (tipo
-- 'entrada'/'saida', coluna TEXT, não enum). Esta migration introduz
-- rastreamento por lote pela primeira vez, replicando o MESMO padrão de
-- trigger (movimento assinado -> saldo recalculado), agora por lote em vez
-- de por produto agregado.
--
-- Escopo: só a Natureza A (insumo novo). Natureza B (tinta preparada) e C
-- (retorno de máquina) vêm nos slices 042/043, quando existir ordem de
-- preparação pra consumir estes lotes.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Enum isolado (só o que é classificação fixa de verdade; "tipo" de
--    movimentação fica TEXT + CHECK, espelhando estoque_movimentacoes.tipo,
--    que também é TEXT — evita ALTER TYPE ADD VALUE no futuro pra novas
--    origens de movimento, que são texto livre, não enum).
-- ----------------------------------------------------------------------------
create type status_qualidade_lote_tinta as enum (
  'liberado',
  'quarentena',
  'bloqueado',
  'vencido'
);

-- ----------------------------------------------------------------------------
-- 2. lotes_insumo_tinta
-- ----------------------------------------------------------------------------
create table lotes_insumo_tinta (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  insumo_id uuid not null references insumos_tinta(id),
  numero_lote text not null,
  fornecedor_id uuid references favorecidos(id),   -- pode diferir do fornecedor padrão do insumo
  nota_fiscal text,
  quantidade_recebida numeric not null,
  saldo_atual numeric not null default 0,           -- mantido só pelo trigger, nunca editado direto
  custo_unitario numeric,
  data_recebimento date not null default current_date,
  data_validade date,
  status_qualidade status_qualidade_lote_tinta not null default 'liberado',
  observacoes text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id),
  unique (tenant_id, insumo_id, numero_lote)
);

create index idx_lotes_insumo_tinta_tenant on lotes_insumo_tinta(tenant_id);
create index idx_lotes_insumo_tinta_insumo on lotes_insumo_tinta(insumo_id);
create index idx_lotes_insumo_tinta_validade on lotes_insumo_tinta(data_validade);

alter table lotes_insumo_tinta enable row level security;

create policy tenant_isolation_lotes_insumo_tinta on lotes_insumo_tinta
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- 3. movimentacoes_estoque_tinta (mesmo padrão de estoque_movimentacoes)
-- ----------------------------------------------------------------------------
create table movimentacoes_estoque_tinta (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  lote_id uuid not null references lotes_insumo_tinta(id),
  tipo text not null check (tipo in ('entrada', 'saida')),
  quantidade numeric not null check (quantidade > 0),
  origem text not null,          -- 'recebimento_insumo' | 'ajuste_manual' (texto livre; novas origens não exigem migration)
  origem_id uuid,
  observacoes text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id)
);

create index idx_movimentacoes_estoque_tinta_tenant on movimentacoes_estoque_tinta(tenant_id);
create index idx_movimentacoes_estoque_tinta_lote on movimentacoes_estoque_tinta(lote_id);

alter table movimentacoes_estoque_tinta enable row level security;

create policy tenant_isolation_movimentacoes_estoque_tinta on movimentacoes_estoque_tinta
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- 4. Trigger: saldo do lote = soma dos movimentos assinados.
--    Bloqueia explicitamente saldo negativo (regra de negócio do documento
--    estratégico: "Estoque negativo não é permitido sem permissão
--    excepcional e log") — decisão: nesta fase, bloquear sempre, sem exceção
--    configurável ainda.
-- ----------------------------------------------------------------------------
create or replace function fn_atualizar_saldo_lote_tinta()
returns trigger as $$
declare
  v_saldo_resultante numeric;
begin
  select saldo_atual + case when new.tipo = 'entrada' then new.quantidade else -new.quantidade end
  into v_saldo_resultante
  from lotes_insumo_tinta
  where id = new.lote_id;

  if v_saldo_resultante < 0 then
    raise exception 'Saldo do lote ficaria negativo (%). Operação bloqueada.', v_saldo_resultante;
  end if;

  update lotes_insumo_tinta
  set saldo_atual = v_saldo_resultante
  where id = new.lote_id;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_atualizar_saldo_lote_tinta
  after insert on movimentacoes_estoque_tinta
  for each row execute function fn_atualizar_saldo_lote_tinta();

-- ----------------------------------------------------------------------------
-- 5. View auxiliar: saldo total por insumo (soma de todos os lotes ativos).
--    ATENÇÃO (aprendizado já registrado na Documentação Técnica): PostgREST
--    não consegue montar embed de FK através de uma view com GROUP BY. Esta
--    view é só para exibir números agregados — NUNCA fazer
--    `insumos_tinta!inner(...)` embutido a partir dela. Se precisar dos
--    dados do insumo junto, buscar insumos_tinta direto e juntar no
--    navegador pelo insumo_id, como já é feito em outros lugares do sistema.
-- ----------------------------------------------------------------------------
create view vw_saldo_insumo_tinta as
select
  insumo_id,
  sum(saldo_atual) as saldo_total,
  count(*) filter (where saldo_atual > 0) as lotes_com_saldo,
  min(data_validade) filter (where saldo_atual > 0) as proxima_validade
from lotes_insumo_tinta
group by insumo_id;
