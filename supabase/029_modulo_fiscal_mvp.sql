-- ============================================================================
-- MIGRAÇÃO 029 — Módulo Fiscal (MVP): registro e controle, sem emissão SEFAZ
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: registra e
-- rastreia NF-e (emitidas hoje pelo contador/emissor externo do Renan),
-- vinculando a pedidos de venda e expedições. NÃO assina, NÃO transmite,
-- NÃO calcula imposto real — isso exige certificado digital e definição de
-- emissor (motor próprio vs. integração terceira), fora do escopo seguro
-- deste ambiente.
-- ============================================================================

create type status_nota_fiscal as enum ('rascunho', 'emitida', 'cancelada', 'denegada');
create type tipo_nota_fiscal as enum ('entrada', 'saida');

create table notas_fiscais (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id  uuid references grupos_empresariais(id),
  numero                text,
  serie                 text,
  chave_acesso          text,
  tipo                  tipo_nota_fiscal not null default 'saida',
  natureza_operacao     text,
  data_emissao          date not null default current_date,
  valor_total           numeric(16,2) not null default 0,
  status                status_nota_fiscal not null default 'rascunho',
  pedido_venda_id       uuid references pedidos_venda(id),
  expedicao_id          uuid references expedicoes(id),
  favorecido_id         uuid references favorecidos(id),
  observacoes           text,
  criado_por            uuid references usuarios(id),
  criado_em             timestamptz not null default now()
);
create unique index idx_notas_fiscais_chave on notas_fiscais(tenant_id, chave_acesso) where chave_acesso is not null;
create index idx_notas_fiscais_pedido on notas_fiscais(pedido_venda_id);
create index idx_notas_fiscais_expedicao on notas_fiscais(expedicao_id);

create table notas_fiscais_itens (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  nota_fiscal_id    uuid not null references notas_fiscais(id) on delete cascade,
  produto_id        uuid references produtos(id),
  ncm               text,
  cfop              text,
  quantidade        numeric(16,4) not null default 0,
  valor_unitario    numeric(16,4) not null default 0,
  valor_total       numeric(16,2) not null default 0
);

alter table notas_fiscais enable row level security;
create policy tenant_isolation_notas_fiscais on notas_fiscais
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table notas_fiscais_itens enable row level security;
create policy tenant_isolation_notas_fiscais_itens on notas_fiscais_itens
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
