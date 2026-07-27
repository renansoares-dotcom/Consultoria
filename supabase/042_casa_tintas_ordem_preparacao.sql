-- ============================================================================
-- Migration: 042_casa_tintas_ordem_preparacao
-- Módulo: Qualidade > Casa de Tintas (Slice 4 — Ordem de Preparação + Pesagem)
-- Data: 2026-07-26
--
-- Primeiro slice que efetivamente CONSOME os lotes de insumo (Slice 2) contra
-- uma receita aprovada e imutável (Slice 3). Reaproveita o padrão de
-- reserva/consumo já usado no Elo Produção↔Compras (reservar antes, consumir
-- na pesagem real — que pode divergir do planejado, é isso que "apontamento
-- real versus previsto" significa).
--
-- Escopo desta migration: só a reserva + pesagem/consumo. NÃO inclui ainda:
-- criação do lote de tinta preparada, etiqueta, retorno de máquina — isso é
-- Slice 5. Ao final desta migration, uma ordem "pesada" ainda não vira
-- fisicamente um lote de tinta; fecha só a Fase 1 de rastreabilidade de
-- consumo, que é pré-requisito pro Slice 5.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Enum isolado
-- ----------------------------------------------------------------------------
create type status_ordem_preparacao_tinta as enum (
  'aberta',
  'pesada',
  'cancelada'
);

-- ----------------------------------------------------------------------------
-- 2. Estende lotes_insumo_tinta com saldo_reservado (mesmo padrão de
--    produtos.saldo_reservado, já usado em Compras/PCP).
-- ----------------------------------------------------------------------------
alter table lotes_insumo_tinta add column saldo_reservado numeric not null default 0;

-- ----------------------------------------------------------------------------
-- 3. ordens_preparacao_tinta
-- ----------------------------------------------------------------------------
create table ordens_preparacao_tinta (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  receita_versao_id uuid not null references receitas_tinta_versoes(id),
  numero_ordem text not null,
  quantidade_planejada numeric not null,
  status status_ordem_preparacao_tinta not null default 'aberta',
  observacoes text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id),
  unique (tenant_id, numero_ordem)
);

create index idx_ordens_preparacao_tinta_tenant on ordens_preparacao_tinta(tenant_id);
create index idx_ordens_preparacao_tinta_versao on ordens_preparacao_tinta(receita_versao_id);

alter table ordens_preparacao_tinta enable row level security;

create policy tenant_isolation_ordens_preparacao_tinta on ordens_preparacao_tinta
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- Regra: só se pode abrir ordem contra versão de receita APROVADA — nunca
-- rascunho, em teste, bloqueada ou obsoleta. Garantido no banco, não só na UI.
create or replace function fn_validar_receita_aprovada_ordem()
returns trigger as $$
declare
  v_status status_receita_tinta;
begin
  select status into v_status from receitas_tinta_versoes where id = new.receita_versao_id;
  if v_status is distinct from 'aprovada' then
    raise exception 'Só é possível abrir ordem de preparação contra uma versão de receita aprovada (status atual: %).', v_status;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_validar_receita_aprovada_ordem
  before insert on ordens_preparacao_tinta
  for each row execute function fn_validar_receita_aprovada_ordem();

-- ----------------------------------------------------------------------------
-- 4. reservas_lote_insumo_tinta — reserva soft (não decrementa saldo_atual,
--    só saldo_reservado) por lote, pra cada ordem.
-- ----------------------------------------------------------------------------
create table reservas_lote_insumo_tinta (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  ordem_id uuid not null references ordens_preparacao_tinta(id) on delete cascade,
  lote_id uuid not null references lotes_insumo_tinta(id),
  insumo_id uuid not null references insumos_tinta(id),
  quantidade_reservada numeric not null check (quantidade_reservada > 0),
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id)
);

create index idx_reservas_lote_insumo_tinta_tenant on reservas_lote_insumo_tinta(tenant_id);
create index idx_reservas_lote_insumo_tinta_ordem on reservas_lote_insumo_tinta(ordem_id);
create index idx_reservas_lote_insumo_tinta_lote on reservas_lote_insumo_tinta(lote_id);

