-- ============================================================================
-- Migration: 045_portal_solicitacao_prorrogacao
-- Portal do Cliente — Slice 3 (Solicitação de prorrogação de título)
-- Data: 2026-07-27
--
-- Primeiro fluxo do sistema em que o cliente ESCREVE no banco (Slices 1 e 2
-- eram só leitura). Regra do documento estratégico, não negociável:
-- "nunca alterar vencimento diretamente" — o cliente cria uma SOLICITAÇÃO,
-- nunca o campo data_prorrogacao_vencimento do lançamento em si. Só
-- colaborador interno aprova/recusa, e só a aprovação toca o lançamento de
-- verdade (reaproveitando os mesmos campos data_prorrogacao_vencimento /
-- motivo_prorrogacao que lancamento-novo.html já usa hoje, mas que hoje são
-- editados livremente, sem workflow nenhum — esta migration introduz o
-- primeiro fluxo de aprovação formal em cima deles).
-- ============================================================================

create type status_solicitacao_prorrogacao as enum (
  'solicitada',
  'em_analise',
  'aprovada',
  'recusada',
  'cancelada'
);

create table solicitacoes_prorrogacao (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  lancamento_id uuid not null references lancamentos(id),
  favorecido_id uuid not null references favorecidos(id),
  data_vencimento_atual date not null,       -- travado a partir do lançamento no momento da solicitação, nunca confia no que o cliente manda
  data_vencimento_solicitada date not null,
  motivo text not null,
  status status_solicitacao_prorrogacao not null default 'solicitada',
  resposta_interna text,
  analisado_por uuid references usuarios(id),
  analisado_em timestamptz,
  criado_por_portal uuid references usuarios_portal(id),
  criado_em timestamptz not null default now()
);

create index idx_solicitacoes_prorrogacao_tenant on solicitacoes_prorrogacao(tenant_id);
create index idx_solicitacoes_prorrogacao_lancamento on solicitacoes_prorrogacao(lancamento_id);
create index idx_solicitacoes_prorrogacao_favorecido on solicitacoes_prorrogacao(favorecido_id);
create index idx_solicitacoes_prorrogacao_status on solicitacoes_prorrogacao(status);

alter table solicitacoes_prorrogacao enable row level security;

-- Colaborador interno vê e gerencia tudo do tenant (analisa, aprova, recusa).
create policy tenant_isolation_solicitacoes_prorrogacao on solicitacoes_prorrogacao
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- Cliente do portal só CRIA e LÊ as próprias solicitações — nunca UPDATE,
-- nunca DELETE. Uma vez enviada, só o colaborador interno pode mudar o
-- status (mesmo espírito de "nunca alterar vencimento diretamente": aqui é
-- "nunca alterar a própria solicitação depois de enviada").
create policy portal_insert_solicitacoes_prorrogacao on solicitacoes_prorrogacao
  for insert
  with check (favorecido_id = auth_portal_favorecido_id());

create policy portal_select_solicitacoes_prorrogacao on solicitacoes_prorrogacao
  for select
  using (favorecido_id = auth_portal_favorecido_id());

-- ----------------------------------------------------------------------------
-- Validação no BANCO, não só na UI (mesmo princípio de todas as migrations
-- anteriores): o cliente não decide status, não decide a data atual, e só
-- pode pedir prorrogação de título que é dele e que ainda está em aberto.
-- ----------------------------------------------------------------------------
create or replace function fn_validar_solicitacao_prorrogacao()
returns trigger as $$
declare
  v_lancamento lancamentos%rowtype;
begin
  select * into v_lancamento from lancamentos where id = new.lancamento_id;

  if v_lancamento is null then
    raise exception 'Título não encontrado.';
  end if;

  if v_lancamento.favorecido_id is distinct from new.favorecido_id then
    raise exception 'Este título não pertence ao cliente informado.';
  end if;

  if v_lancamento.status not in ('em_aberto', 'parcial', 'inadimplente') then
    raise exception 'Só é possível solicitar prorrogação de título em aberto (status atual: %).', v_lancamento.status;
  end if;

  if new.data_vencimento_solicitada <= v_lancamento.data_vencimento then
    raise exception 'A nova data precisa ser posterior ao vencimento atual (%).', v_lancamento.data_vencimento;
  end if;

  -- Nunca confia no que veio do cliente pra data atual nem pro status —
  -- deriva sempre do lançamento real, e força o status inicial correto.
  new.data_vencimento_atual := v_lancamento.data_vencimento;
  new.status := 'solicitada';
  new.analisado_por := null;
  new.analisado_em := null;
  new.resposta_interna := null;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_validar_solicitacao_prorrogacao
  before insert on solicitacoes_prorrogacao
  for each row execute function fn_validar_solicitacao_prorrogacao();

-- ----------------------------------------------------------------------------
-- Aprovação: só então o lançamento real é tocado — e só pelo colaborador
-- interno (esta função roda com os privilégios de quem chama; a RLS de
-- `lancamentos` já garante que só colaborador interno consegue de fato
-- fazer o UPDATE por trás dela).
-- ----------------------------------------------------------------------------
create or replace function fn_aprovar_solicitacao_prorrogacao(p_solicitacao_id uuid, p_usuario_id uuid)
returns void as $$
declare
  v_solicitacao solicitacoes_prorrogacao%rowtype;
begin
  select * into v_solicitacao from solicitacoes_prorrogacao where id = p_solicitacao_id;

  if v_solicitacao is null then
    raise exception 'Solicitação não encontrada.';
  end if;
  if v_solicitacao.status not in ('solicitada', 'em_analise') then
    raise exception 'Esta solicitação já foi % — não pode ser aprovada de novo.', v_solicitacao.status;
  end if;

  update lancamentos
  set data_prorrogacao_vencimento = v_solicitacao.data_vencimento_solicitada,
      motivo_prorrogacao = v_solicitacao.motivo
  where id = v_solicitacao.lancamento_id;

  update solicitacoes_prorrogacao
  set status = 'aprovada', analisado_por = p_usuario_id, analisado_em = now()
  where id = p_solicitacao_id;
end;
$$ language plpgsql security invoker;
