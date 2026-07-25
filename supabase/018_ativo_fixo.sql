-- ============================================================================
-- MIGRAÇÃO 018 — Ativo Fixo (controle patrimonial + depreciação linear)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: controle
-- patrimonial com depreciação calculada (método linear), sem gerar
-- lançamento automático no Fluxo de Caixa nem no DRE nesta versão —
-- depreciação é despesa não-desembolsada, e a integração automática com o
-- DRE fica para uma próxima iteração (registrada em Ideias Futuras).
-- ============================================================================

create type categoria_ativo_fixo as enum (
  'maquinas_equipamentos', 'veiculos', 'moveis_utensilios', 'imoveis', 'informatica', 'outros'
);

create table ativos_fixos (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id uuid references grupos_empresariais(id),
  nome               text not null,
  categoria          categoria_ativo_fixo not null default 'outros',
  data_aquisicao     date not null,
  valor_aquisicao    numeric(16,2) not null,
  valor_residual     numeric(16,2) not null default 0,   -- valor estimado ao final da vida útil (0 = deprecia 100%)
  vida_util_meses    integer not null check (vida_util_meses > 0),
  conta_bancaria_id  uuid references contas_bancarias(id),  -- de onde saiu o dinheiro na compra, se aplicável
  observacoes        text,
  data_baixa         date,          -- preenchido quando o ativo é vendido/descartado
  valor_baixa        numeric(16,2), -- valor de venda, se houve
  motivo_baixa       text,
  criado_por         uuid references usuarios(id),
  criado_em          timestamptz not null default now()
);

create index idx_ativos_fixos_tenant on ativos_fixos(tenant_id);
create index idx_ativos_fixos_grupo on ativos_fixos(grupo_empresarial_id);

alter table ativos_fixos enable row level security;
create policy tenant_isolation_ativos_fixos on ativos_fixos
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- View de depreciação — método linear, calculado sempre "hoje" (não grava
-- histórico mês a mês; se no futuro precisar de posição em uma data
-- passada específica, basta trocar current_date por um parâmetro).
--
-- meses_decorridos: desde a aquisição até hoje (ou até a baixa, se baixado),
--   arredondado pra baixo — mês corrente só conta depois de completar.
-- depreciacao_acumulada: nunca passa de (valor_aquisicao - valor_residual),
--   mesmo que a vida útil já tenha sido ultrapassada.
-- valor_contabil_liquido: valor_aquisicao - depreciacao_acumulada.
-- ----------------------------------------------------------------------------
create or replace view vw_ativos_fixos_depreciacao as
select
  a.*,
  greatest(0,
    (extract(year from age(coalesce(a.data_baixa, current_date), a.data_aquisicao)) * 12
     + extract(month from age(coalesce(a.data_baixa, current_date), a.data_aquisicao)))::int
  ) as meses_decorridos,
  least(
    a.valor_aquisicao - a.valor_residual,
    greatest(0,
      (extract(year from age(coalesce(a.data_baixa, current_date), a.data_aquisicao)) * 12
       + extract(month from age(coalesce(a.data_baixa, current_date), a.data_aquisicao)))::int
    ) * ((a.valor_aquisicao - a.valor_residual) / a.vida_util_meses)
  ) as depreciacao_acumulada,
  a.valor_aquisicao - least(
    a.valor_aquisicao - a.valor_residual,
    greatest(0,
      (extract(year from age(coalesce(a.data_baixa, current_date), a.data_aquisicao)) * 12
       + extract(month from age(coalesce(a.data_baixa, current_date), a.data_aquisicao)))::int
    ) * ((a.valor_aquisicao - a.valor_residual) / a.vida_util_meses)
  ) as valor_contabil_liquido,
  (a.valor_aquisicao - a.valor_residual) / a.vida_util_meses as depreciacao_mensal
from ativos_fixos a;

alter view vw_ativos_fixos_depreciacao set (security_invoker = on);
