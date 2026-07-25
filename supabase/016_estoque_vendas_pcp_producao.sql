-- ============================================================================
-- MIGRAÇÃO 016 — Primeira fatia real do ERP: Estoque, Vendas, PCP e Produção
--
-- Constrói o fluxo completo: Pedido de Venda → PCP decide → Ordem de Produção
-- (núcleo) → camada de segmento (Plásticos: molde/cor/regrind) → Apontamento
-- → Estoque. Tudo dentro do mesmo tenant/RLS já existente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Segmento da indústria (decide quais camadas de Produção aparecem)
-- ----------------------------------------------------------------------------
alter table configuracoes
  add column if not exists segmento_industria text default 'generico';
  -- valores esperados: 'generico' | 'plasticos' (mais segmentos entram depois)

-- ----------------------------------------------------------------------------
-- 1. ESTOQUE — Produtos (matéria-prima, produto acabado, insumo)
-- ----------------------------------------------------------------------------
create type tipo_produto as enum ('materia_prima', 'produto_acabado', 'insumo');

create table produtos (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  codigo            text not null,
  nome              text not null,
  tipo              tipo_produto not null,
  unidade_medida    text not null default 'UN', -- UN, KG, M, L...
  saldo_atual       numeric(16,3) not null default 0,
  saldo_minimo      numeric(16,3),
  custo_medio       numeric(16,4),
  ativo             boolean not null default true,
  criado_em         timestamptz not null default now()
);
create unique index idx_produtos_codigo on produtos(tenant_id, codigo);

create table estoque_movimentacoes (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  produto_id        uuid not null references produtos(id) on delete cascade,
  tipo              text not null check (tipo in ('entrada','saida')),
  quantidade        numeric(16,3) not null,
  origem            text, -- 'apontamento_producao' | 'compra' | 'ajuste_manual' | 'venda'
  origem_id         uuid, -- id do registro de origem (ordem de produção, pedido, etc.)
  observacoes       text,
  data              date not null default current_date,
  criado_por        uuid references usuarios(id),
  criado_em         timestamptz not null default now()
);

alter table produtos enable row level security;
create policy tenant_isolation_produtos on produtos for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table estoque_movimentacoes enable row level security;
create policy tenant_isolation_estoque_mov on estoque_movimentacoes for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- Toda movimentação de estoque atualiza o saldo do produto automaticamente
create or replace function fn_atualizar_saldo_produto()
returns trigger as $$
begin
  update produtos
  set saldo_atual = saldo_atual + case when new.tipo = 'entrada' then new.quantidade else -new.quantidade end
  where id = new.produto_id;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_atualizar_saldo_produto
  after insert on estoque_movimentacoes
  for each row execute function fn_atualizar_saldo_produto();

-- ----------------------------------------------------------------------------
-- 2. VENDAS — Pedido de Venda
-- ----------------------------------------------------------------------------
create type status_pedido_venda as enum ('aberto','em_producao','faturado','cancelado');

create table pedidos_venda (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id  uuid references grupos_empresariais(id),
  numero_pedido         text,
  cliente_id            uuid not null references favorecidos(id),
  data_pedido           date not null default current_date,
  data_entrega_prevista date,
  status                status_pedido_venda not null default 'aberto',
  observacoes           text,
  criado_por            uuid references usuarios(id),
  criado_em             timestamptz not null default now()
);

create table pedido_venda_itens (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants(id) on delete cascade,
  pedido_venda_id uuid not null references pedidos_venda(id) on delete cascade,
  produto_id      uuid not null references produtos(id),
  quantidade      numeric(16,3) not null,
  valor_unitario  numeric(16,4) not null default 0,
  quantidade_atendida numeric(16,3) not null default 0 -- vai subindo conforme apontamentos entregam
);

alter table pedidos_venda enable row level security;
create policy tenant_isolation_pedidos_venda on pedidos_venda for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table pedido_venda_itens enable row level security;
create policy tenant_isolation_pedido_venda_itens on pedido_venda_itens for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

