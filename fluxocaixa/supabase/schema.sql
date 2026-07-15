-- ============================================================================
-- FLUXO DE CAIXA — Schema Supabase (PostgreSQL)
-- Modelo: cada CLIENTE da consultoria é um tenant. Dentro de um tenant pode
-- existir mais de um "grupo empresarial" (como na planilha: IPLAMM, KRATOS...).
-- RLS isola tudo por tenant_id, para o cliente A nunca ver dado do cliente B.
-- ============================================================================

create extension if not exists "pgcrypto";

-- ----------------------------------------------------------------------------
-- 1. TENANTS (clientes da consultoria)
-- ----------------------------------------------------------------------------
create table tenants (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null,
  cnpj          text,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now()
);

-- Grupos empresariais dentro de um tenant (equivalente à aba 204_grupo)
create table grupos_empresariais (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references tenants(id) on delete cascade,
  nome          text not null,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. USUÁRIOS E NÍVEIS DE ACESSO
-- ----------------------------------------------------------------------------
create table perfis_acesso (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references tenants(id) on delete cascade, -- null = perfil padrão do sistema
  nome          text not null,               -- ex: Administrador, Financeiro, Visualização
  permissoes    jsonb not null default '{}', -- {"lancamentos":"rw","relatorios":"r","usuarios":"none",...}
  criado_em     timestamptz not null default now()
);

-- Estende auth.users do Supabase Auth com dados de negócio
create table usuarios (
  id            uuid primary key references auth.users(id) on delete cascade,
  tenant_id     uuid not null references tenants(id) on delete cascade,
  nome          text not null,
  email         text not null,
  perfil_id     uuid references perfis_acesso(id),
  grupos_permitidos uuid[] default null, -- restringe usuário a certos grupos_empresariais (null = todos)
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 3. CADASTROS (equivalentes às abas 201/202/203/205/206/207)
-- ----------------------------------------------------------------------------
create type tipo_plano_contas as enum ('entrada','saida','transferencia');

create table plano_contas (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references tenants(id) on delete cascade,
  tipo          tipo_plano_contas not null,
  codigo_grupo  text not null,         -- ex: "1.01"
  nome_grupo    text not null,         -- ex: "Receita de vendas"
  codigo_conta  text not null,         -- ex: "1.01.01"
  nome_conta    text not null,         -- ex: "Receita com vendas de produtos"
  ativo         boolean not null default true,
  ordem         integer,
  criado_em     timestamptz not null default now(),
  unique (tenant_id, codigo_conta)
);

create table contas_bancarias (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id uuid references grupos_empresariais(id),
  nome          text not null,          -- ex: BRADESCO
  disponibilidade text,                 -- ex: "Conta com recursos disponíveis"
  saldo_inicial numeric(16,2) not null default 0,
  data_saldo_inicial date,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now()
);

create table centros_custo (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references tenants(id) on delete cascade,
  nome          text not null,
  ativo         boolean not null default true
);

create type tipo_favorecido as enum ('fornecedores','clientes','funcionarios','socios','outros');

create table favorecidos (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references tenants(id) on delete cascade,
  tipo          tipo_favorecido not null,
  nome          text not null,
  segmento      text,
  cnpj_cpf      text,
  forma_pagamento text,
  dados_bancarios text,
  periodicidade text,
  ativo         boolean not null default true
);

-- ----------------------------------------------------------------------------
-- 4. LANÇAMENTOS (equivalente às abas 1..12 — todas unificadas em uma tabela)
-- ----------------------------------------------------------------------------
create type status_lancamento as enum ('pago','em_aberto','inadimplente');

create table lancamentos (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id uuid not null references grupos_empresariais(id),
  data            date not null,
  plano_conta_id  uuid not null references plano_contas(id),
  descricao       text,
  favorecido_id   uuid references favorecidos(id),
  centro_custo_id uuid references centros_custo(id),
  status          status_lancamento not null default 'em_aberto',
  conta_bancaria_id uuid not null references contas_bancarias(id),
  valor           numeric(16,2) not null,   -- positivo=entrada, negativo=saída (transferência usa par de lançamentos)
  data_pagamento  date,                     -- preenchido quando status muda para 'pago'
  data_vencimento date,                     -- para contas a receber/pagar em aberto
  observacoes     text,
  criado_por      uuid references usuarios(id),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);

create index idx_lancamentos_tenant_data on lancamentos(tenant_id, data);
create index idx_lancamentos_status on lancamentos(tenant_id, status);
create index idx_lancamentos_plano on lancamentos(plano_conta_id);
create index idx_lancamentos_grupo on lancamentos(grupo_empresarial_id);

-- ----------------------------------------------------------------------------
-- 5. BUDGET / FORECAST (equivalente às abas 6.x)
-- ----------------------------------------------------------------------------
create type tipo_orcamento as enum ('budget','forecast');

create table orcamentos (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id uuid not null references grupos_empresariais(id),
  tipo            tipo_orcamento not null,
  ano             integer not null,
  mes             integer not null check (mes between 1 and 12),
  plano_conta_id  uuid not null references plano_contas(id),
  valor_previsto  numeric(16,2) not null default 0,
  criado_em       timestamptz not null default now(),
  unique (tenant_id, grupo_empresarial_id, tipo, ano, mes, plano_conta_id)
);

-- ----------------------------------------------------------------------------
-- 6. AUDITORIA
-- ----------------------------------------------------------------------------
create table auditoria (
  id            bigint generated always as identity primary key,
  tenant_id     uuid not null references tenants(id) on delete cascade,
  usuario_id    uuid references usuarios(id),
  tabela        text not null,
  registro_id   uuid,
  acao          text not null,     -- insert | update | delete | login | export...
  dados_antes   jsonb,
  dados_depois  jsonb,
  ip            text,
  criado_em     timestamptz not null default now()
);
create index idx_auditoria_tenant on auditoria(tenant_id, criado_em desc);

-- ----------------------------------------------------------------------------
-- 7. CONFIGURAÇÕES
-- ----------------------------------------------------------------------------
create table configuracoes (
  tenant_id     uuid primary key references tenants(id) on delete cascade,
  nome_fantasia text,
  logo_url      text,
  moeda         text not null default 'BRL',
  ano_fiscal_inicio integer not null default 1,
  config_extra  jsonb not null default '{}'
);

-- ============================================================================
-- ROW LEVEL SECURITY — isolamento por tenant
-- ============================================================================
alter table grupos_empresariais enable row level security;
alter table usuarios enable row level security;
alter table plano_contas enable row level security;
alter table contas_bancarias enable row level security;
alter table centros_custo enable row level security;
alter table favorecidos enable row level security;
alter table lancamentos enable row level security;
alter table orcamentos enable row level security;
alter table auditoria enable row level security;
alter table configuracoes enable row level security;

-- Helper: tenant do usuário logado
create or replace function auth_tenant_id() returns uuid as $$
  select tenant_id from usuarios where id = auth.uid()
$$ language sql stable security definer;

-- Política padrão: só enxerga/edita linhas do próprio tenant
create policy tenant_isolation_select on lancamentos for select using (tenant_id = auth_tenant_id());
create policy tenant_isolation_all on lancamentos for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

create policy tenant_isolation_plano on plano_contas for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
create policy tenant_isolation_contas on contas_bancarias for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
create policy tenant_isolation_cc on centros_custo for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
create policy tenant_isolation_fav on favorecidos for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
create policy tenant_isolation_orc on orcamentos for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
create policy tenant_isolation_grupos on grupos_empresariais for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
create policy tenant_isolation_usuarios on usuarios for select using (tenant_id = auth_tenant_id());
create policy tenant_isolation_config on configuracoes for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
create policy tenant_isolation_audit_select on auditoria for select using (tenant_id = auth_tenant_id());

-- ============================================================================
-- TRIGGER DE AUDITORIA GENÉRICO (lançamentos como exemplo — replicar para
-- plano_contas, contas_bancarias, usuarios etc. conforme necessidade)
-- ============================================================================
create or replace function fn_auditoria() returns trigger as $$
begin
  insert into auditoria (tenant_id, usuario_id, tabela, registro_id, acao, dados_antes, dados_depois)
  values (
    coalesce(new.tenant_id, old.tenant_id),
    auth.uid(),
    tg_table_name,
    coalesce(new.id, old.id),
    lower(tg_op),
    case when tg_op in ('update','delete') then to_jsonb(old) else null end,
    case when tg_op in ('update','insert') then to_jsonb(new) else null end
  );
  return coalesce(new, old);
end;
$$ language plpgsql security definer;

create trigger trg_auditoria_lancamentos
  after insert or update or delete on lancamentos
  for each row execute function fn_auditoria();
