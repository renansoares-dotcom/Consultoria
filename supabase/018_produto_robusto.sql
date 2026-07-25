-- ============================================================================
-- MIGRAÇÃO 018 — Cadastro de Produto robusto
-- Baseado no padrão real de ERPs industriais (print de referência do
-- usuário), adaptado para Indústria de Plásticos Flexíveis (filmes, sacos,
-- bobinas) — largura, espessura (micragem) e peso são específicos desse
-- segmento, além da classificação hierárquica, estoque avançado e fiscal
-- básico que qualquer indústria precisa.
--
-- NOTA (25/07/2026): este arquivo estava registrado no Notion como aplicado,
-- mas foi confirmado que NUNCA chegou a rodar no banco de produção — nenhuma
-- destas colunas existe em `produtos`. Recuperado do Renan em 25/07/2026.
-- Aguardando decisão sobre aplicar agora ou revisar antes.
-- ============================================================================

alter table produtos
  -- Classificação
  add column if not exists grupo text,
  add column if not exists subgrupo text,
  add column if not exists classe text,
  add column if not exists referencia text,

  -- Fiscal básico
  add column if not exists ncm text,
  add column if not exists codigo_barras text,

  -- Dimensões e peso — específico de filmes/bobinas/embalagens flexíveis
  add column if not exists largura_mm numeric(10,2),
  add column if not exists espessura_micras numeric(10,2),
  add column if not exists comprimento_m numeric(12,3),
  add column if not exists peso_liquido numeric(12,4),
  add column if not exists peso_bruto numeric(12,4),

  -- Estoque avançado
  add column if not exists gera_estoque boolean not null default true,
  add column if not exists localizacao text,
  add column if not exists estoque_maximo numeric(16,3),
  add column if not exists lote_economico numeric(16,3),
  add column if not exists lote_minimo numeric(16,3),
  add column if not exists ponto_pedido numeric(16,3),

  -- Preços de referência
  add column if not exists preco_venda numeric(16,4),
  add column if not exists preco_reposicao numeric(16,4),

  -- Qualidade
  add column if not exists inspecao_aquisicao boolean not null default false,
  add column if not exists inspecao_producao boolean not null default false,

  add column if not exists observacoes text;

-- ----------------------------------------------------------------------------
-- Fornecedores homologados por produto (aba "Correntistas" do exemplo)
-- ----------------------------------------------------------------------------
create table produto_fornecedores (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references tenants(id) on delete cascade,
  produto_id          uuid not null references produtos(id) on delete cascade,
  fornecedor_id       uuid not null references favorecidos(id),
  codigo_no_fornecedor text,
  preco_ultima_compra numeric(16,4),
  data_ultima_compra  date,
  ativo               boolean not null default true
);

alter table produto_fornecedores enable row level security;
create policy tenant_isolation_produto_fornecedores on produto_fornecedores for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
