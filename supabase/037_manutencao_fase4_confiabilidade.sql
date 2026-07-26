-- ============================================================================
-- MIGRAÇÃO 037 — Manutenção Fase 4 (Confiabilidade e Análise de Falhas)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026. 100% aditivo.
-- ============================================================================

create table falhas_ativos (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references tenants(id) on delete cascade,
  codigo      text,
  nome        text not null,
  categoria   text,   -- mecânica, elétrica, hidráulica, pneumática, operacional... texto livre
  descricao   text,
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now()
);

alter table ordens_manutencao add column falha_id uuid references falhas_ativos(id);

create table paradas_producao (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  equipamento_id        uuid not null references equipamentos(id),
  ordem_manutencao_id   uuid references ordens_manutencao(id),
  ordem_producao_id     uuid references ordens_producao(id),
  falha_id              uuid references falhas_ativos(id),
  inicio                timestamptz not null default now(),
  fim                   timestamptz,
  causa                 text,
  quantidade_perdida    numeric(16,3),
  impacto_estimado      numeric(16,2),
  registrado_por        uuid references usuarios(id),
  criado_em             timestamptz not null default now(),
  check (fim is null or fim > inicio)
);
create index idx_paradas_producao_equipamento on paradas_producao(equipamento_id);
create index idx_paradas_producao_om on paradas_producao(ordem_manutencao_id);

create table analises_causa_raiz (
  id                          uuid primary key default gen_random_uuid(),
  tenant_id                   uuid not null references tenants(id) on delete cascade,
  ordem_manutencao_id         uuid references ordens_manutencao(id),
  parada_id                   uuid references paradas_producao(id),
  metodo                      text,   -- 5 porquês, Ishikawa... texto livre
  descricao_analise           text not null,
  causa_raiz_identificada     text,
  responsavel_id              uuid references usuarios(id),
  data_analise                date not null default current_date,
  criado_em                   timestamptz not null default now(),
  check (ordem_manutencao_id is not null or parada_id is not null)
);
create index idx_analises_causa_raiz_om on analises_causa_raiz(ordem_manutencao_id);

create table acoes_confiabilidade (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  analise_id        uuid not null references analises_causa_raiz(id) on delete cascade,
  descricao         text not null,
  responsavel_id    uuid references usuarios(id),
  prazo             date,
  status            text not null default 'pendente' check (status in ('pendente','em_andamento','concluida','cancelada')),
  data_conclusao    date,
  criado_em         timestamptz not null default now()
);
create index idx_acoes_confiabilidade_analise on acoes_confiabilidade(analise_id);

alter table falhas_ativos enable row level security;
create policy tenant_isolation_falhas_ativos on falhas_ativos for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table paradas_producao enable row level security;
create policy tenant_isolation_paradas_producao on paradas_producao for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table analises_causa_raiz enable row level security;
create policy tenant_isolation_analises_causa_raiz on analises_causa_raiz for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table acoes_confiabilidade enable row level security;
create policy tenant_isolation_acoes_confiabilidade on acoes_confiabilidade for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- Ao encerrar uma parada vinculada a uma OS, soma o impacto estimado no
-- custo_parada_estimado da OS (Fase 3) automaticamente. Só soma uma vez —
-- protegido contra reprocessar em edições futuras de "fim".
create or replace function fn_registrar_impacto_parada()
returns trigger as $$
begin
  if new.fim is not null and new.ordem_manutencao_id is not null and new.impacto_estimado is not null
     and (tg_op = 'INSERT' or old.fim is null) then
    update ordens_manutencao set custo_parada_estimado = custo_parada_estimado + new.impacto_estimado where id = new.ordem_manutencao_id;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_registrar_impacto_parada
  after insert or update of fim on paradas_producao
  for each row execute function fn_registrar_impacto_parada();

-- ----------------------------------------------------------------------------
-- MTTR (duração média de reparo) e MTBF (tempo médio entre falhas), por
-- equipamento, calculados em tempo real via window function.
-- ----------------------------------------------------------------------------
create or replace view vw_paradas_com_gap as
select
  pp.*,
  extract(epoch from (pp.fim - pp.inicio)) / 3600 as duracao_horas,
  extract(epoch from (pp.inicio - lag(pp.fim) over (partition by pp.equipamento_id order by pp.inicio))) / 3600 as horas_desde_parada_anterior
from paradas_producao pp
where pp.fim is not null;

alter view vw_paradas_com_gap set (security_invoker = on);

create or replace view vw_confiabilidade_equipamento as
select
  eq.id as equipamento_id,
  eq.tenant_id,
  eq.codigo,
  eq.nome,
  count(pc.id) as total_paradas,
  round(avg(pc.duracao_horas)::numeric, 2) as mttr_horas,
  round(avg(pc.horas_desde_parada_anterior)::numeric, 2) as mtbf_horas,
  sum(pc.quantidade_perdida) as quantidade_total_perdida,
  sum(pc.impacto_estimado) as impacto_total_estimado
from equipamentos eq
left join vw_paradas_com_gap pc on pc.equipamento_id = eq.id
group by eq.id, eq.tenant_id, eq.codigo, eq.nome;

alter view vw_confiabilidade_equipamento set (security_invoker = on);
