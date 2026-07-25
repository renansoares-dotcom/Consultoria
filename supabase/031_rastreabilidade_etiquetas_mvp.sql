-- ============================================================================
-- MIGRAÇÃO 031 — Rastreabilidade e Etiquetas (MVP)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: unidade
-- produzida com identidade única, 1:1 com apontamento de produção; herda
-- situação de qualidade quando o produto exige inspeção; pallet agrupando
-- unidades; layout de etiqueta configurável (dimensões + campos visíveis,
-- escolhido manualmente ao imprimir); reimpressão auditável.
-- ============================================================================

create type situacao_qualidade_unidade as enum ('nao_aplicavel', 'aguardando', 'aprovada', 'reprovada', 'aprovada_parcial');
create type status_unidade_logistica as enum ('aberta', 'fechada', 'expedida');

create table unidades_logisticas (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  codigo_identificador  uuid not null default gen_random_uuid(),
  tipo                  text not null default 'pallet',   -- pallet, carga... texto livre
  status                status_unidade_logistica not null default 'aberta',
  observacoes           text,
  criado_por            uuid references usuarios(id),
  criado_em             timestamptz not null default now()
);
create unique index idx_unidades_logisticas_codigo on unidades_logisticas(codigo_identificador);

create table unidades_produzidas (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references tenants(id) on delete cascade,
  codigo_identificador    uuid not null default gen_random_uuid(),   -- o que vira código de barras/QR
  apontamento_producao_id uuid not null references apontamentos_producao(id),
  ordem_producao_id       uuid not null references ordens_producao(id),
  produto_id              uuid not null references produtos(id),
  lote_interno            text,                -- por padrão, o próprio número da OP
  quantidade              numeric(16,3) not null,
  unidade_medida          text not null,
  maquina_linha           text,
  data_producao           date not null default current_date,
  situacao_qualidade      situacao_qualidade_unidade not null default 'nao_aplicavel',
  inspecao_qualidade_id   uuid references inspecoes_qualidade(id),
  pallet_id               uuid references unidades_logisticas(id),
  criado_em               timestamptz not null default now()
);
create unique index idx_unidades_produzidas_codigo on unidades_produzidas(codigo_identificador);
create unique index idx_unidades_produzidas_apontamento on unidades_produzidas(apontamento_producao_id);
create index idx_unidades_produzidas_op on unidades_produzidas(ordem_producao_id);
create index idx_unidades_produzidas_pallet on unidades_produzidas(pallet_id);

create table layouts_etiqueta (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  nome                  text not null,
  grupo_empresarial_id  uuid references grupos_empresariais(id),
  cliente_id            uuid references favorecidos(id),
  embalagem_tipo        text,
  largura_mm            integer not null default 100,
  altura_mm             integer not null default 60,
  mostrar_produto       boolean not null default true,
  mostrar_lote          boolean not null default true,
  mostrar_op            boolean not null default true,
  mostrar_quantidade    boolean not null default true,
  mostrar_data          boolean not null default true,
  mostrar_maquina       boolean not null default false,
  mostrar_cliente       boolean not null default false,
  mostrar_qualidade     boolean not null default false,
  padrao                boolean not null default false,
  ativo                 boolean not null default true,
  criado_em             timestamptz not null default now()
);

create table reimpressoes_etiqueta (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  unidade_produzida_id  uuid references unidades_produzidas(id),
  unidade_logistica_id  uuid references unidades_logisticas(id),
  motivo                text not null,
  usuario_id            uuid references usuarios(id),
  criado_em             timestamptz not null default now(),
  check (unidade_produzida_id is not null or unidade_logistica_id is not null)
);

alter table unidades_logisticas enable row level security;
create policy tenant_isolation_unidades_logisticas on unidades_logisticas
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table unidades_produzidas enable row level security;
create policy tenant_isolation_unidades_produzidas on unidades_produzidas
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table layouts_etiqueta enable row level security;
create policy tenant_isolation_layouts_etiqueta on layouts_etiqueta
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table reimpressoes_etiqueta enable row level security;
create policy tenant_isolation_reimpressoes_etiqueta on reimpressoes_etiqueta
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- Rastreabilidade completa ao bipar: OP, produto, apontamento, qualidade, pallet.
-- ----------------------------------------------------------------------------
create or replace view vw_rastreabilidade_unidade as
select
  up.id as unidade_produzida_id,
  up.tenant_id,
  up.codigo_identificador,
  up.lote_interno,
  up.quantidade,
  up.unidade_medida,
  up.data_producao,
  up.maquina_linha,
  up.situacao_qualidade,
  (up.situacao_qualidade in ('nao_aplicavel','aprovada','aprovada_parcial')) as liberada,
  p.codigo as produto_codigo, p.nome as produto_nome,
  op.numero_op,
  ap.turno, ap.quantidade_refugo,
  iq.motivo_reprovacao,
  ul.codigo_identificador as pallet_codigo, ul.status as pallet_status
from unidades_produzidas up
join produtos p on p.id = up.produto_id
join ordens_producao op on op.id = up.ordem_producao_id
join apontamentos_producao ap on ap.id = up.apontamento_producao_id
left join inspecoes_qualidade iq on iq.id = up.inspecao_qualidade_id
left join unidades_logisticas ul on ul.id = up.pallet_id;

alter view vw_rastreabilidade_unidade set (security_invoker = on);
