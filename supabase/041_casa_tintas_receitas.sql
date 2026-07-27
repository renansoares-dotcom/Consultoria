-- ============================================================================
-- Migration: 041_casa_tintas_receitas
-- Módulo: Qualidade > Casa de Tintas (Slice 3 — Receitas versionadas)
-- Data: 2026-07-26
--
-- Regra central do documento estratégico: "Receita aprovada é imutável.
-- Toda alteração deve gerar nova versão." Isso é garantido no BANCO via
-- trigger (não só escondido na UI) — mesmo princípio já usado no Borderô
-- pra imutabilidade de título.
--
-- Estrutura: receitas_tinta (identidade da cor/fórmula) 1:N
-- receitas_tinta_versoes (cada versão tem seu próprio status e parâmetros)
-- 1:N receitas_tinta_itens (composição, pertence à versão, não à receita).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Enum isolado
-- ----------------------------------------------------------------------------
create type status_receita_tinta as enum (
  'rascunho',
  'em_teste',
  'aprovada',
  'bloqueada',
  'obsoleta'
);

-- ----------------------------------------------------------------------------
-- 2. receitas_tinta (identidade — código, cor, aplicação)
-- ----------------------------------------------------------------------------
create table receitas_tinta (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  cor_tinta_id uuid not null references cores_tinta(id),
  codigo text not null,
  nome text not null,
  aplicacao text,                       -- ex: superfície, laminação, interno/externo
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id),
  unique (tenant_id, codigo)
);

create index idx_receitas_tinta_tenant on receitas_tinta(tenant_id);
create index idx_receitas_tinta_cor on receitas_tinta(cor_tinta_id);

alter table receitas_tinta enable row level security;

create policy tenant_isolation_receitas_tinta on receitas_tinta
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- 3. receitas_tinta_versoes
-- ----------------------------------------------------------------------------
create table receitas_tinta_versoes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  receita_id uuid not null references receitas_tinta(id) on delete cascade,
  numero_versao int not null,
  status status_receita_tinta not null default 'rascunho',
  quantidade_minima_lote numeric,
  quantidade_maxima_lote numeric,
  viscosidade_alvo numeric,
  viscosidade_tolerancia numeric,
  viscosidade_metodo text,
  densidade_alvo numeric,
  densidade_tolerancia numeric,
  delta_e_tolerancia numeric,
  custo_teorico numeric not null default 0,   -- mantido só pelo trigger de recálculo (soma dos itens)
  revisor_id uuid references usuarios(id),
  aprovador_id uuid references usuarios(id),
  aprovado_em timestamptz,
  observacoes text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id),
  unique (receita_id, numero_versao)
);

create index idx_receitas_tinta_versoes_tenant on receitas_tinta_versoes(tenant_id);
create index idx_receitas_tinta_versoes_receita on receitas_tinta_versoes(receita_id);

alter table receitas_tinta_versoes enable row level security;

create policy tenant_isolation_receitas_tinta_versoes on receitas_tinta_versoes
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- 4. receitas_tinta_itens (composição — pertence à versão)
-- ----------------------------------------------------------------------------
create table receitas_tinta_itens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  versao_id uuid not null references receitas_tinta_versoes(id) on delete cascade,
  insumo_id uuid not null references insumos_tinta(id),
  quantidade numeric not null check (quantidade > 0),
  funcao text,                          -- ex: base, pigmento, secante, diluente
  tolerancia_pesagem_percentual numeric,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id)
);

create index idx_receitas_tinta_itens_tenant on receitas_tinta_itens(tenant_id);
create index idx_receitas_tinta_itens_versao on receitas_tinta_itens(versao_id);
create index idx_receitas_tinta_itens_insumo on receitas_tinta_itens(insumo_id);

alter table receitas_tinta_itens enable row level security;

