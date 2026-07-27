-- ============================================================================
-- Migration: 039_casa_tintas_cadastros
-- Módulo: Qualidade > Casa de Tintas (Slice 1 — Fundação / cadastros técnicos)
-- Data: 2026-07-26
-- Decisão associada (Product Decisions Log): Casa de Tintas nasce como
-- sub-módulo dentro de Qualidade.
--
-- Escopo desta migration: SOMENTE cadastros técnicos puros, sem movimentação
-- de estoque, sem receita, sem ordem de preparação. Slices seguintes:
--   040 - estoque de insumo (lotes_insumo_tinta, movimentacoes_estoque_tinta)
--   041 - receitas versionadas
--   042 - ordem de preparação + pesagem
--   043 - lote de tinta preparada, composição, custo, etiqueta
--
-- Convenções seguidas (Documentação Técnica do projeto):
--   - tenant_id em toda tabela + RLS "tenant_isolation_<tabela>" (ALL,
--     qual/with_check = tenant_id = auth_tenant_id()), nunca allow-all.
--   - criado_em timestamptz default now(), criado_por uuid -> usuarios(id).
--   - Nomenclatura de enum: tipo_<entidade>, alterações de enum sempre em
--     migration isolada (nunca ALTER TYPE ADD VALUE misturado com DDL de
--     tabela na mesma migration).
--   - "cores_tinta"/"padroes_cor_tinta" (não "cores"/"padroes_cor" como no
--     documento original) para não colidir conceitualmente com Cor/
--     Masterbatch já existente em Produção (segmento Plásticos) — são
--     domínios diferentes: cor de tinta de impressão x cor do polímero.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Enums isolados
-- ----------------------------------------------------------------------------
create type tipo_insumo_tinta as enum (
  'tinta_base',
  'pigmento_concentrado',
  'verniz',
  'solvente',
  'retardador',
  'diluente',
  'plastificante',
  'aditivo',
  'limpeza'
);

create type tipo_padrao_cor_tinta as enum (
  'pantone',
  'cliente',
  'instrumental'
);

-- ----------------------------------------------------------------------------
-- 2. sistemas_tinta (Solvente / Água / UV / etc.)
-- ----------------------------------------------------------------------------
create table sistemas_tinta (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  nome text not null,
  descricao text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id),
  unique (tenant_id, nome)
);

alter table sistemas_tinta enable row level security;

create policy tenant_isolation_sistemas_tinta on sistemas_tinta
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- 3. insumos_tinta (tintas-base, pigmentos, vernizes, solventes, aditivos...)
-- ----------------------------------------------------------------------------
create table insumos_tinta (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  codigo text not null,
  nome text not null,
  tipo tipo_insumo_tinta not null,
  sistema_tinta_id uuid references sistemas_tinta(id),
  unidade_medida text not null default 'KG',
  densidade_referencia numeric,          -- kg/L, temperatura de referência abaixo
  temperatura_referencia_c numeric,
  fornecedor_padrao_id uuid references favorecidos(id),
  custo_referencia numeric,
  ativo boolean not null default true,
  observacoes text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id),
  unique (tenant_id, codigo)
);

create index idx_insumos_tinta_tenant on insumos_tinta(tenant_id);
create index idx_insumos_tinta_sistema on insumos_tinta(sistema_tinta_id);

alter table insumos_tinta enable row level security;

create policy tenant_isolation_insumos_tinta on insumos_tinta
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- 4. especificacoes_seguranca_insumo (FISPQ / risco / EPI) — 1:1 com insumo
-- ----------------------------------------------------------------------------
create table especificacoes_seguranca_insumo (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  insumo_id uuid not null references insumos_tinta(id) on delete cascade,
  classe_risco text,                     -- texto livre (classificação GHS varia por produto)
  inflamavel boolean not null default false,
  ponto_fulgor_c numeric,
  epi_necessario text,
  local_armazenagem text,
  fispq_arquivo_path text,               -- bucket 'anexos', padrão {tenant_id}/casa-tintas/...
  fispq_arquivo_nome text,
  observacoes text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id),
  unique (insumo_id)
);

create index idx_especificacoes_seguranca_tenant on especificacoes_seguranca_insumo(tenant_id);

alter table especificacoes_seguranca_insumo enable row level security;

create policy tenant_isolation_especificacoes_seguranca_insumo on especificacoes_seguranca_insumo
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- 5. cores_tinta (cor de impressão — não confundir com Cor/Masterbatch de
--    Produção, que é o polímero)
-- ----------------------------------------------------------------------------
create table cores_tinta (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  codigo text not null,
  nome text not null,
  sistema_tinta_id uuid references sistemas_tinta(id),
  favorecido_id uuid references favorecidos(id),  -- cor exclusiva de cliente, quando aplicável
  ativo boolean not null default true,
  observacoes text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id),
  unique (tenant_id, codigo)
);

create index idx_cores_tinta_tenant on cores_tinta(tenant_id);
create index idx_cores_tinta_favorecido on cores_tinta(favorecido_id);

alter table cores_tinta enable row level security;

create policy tenant_isolation_cores_tinta on cores_tinta
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- 6. padroes_cor_tinta (Pantone / padrão do cliente / leitura instrumental)
-- ----------------------------------------------------------------------------
create table padroes_cor_tinta (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  cor_tinta_id uuid not null references cores_tinta(id) on delete cascade,
  tipo_padrao tipo_padrao_cor_tinta not null,
  codigo_pantone text,
  valor_l numeric,                       -- CIE L*a*b*, preparado para Fase 3 (espectrofotômetro)
  valor_a numeric,
  valor_b numeric,
  delta_e_tolerancia numeric,
  imagem_arquivo_path text,              -- bucket 'anexos'
  imagem_arquivo_nome text,
  observacoes text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id)
);

create index idx_padroes_cor_tinta_tenant on padroes_cor_tinta(tenant_id);
create index idx_padroes_cor_tinta_cor on padroes_cor_tinta(cor_tinta_id);

alter table padroes_cor_tinta enable row level security;

create policy tenant_isolation_padroes_cor_tinta on padroes_cor_tinta
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());