create trigger trg_auditoria_pedidos_venda after insert or update or delete on pedidos_venda for each row execute function fn_auditoria();

-- ----------------------------------------------------------------------------
-- 3. PRODUÇÃO — núcleo (Ordem de Produção, Apontamento)
-- ----------------------------------------------------------------------------
create type status_ordem_producao as enum ('planejada','em_andamento','concluida','cancelada');

create table ordens_producao (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id  uuid references grupos_empresariais(id),
  numero_op             text,
  produto_id            uuid not null references produtos(id),
  quantidade_planejada  numeric(16,3) not null,
  quantidade_produzida  numeric(16,3) not null default 0,
  pedido_venda_id       uuid references pedidos_venda(id), -- opcional: sob encomenda x estoque
  status                status_ordem_producao not null default 'planejada',
  data_abertura         date not null default current_date,
  data_prevista         date,
  data_conclusao        date,
  observacoes           text,

  -- Camada de segmento: Plásticos (colunas ficam nulas se o segmento não for plásticos)
  molde_id              uuid,
  cor_masterbatch       text,
  percentual_regrind    numeric(5,2),

  criado_por            uuid references usuarios(id),
  criado_em             timestamptz not null default now()
);

create table apontamentos_producao (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  ordem_producao_id uuid not null references ordens_producao(id) on delete cascade,
  quantidade        numeric(16,3) not null,
  quantidade_refugo numeric(16,3) not null default 0,
  data              date not null default current_date,
  turno             text,
  observacoes       text,
  criado_por        uuid references usuarios(id),
  criado_em         timestamptz not null default now()
);

alter table ordens_producao enable row level security;
create policy tenant_isolation_ordens_producao on ordens_producao for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table apontamentos_producao enable row level security;
create policy tenant_isolation_apontamentos on apontamentos_producao for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

create trigger trg_auditoria_ordens_producao after insert or update or delete on ordens_producao for each row execute function fn_auditoria();

-- Todo apontamento: soma na OP, gera entrada de estoque do produto acabado,
-- e (se a OP estiver vinculada a um pedido de venda) atualiza o item atendido.
create or replace function fn_processar_apontamento()
returns trigger as $$
declare
  v_op ordens_producao%rowtype;
begin
  select * into v_op from ordens_producao where id = new.ordem_producao_id;

  update ordens_producao
  set quantidade_produzida = quantidade_produzida + new.quantidade,
      status = (case when quantidade_produzida + new.quantidade >= quantidade_planejada then 'concluida' else 'em_andamento' end)::status_ordem_producao,
      data_conclusao = case when quantidade_produzida + new.quantidade >= quantidade_planejada then new.data else data_conclusao end
  where id = new.ordem_producao_id;

  insert into estoque_movimentacoes (tenant_id, produto_id, tipo, quantidade, origem, origem_id, data, criado_por)
  values (new.tenant_id, v_op.produto_id, 'entrada', new.quantidade, 'apontamento_producao', new.ordem_producao_id, new.data, new.criado_por);

  if v_op.pedido_venda_id is not null then
    update pedido_venda_itens
    set quantidade_atendida = quantidade_atendida + new.quantidade
    where pedido_venda_id = v_op.pedido_venda_id and produto_id = v_op.produto_id;
  end if;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_processar_apontamento
  after insert on apontamentos_producao
  for each row execute function fn_processar_apontamento();

-- ----------------------------------------------------------------------------
-- 4. Camada Plásticos — Moldes
-- ----------------------------------------------------------------------------
create table moldes (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  codigo            text not null,
  nome              text not null,
  numero_cavidades  integer not null default 1,
  maquina_compativel text,
  produto_id        uuid references produtos(id), -- produto que este molde produz
  ativo             boolean not null default true,
  observacoes       text
);
create unique index idx_moldes_codigo on moldes(tenant_id, codigo);

alter table moldes enable row level security;
create policy tenant_isolation_moldes on moldes for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

alter table ordens_producao add constraint fk_ordens_producao_molde foreign key (molde_id) references moldes(id);
