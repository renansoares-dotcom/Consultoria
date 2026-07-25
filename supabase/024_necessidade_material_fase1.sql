-- ============================================================================
-- MIGRAÇÃO 024 — Elo Produção↔Compras, Fase 1 (necessidade + requisição)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: Fase 1 calcula
-- necessidade real (BOM × OPs abertas, descontando estoque e considerando
-- mínimo) e gera Requisição de Compra com aprovação humana — nunca cria
-- pedido de compra sozinho. Fase 2 (bloqueio Qualidade, lote/fornecedor,
-- trilha até recebimento) fica para quando os módulos Compras/Qualidade
-- existirem.
-- ============================================================================

create type status_requisicao_compra as enum ('pendente', 'aprovada', 'rejeitada', 'cancelada');

create table requisicoes_compra (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id uuid references grupos_empresariais(id),
  produto_id          uuid not null references produtos(id),   -- o componente (matéria-prima/insumo) a comprar
  quantidade_solicitada numeric(16,4) not null check (quantidade_solicitada > 0),
  status              status_requisicao_compra not null default 'pendente',
  observacoes         text,
  criado_por          uuid references usuarios(id),
  criado_em           timestamptz not null default now(),
  decidido_por        uuid references usuarios(id),
  decidido_em         timestamptz,
  motivo_decisao      text
);

create index idx_requisicoes_compra_status on requisicoes_compra(tenant_id, status);
create index idx_requisicoes_compra_produto on requisicoes_compra(produto_id);

alter table requisicoes_compra enable row level security;
create policy tenant_isolation_requisicoes_compra on requisicoes_compra
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- Rastreabilidade: uma requisição consolidada pode cobrir várias Ordens de
-- Produção que precisam do mesmo material (pedido do ChatGPT: consolidar por
-- material). Traço a origem OP → requisição aqui.
create table requisicao_compra_origem (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  requisicao_id     uuid not null references requisicoes_compra(id) on delete cascade,
  ordem_producao_id uuid not null references ordens_producao(id),
  quantidade        numeric(16,4) not null check (quantidade > 0),
  unique (requisicao_id, ordem_producao_id)
);

alter table requisicao_compra_origem enable row level security;
create policy tenant_isolation_requisicao_compra_origem on requisicao_compra_origem
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- Necessidade por OP × componente: para cada Ordem de Produção aberta
-- (planejada ou em_andamento), o que falta produzir × a BOM do produto.
-- ----------------------------------------------------------------------------
create or replace view vw_necessidade_op_material as
select
  op.id as ordem_producao_id,
  op.tenant_id,
  op.grupo_empresarial_id,
  op.numero_op,
  op.produto_id as produto_acabado_id,
  epi.componente_id,
  (op.quantidade_planejada - op.quantidade_produzida) as quantidade_pendente_produzir,
  epi.quantidade_por_unidade,
  (op.quantidade_planejada - op.quantidade_produzida) * epi.quantidade_por_unidade as necessidade_bruta
from ordens_producao op
join estrutura_produto_itens epi on epi.produto_id = op.produto_id
where op.status in ('planejada', 'em_andamento')
  and (op.quantidade_planejada - op.quantidade_produzida) > 0;

alter view vw_necessidade_op_material set (security_invoker = on);

-- ----------------------------------------------------------------------------
-- Necessidade consolidada por material: soma de todas as OPs abertas, menos
-- o que já está saldo em estoque (respeitando o mínimo), menos o que já foi
-- requisitado e ainda está pendente/aprovado (pra não sugerir de novo).
-- necessidade_liquida > 0 é o gatilho visual pra sugerir requisição.
-- ----------------------------------------------------------------------------
create or replace view vw_necessidade_consolidada as
select
  p.id as produto_id,
  p.tenant_id,
  p.codigo,
  p.nome,
  p.unidade_medida,
  p.saldo_atual,
  coalesce(p.saldo_minimo, 0) as saldo_minimo,
  coalesce(nm.necessidade_total, 0) as necessidade_producao,
  coalesce(rc.ja_requisitado, 0) as ja_requisitado_em_aberto,
  greatest(0,
    coalesce(nm.necessidade_total, 0) + coalesce(p.saldo_minimo, 0) - p.saldo_atual - coalesce(rc.ja_requisitado, 0)
  ) as necessidade_liquida
from produtos p
left join (
  select componente_id, tenant_id, sum(necessidade_bruta) as necessidade_total
  from vw_necessidade_op_material
  group by componente_id, tenant_id
) nm on nm.componente_id = p.id and nm.tenant_id = p.tenant_id
left join (
  select produto_id, tenant_id, sum(quantidade_solicitada) as ja_requisitado
  from requisicoes_compra
  where status in ('pendente', 'aprovada')
  group by produto_id, tenant_id
) rc on rc.produto_id = p.id and rc.tenant_id = p.tenant_id
where p.tipo in ('materia_prima', 'insumo') and p.ativo = true;

alter view vw_necessidade_consolidada set (security_invoker = on);