alter table reservas_lote_insumo_tinta enable row level security;

create policy tenant_isolation_reservas_lote_insumo_tinta on reservas_lote_insumo_tinta
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- Mantém lotes_insumo_tinta.saldo_reservado em sincronia com as reservas,
-- com a mesma trava de "não pode passar do disponível" já usada pro saldo
-- real na Slice 2.
create or replace function fn_sincronizar_saldo_reservado_lote()
returns trigger as $$
declare
  v_delta numeric;
  v_lote_id uuid;
  v_saldo_atual numeric;
  v_saldo_reservado_resultante numeric;
begin
  if tg_op = 'INSERT' then
    v_delta := new.quantidade_reservada;
    v_lote_id := new.lote_id;
  elsif tg_op = 'DELETE' then
    v_delta := -old.quantidade_reservada;
    v_lote_id := old.lote_id;
  else -- UPDATE
    v_delta := new.quantidade_reservada - old.quantidade_reservada;
    v_lote_id := new.lote_id;
  end if;

  select saldo_atual, saldo_reservado + v_delta into v_saldo_atual, v_saldo_reservado_resultante
  from lotes_insumo_tinta where id = v_lote_id;

  if v_saldo_reservado_resultante > v_saldo_atual then
    raise exception 'Reserva excede o saldo disponível do lote (saldo atual %, reserva resultante seria %).', v_saldo_atual, v_saldo_reservado_resultante;
  end if;

  update lotes_insumo_tinta set saldo_reservado = greatest(0, v_saldo_reservado_resultante) where id = v_lote_id;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_sincronizar_saldo_reservado_lote
  after insert or update or delete on reservas_lote_insumo_tinta
  for each row execute function fn_sincronizar_saldo_reservado_lote();

-- ----------------------------------------------------------------------------
-- 5. pesagens_preparacao_tinta — o apontamento real. Consome o lote de
--    verdade (movimentação 'saida') e libera a reserva correspondente.
-- ----------------------------------------------------------------------------
create table pesagens_preparacao_tinta (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  ordem_id uuid not null references ordens_preparacao_tinta(id) on delete cascade,
  receita_item_id uuid not null references receitas_tinta_itens(id),
  insumo_id uuid not null references insumos_tinta(id),
  lote_id uuid not null references lotes_insumo_tinta(id),
  quantidade_planejada numeric not null,
  quantidade_pesada numeric not null check (quantidade_pesada > 0),
  balanca_equipamento text,
  operador_id uuid references usuarios(id),
  pesado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id)
);

create index idx_pesagens_preparacao_tinta_tenant on pesagens_preparacao_tinta(tenant_id);
create index idx_pesagens_preparacao_tinta_ordem on pesagens_preparacao_tinta(ordem_id);

alter table pesagens_preparacao_tinta enable row level security;

create policy tenant_isolation_pesagens_preparacao_tinta on pesagens_preparacao_tinta
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

create or replace function fn_processar_pesagem_preparacao_tinta()
returns trigger as $$
begin
  -- 1. Consumo real do lote (dispara o trigger de saldo já existente da
  --    Slice 2, inclusive o bloqueio de saldo negativo).
  insert into movimentacoes_estoque_tinta (tenant_id, lote_id, tipo, quantidade, origem, origem_id, criado_por)
  values (new.tenant_id, new.lote_id, 'saida', new.quantidade_pesada, 'consumo_preparacao', new.ordem_id, new.criado_por);

  -- 2. Libera a reserva correspondente por inteiro. Uma pesagem é um evento
  --    único de "peguei deste lote para este item" — mesmo com pequeno
  --    desvio de peso (normal na prática), o envolvimento desse lote com
  --    esse item da ordem está encerrado, não deve sobrar reserva presa.
  --    (Se o mesmo item precisar de mais de um lote, é uma reserva e uma
  --    pesagem por lote — cada uma libera só a sua própria reserva.)
  delete from reservas_lote_insumo_tinta
  where ordem_id = new.ordem_id and lote_id = new.lote_id;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_processar_pesagem_preparacao_tinta
  after insert on pesagens_preparacao_tinta
  for each row execute function fn_processar_pesagem_preparacao_tinta();
