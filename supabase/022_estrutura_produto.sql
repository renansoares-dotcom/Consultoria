-- ============================================================================
-- MIGRAÇÃO 022 — Estrutura de Produto (BOM)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: BOM como tela
-- dentro do cadastro de Produtos existente (Estoque), não página nova.
-- Cálculo de necessidade de material (Elo Produção↔Compras) fica pra Ordem 9.
-- ============================================================================

create table estrutura_produto_itens (
  id                     uuid primary key default gen_random_uuid(),
  tenant_id              uuid not null references tenants(id) on delete cascade,
  produto_id             uuid not null references produtos(id) on delete cascade,   -- produto acabado (pai)
  componente_id          uuid not null references produtos(id),                     -- matéria-prima/insumo (filho)
  quantidade_por_unidade numeric(16,4) not null check (quantidade_por_unidade > 0),
  observacoes            text,
  criado_por             uuid references usuarios(id),
  criado_em              timestamptz not null default now(),
  unique (tenant_id, produto_id, componente_id),
  check (produto_id <> componente_id)
);

create index idx_estrutura_produto_produto on estrutura_produto_itens(produto_id);
create index idx_estrutura_produto_componente on estrutura_produto_itens(componente_id);

alter table estrutura_produto_itens enable row level security;
create policy tenant_isolation_estrutura_produto on estrutura_produto_itens
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

comment on table estrutura_produto_itens is
  'Bill of Materials (BOM) / Ficha Técnica: para cada produto acabado, os componentes (matéria-prima/insumo) e a quantidade necessária por unidade produzida.';
