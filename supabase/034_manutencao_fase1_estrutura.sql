-- ============================================================================
-- MIGRAÇÃO 034 — Manutenção Fase 1 (Estrutura e Cadastro) — 100% aditivo
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: primeiro corte
-- seguro da visão EAM+CMMS+APM trazida pelo Renan. Não renomeia nem altera
-- nenhuma coluna existente de "equipamentos" — só adiciona. ordens_manutencao
-- e o restante do MVP de Manutenção continuam funcionando idênticos.
-- ============================================================================

-- Hierarquia: planta > área > linha (auto-referenciada, sem enum pra não engessar o nível)
create table locais_funcionais (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references tenants(id) on delete cascade,
  nome        text not null,
  tipo        text not null default 'linha',   -- planta, area, linha — texto livre
  parent_id   uuid references locais_funcionais(id),
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now()
);
create index idx_locais_funcionais_parent on locais_funcionais(parent_id);

alter table equipamentos
  add column local_funcional_id uuid references locais_funcionais(id),
  add column criticidade text check (criticidade in ('baixa','media','alta','critica')),
  add column centro_custo_id uuid references centros_custo(id),
  add column responsavel_id uuid references usuarios(id);

create table ativos_componentes (
  id                        uuid primary key default gen_random_uuid(),
  tenant_id                 uuid not null references tenants(id) on delete cascade,
  equipamento_id            uuid not null references equipamentos(id) on delete cascade,
  nome                      text not null,
  numero_serie              text,
  data_instalacao           date,
  vida_util_estimada_horas  numeric(12,2),
  observacoes               text,
  ativo                     boolean not null default true,
  criado_em                 timestamptz not null default now()
);

create table ativos_documentos (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants(id) on delete cascade,
  equipamento_id  uuid not null references equipamentos(id) on delete cascade,
  tipo            text,          -- manual, foto, garantia, nota_fiscal... texto livre
  arquivo_path    text not null, -- bucket 'anexos' existente: {tenant_id}/ativos/{equipamento_id}/arquivo
  arquivo_nome    text not null,
  observacoes     text,
  enviado_por     uuid references usuarios(id),
  criado_em       timestamptz not null default now()
);

create table medidores (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants(id) on delete cascade,
  equipamento_id  uuid not null references equipamentos(id) on delete cascade,
  nome            text not null,      -- ex: Horímetro, Contador de Ciclos, Consumo de Energia
  unidade         text not null,      -- h, ciclos, km, kWh...
  leitura_atual   numeric(16,3) not null default 0,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now()
);

create table leituras_medidores (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants(id) on delete cascade,
  medidor_id      uuid not null references medidores(id) on delete cascade,
  leitura         numeric(16,3) not null,
  data_leitura    date not null default current_date,
  registrado_por  uuid references usuarios(id),
  observacoes     text,
  criado_em       timestamptz not null default now()
);

create index idx_ativos_componentes_equipamento on ativos_componentes(equipamento_id);
create index idx_ativos_documentos_equipamento on ativos_documentos(equipamento_id);
create index idx_medidores_equipamento on medidores(equipamento_id);
create index idx_leituras_medidor on leituras_medidores(medidor_id);

alter table locais_funcionais enable row level security;
create policy tenant_isolation_locais_funcionais on locais_funcionais
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table ativos_componentes enable row level security;
create policy tenant_isolation_ativos_componentes on ativos_componentes
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table ativos_documentos enable row level security;
create policy tenant_isolation_ativos_documentos on ativos_documentos
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table medidores enable row level security;
create policy tenant_isolation_medidores on medidores
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table leituras_medidores enable row level security;
create policy tenant_isolation_leituras_medidores on leituras_medidores
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- Toda leitura nova atualiza o valor atual do medidor (mostrado nas telas).
create or replace function fn_atualizar_leitura_medidor()
returns trigger as $$
begin
  update medidores set leitura_atual = new.leitura where id = new.medidor_id;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_atualizar_leitura_medidor
  after insert on leituras_medidores
  for each row execute function fn_atualizar_leitura_medidor();