create policy tenant_isolation_receitas_tinta_itens on receitas_tinta_itens
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- 5. Imutabilidade: uma vez que a versão saiu de rascunho/em_teste para
--    aprovada (ou além), ela é congelada. Única mudança permitida depois
--    disso é a transição de status aprovada -> bloqueada / obsoleta, ou
--    bloqueada -> obsoleta — nunca os parâmetros técnicos ou aprovador.
-- ----------------------------------------------------------------------------
create or replace function fn_bloquear_alteracao_receita_aprovada()
returns trigger as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'rascunho' then
      raise exception 'Versão % já não está em rascunho (status: %) — não pode ser excluída.', old.numero_versao, old.status;
    end if;
    return old;
  end if;

  -- UPDATE
  if old.status in ('aprovada', 'bloqueada', 'obsoleta') then
    if not (
      old.status = 'aprovada' and new.status in ('bloqueada', 'obsoleta')
      or old.status = 'bloqueada' and new.status = 'obsoleta'
    ) then
      raise exception 'Versão % está com status % — imutável. Crie uma nova versão para alterar a fórmula.', old.numero_versao, old.status;
    end if;
    -- mesmo numa transição de status permitida, nenhum outro campo pode mudar
    if new.quantidade_minima_lote is distinct from old.quantidade_minima_lote
       or new.quantidade_maxima_lote is distinct from old.quantidade_maxima_lote
       or new.viscosidade_alvo is distinct from old.viscosidade_alvo
       or new.viscosidade_tolerancia is distinct from old.viscosidade_tolerancia
       or new.densidade_alvo is distinct from old.densidade_alvo
       or new.densidade_tolerancia is distinct from old.densidade_tolerancia
       or new.delta_e_tolerancia is distinct from old.delta_e_tolerancia
       or new.custo_teorico is distinct from old.custo_teorico
       or new.aprovador_id is distinct from old.aprovador_id
       or new.aprovado_em is distinct from old.aprovado_em
    then
      raise exception 'Versão % está com status % — só a transição de status é permitida, nenhum outro campo pode mudar.', old.numero_versao, old.status;
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_bloquear_alteracao_receita_aprovada
  before update or delete on receitas_tinta_versoes
  for each row execute function fn_bloquear_alteracao_receita_aprovada();

-- ----------------------------------------------------------------------------
-- 6. Itens ficam congelados junto com a versão (inclusive contra INSERT de
--    novo item numa versão já aprovada).
-- ----------------------------------------------------------------------------
create or replace function fn_bloquear_alteracao_itens_receita()
returns trigger as $$
declare
  v_status status_receita_tinta;
  v_numero int;
  v_versao_id uuid;
begin
  v_versao_id := coalesce(new.versao_id, old.versao_id);
  select status, numero_versao into v_status, v_numero from receitas_tinta_versoes where id = v_versao_id;

  if v_status in ('aprovada', 'bloqueada', 'obsoleta') then
    raise exception 'Versão % está com status % — itens congelados. Crie uma nova versão para alterar a composição.', v_numero, v_status;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_bloquear_alteracao_itens_receita
  before insert or update or delete on receitas_tinta_itens
  for each row execute function fn_bloquear_alteracao_itens_receita();

-- ----------------------------------------------------------------------------
-- 7. Custo teórico da versão = soma automática dos itens (mesmo princípio
--    já usado no custo consolidado de MRO/Manutenção Fase 3 — "soma
--    sozinho", nunca calculado manualmente na tela).
-- ----------------------------------------------------------------------------
create or replace function fn_recalcular_custo_teorico_receita()
returns trigger as $$
declare
  v_versao_id uuid;
begin
  v_versao_id := coalesce(new.versao_id, old.versao_id);

  update receitas_tinta_versoes
  set custo_teorico = coalesce((
    select sum(ri.quantidade * coalesce(i.custo_referencia, 0))
    from receitas_tinta_itens ri
    join insumos_tinta i on i.id = ri.insumo_id
    where ri.versao_id = v_versao_id
  ), 0)
  where id = v_versao_id;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_recalcular_custo_teorico_receita
  after insert or update or delete on receitas_tinta_itens
  for each row execute function fn_recalcular_custo_teorico_receita();
