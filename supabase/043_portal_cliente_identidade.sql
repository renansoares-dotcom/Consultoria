-- ============================================================================
-- Migration: 043_portal_cliente_identidade
-- Portal do Cliente — Slice 1 (login + Meus Pedidos, leitura)
-- Data: 2026-07-27
--
-- Decisão registrada no Product Decisions Log: identidade externa TOTALMENTE
-- separada de `usuarios`. Motivo estrutural, não estilístico: TODA política
-- de RLS do sistema depende de auth_tenant_id(), que faz
--   select tenant_id from usuarios where id = auth.uid()
-- Se um usuário-cliente ganhasse linha em `usuarios`, herdaria acesso de
-- leitura/escrita a TUDO do tenant (RH, Financeiro interno, etc). Por isso
-- `usuarios_portal` é uma tabela separada, nunca lida por auth_tenant_id(),
-- e as políticas do Portal são ADITIVAS por tabela — nunca uma política
-- genérica de tenant.
--
-- Propriedade de segurança verificável: um usuário-portal nunca existe em
-- `usuarios`, então auth_tenant_id() retorna NULL pra ele e TODAS as
-- políticas internas existentes (tenant_isolation_*) automaticamente negam
-- acesso, sem eu precisar tocar em nenhuma delas.
--
-- Escopo desta migration: só o necessário pra "Meus Pedidos" funcionar
-- (status do pedido, posição de produção, posição de expedição/entrega).
-- Financeiro (títulos/NF-e) e Solicitações (prorrogação) ficam pra um
-- próximo slice, só depois de validar esta fatia na tela.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Identidade do usuário do portal
-- ----------------------------------------------------------------------------
create table usuarios_portal (
  id uuid primary key,                          -- = auth.users.id (mesmo padrão de `usuarios`, sem FK cross-schema)
  tenant_id uuid not null references tenants(id),
  favorecido_id uuid not null references favorecidos(id),  -- o cliente que este login representa
  nome text not null,
  email text not null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id),
  unique (tenant_id, email)
);

create index idx_usuarios_portal_tenant on usuarios_portal(tenant_id);
create index idx_usuarios_portal_favorecido on usuarios_portal(favorecido_id);

alter table usuarios_portal enable row level security;

-- Só colaborador interno gerencia usuários do portal (criar/editar/desativar).
-- O próprio usuário-portal NUNCA lê esta tabela — não precisa, no MVP.
create policy tenant_isolation_usuarios_portal on usuarios_portal
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- O próprio usuário do portal pode ler (só ler, nunca editar) o PRÓPRIO
-- registro — necessário pro login carregar nome/favorecido. Nada além
-- disso: não vê outros usuários do portal, nem do próprio cliente.
create policy portal_self_select_usuarios_portal on usuarios_portal
  for select
  using (id = auth.uid());

-- ----------------------------------------------------------------------------
-- 2. Função espelhando auth_tenant_id(), mas pro espaço de identidade do
--    portal — nunca cruza com `usuarios`.
-- ----------------------------------------------------------------------------
create or replace function auth_portal_favorecido_id()
returns uuid
language sql
stable
security definer
as $$
  select favorecido_id from usuarios_portal where id = auth.uid() and ativo = true
$$;

-- ----------------------------------------------------------------------------
-- 3. Políticas ADITIVAS de leitura — só o que "Meus Pedidos" precisa.
--    Cada uma soma à política interna existente (Postgres faz OR entre
--    políticas permissivas do mesmo comando) — nunca substitui, nunca
--    amplia acesso de colaborador interno.
-- ----------------------------------------------------------------------------
create policy portal_select_pedidos_venda on pedidos_venda
  for select
  using (cliente_id = auth_portal_favorecido_id());

create policy portal_select_pedido_venda_itens on pedido_venda_itens
  for select
  using (exists (
    select 1 from pedidos_venda pv
    where pv.id = pedido_venda_itens.pedido_venda_id
      and pv.cliente_id = auth_portal_favorecido_id()
  ));

create policy portal_select_ordens_producao on ordens_producao
  for select
  using (exists (
    select 1 from pedidos_venda pv
    where pv.id = ordens_producao.pedido_venda_id
      and pv.cliente_id = auth_portal_favorecido_id()
  ));

create policy portal_select_expedicoes on expedicoes
  for select
  using (exists (
    select 1 from pedidos_venda pv
    where pv.id = expedicoes.pedido_venda_id
      and pv.cliente_id = auth_portal_favorecido_id()
  ));

-- ----------------------------------------------------------------------------
-- 4. `produtos` tem custo_medio, preco_reposicao etc — dado interno de
--    custo, nunca pode ficar acessível ao portal. RLS é por LINHA, não por
--    coluna: uma política aditiva ali deixaria esses campos tecnicamente
--    acessíveis via API direta (fora da UI), mesmo escopada por linha.
--    Em vez de política em `produtos`, uma função SECURITY DEFINER que só
--    devolve as 3 colunas seguras — a tabela em si continua sem nenhuma
--    política pro portal.
-- ----------------------------------------------------------------------------
create or replace function portal_meus_produtos()
returns table(produto_id uuid, codigo text, nome text)
language sql
stable
security definer
as $$
  select distinct p.id, p.codigo, p.nome
  from produtos p
  join pedido_venda_itens pvi on pvi.produto_id = p.id
  join pedidos_venda pv on pv.id = pvi.pedido_venda_id
  where pv.cliente_id = auth_portal_favorecido_id()
$$;
