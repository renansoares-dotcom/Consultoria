-- ============================================================================
-- Migration: 046_portal_pre_impressao
-- Portal do Cliente — Slice 4 (Pré-impressão / Aprovação de Arte)
-- Data: 2026-07-27
--
-- Estende o MVP de Pré-impressão (migration 032: projetos_arte, arte_versoes,
-- arte_aprovacoes) pra permitir que o PRÓPRIO CLIENTE aprove/reprove/peça
-- alteração — hoje isso só existia pelo lado interno (pages/vendas/
-- pre-impressao.html), com decidido_por apontando sempre pra `usuarios`.
--
-- Diferente dos slices 1-3 (que usam RPC pra tabelas com coluna sensível),
-- projetos_arte/arte_versoes/arte_aprovacoes não têm nenhum dado interno
-- (custo, aprovação financeira, FIDC) — então política de RLS direta é
-- segura aqui, sem precisar de função intermediária.
--
-- A tela interna (pre-impressao.html) NUNCA lê o nome de quem decidiu, só
-- decisao/comentario/criado_em — confirmado antes de mexer, então a coluna
-- nova não quebra nada existente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. arte_aprovacoes ganha uma segunda "autoria" possível: o cliente do
--    portal. Exatamente um dos dois (staff OU portal) tem que estar
--    preenchido — nunca os dois, nunca nenhum. Isso é o mesmo princípio de
--    autoria dupla que já vale pro sistema todo (criado_por vs
--    criado_por_portal em solicitacoes_prorrogacao).
-- ----------------------------------------------------------------------------
alter table arte_aprovacoes add column decidido_por_portal uuid references usuarios_portal(id);

alter table arte_aprovacoes add constraint chk_arte_aprovacoes_autoria_exclusiva check (
  (decidido_por is not null and decidido_por_portal is null)
  or
  (decidido_por is null and decidido_por_portal is not null)
);

-- ----------------------------------------------------------------------------
-- 2. Políticas ADITIVAS de leitura — mesmo padrão dos slices anteriores.
-- ----------------------------------------------------------------------------
create policy portal_select_projetos_arte on projetos_arte
  for select
  using (cliente_id = auth_portal_favorecido_id());

create policy portal_select_arte_versoes on arte_versoes
  for select
  using (exists (
    select 1 from projetos_arte pa
    where pa.id = arte_versoes.projeto_id
      and pa.cliente_id = auth_portal_favorecido_id()
  ));

create policy portal_select_arte_aprovacoes on arte_aprovacoes
  for select
  using (exists (
    select 1 from arte_versoes av join projetos_arte pa on pa.id = av.projeto_id
    where av.id = arte_aprovacoes.versao_id
      and pa.cliente_id = auth_portal_favorecido_id()
  ));

-- ----------------------------------------------------------------------------
-- 3. Política ADITIVA de escrita — primeira vez que o cliente decide algo
--    sobre um documento técnico, não só financeiro. Mesmo espírito de nunca
--    confiar em nada que vem do cliente: o trigger abaixo sobrescreve
--    autor/validações, a policy só garante que ele só insere pra arte que é
--    dele.
-- ----------------------------------------------------------------------------
create policy portal_insert_arte_aprovacoes on arte_aprovacoes
  for insert
  with check (exists (
    select 1 from arte_versoes av join projetos_arte pa on pa.id = av.projeto_id
    where av.id = arte_aprovacoes.versao_id
      and pa.cliente_id = auth_portal_favorecido_id()
  ));

-- ----------------------------------------------------------------------------
-- 4. Validação no banco: só decide quem é dono da arte, só quando o projeto
--    está de fato aguardando aprovação, e só sobre a versão mais recente
--    (nunca aprova/reprova uma versão já superada). Autoria sempre forçada
--    a partir da sessão real, nunca do que o cliente manda no payload.
-- ----------------------------------------------------------------------------
create or replace function fn_validar_aprovacao_arte_portal()
returns trigger as $$
declare
  v_favorecido_portal uuid;
  v_projeto_status status_projeto_arte;
  v_projeto_cliente_id uuid;
  v_ultima_versao int;
  v_versao_numero int;
begin
  v_favorecido_portal := auth_portal_favorecido_id();

  -- só entra nessa validação quando quem está inserindo é sessão de portal;
  -- inserção pelo staff (decidido_por) segue exatamente como já era.
  if v_favorecido_portal is null then
    return new;
  end if;

  new.decidido_por_portal := (select auth.uid());
  new.decidido_por := null;

  select pa.status, pa.cliente_id, av.numero_versao
  into v_projeto_status, v_projeto_cliente_id, v_versao_numero
  from arte_versoes av
  join projetos_arte pa on pa.id = av.projeto_id
  where av.id = new.versao_id;

  if v_projeto_cliente_id is distinct from v_favorecido_portal then
    raise exception 'Esta arte não pertence ao cliente autenticado.';
  end if;

  if v_projeto_status <> 'aguardando_aprovacao' then
    raise exception 'Este projeto não está aguardando aprovação (status atual: %).', v_projeto_status;
  end if;

  select max(numero_versao) into v_ultima_versao
  from arte_versoes av2 join projetos_arte pa2 on pa2.id = av2.projeto_id
  where pa2.id = (select projeto_id from arte_versoes where id = new.versao_id);

  if v_versao_numero <> v_ultima_versao then
    raise exception 'Só é possível decidir sobre a versão mais recente da arte.';
  end if;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_validar_aprovacao_arte_portal
  before insert on arte_aprovacoes
  for each row execute function fn_validar_aprovacao_arte_portal();
