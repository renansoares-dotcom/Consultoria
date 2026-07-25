-- ============================================================================
-- MIGRAÇÃO 030 — Módulo RH (MVP): cadastro de funcionários, cargos, departamentos
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: só cadastro,
-- sem folha de pagamento/ponto/férias (domínio próprio enorme, fica em
-- Ideias Futuras). Fecha o último módulo placeholder do Bloco C.
-- ============================================================================

create table departamentos (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references tenants(id) on delete cascade,
  nome        text not null,
  ativo       boolean not null default true
);

create table cargos (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  nome              text not null,
  departamento_id   uuid references departamentos(id),
  ativo             boolean not null default true
);

create table funcionarios (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references tenants(id) on delete cascade,
  nome                text not null,
  cpf                 text,
  cargo_id            uuid references cargos(id),
  departamento_id     uuid references departamentos(id),
  data_admissao       date,
  data_desligamento   date,
  salario             numeric(16,2),
  status              text not null default 'ativo' check (status in ('ativo','desligado','afastado')),
  email               text,
  telefone            text,
  observacoes         text,
  criado_em           timestamptz not null default now()
);
create unique index idx_funcionarios_cpf on funcionarios(tenant_id, cpf) where cpf is not null;

alter table departamentos enable row level security;
create policy tenant_isolation_departamentos on departamentos
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table cargos enable row level security;
create policy tenant_isolation_cargos on cargos
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table funcionarios enable row level security;
create policy tenant_isolation_funcionarios on funcionarios
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
