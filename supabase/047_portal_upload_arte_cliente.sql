-- ============================================================================
-- Migration: 047_portal_upload_arte_cliente
-- Portal do Cliente — Slice 5 (cliente sobe arquivo de arte)
-- Data: 2026-07-27
--
-- Decisão do Renan: quando o cliente sobe um arquivo, o projeto sempre volta
-- pra 'em_andamento' (equipe interna precisa revisar antes de seguir) — o
-- cliente pode subir a qualquer momento, em qualquer status do projeto.
--
-- Mesmo padrão de autoria dupla já usado em arte_aprovacoes (migration 046):
-- enviado_por (staff) vs enviado_por_portal (cliente), CHECK de
-- exclusividade, trigger que nunca confia no payload.
-- ============================================================================

alter table arte_versoes add column enviado_por_portal uuid references usuarios_portal(id);

alter table arte_versoes add constraint chk_arte_versoes_autoria_exclusiva check (
  (enviado_por is not null and enviado_por_portal is null)
  or
  (enviado_por is null and enviado_por_portal is not null)
);

-- ----------------------------------------------------------------------------
-- Política aditiva: cliente só insere versão pra projeto que é dele.
-- ----------------------------------------------------------------------------
create policy portal_insert_arte_versoes on arte_versoes
  for insert
  with check (exists (
    select 1 from projetos_arte pa
    where pa.id = arte_versoes.projeto_id
      and pa.cliente_id = auth_portal_favorecido_id()
  ));

-- ----------------------------------------------------------------------------
-- BEFORE INSERT: nunca confia no que o cliente manda — autoria, número da
-- versão (evita corrida/duplicidade calculando no banco, não no navegador)
-- e posse do projeto são sempre recalculados/validados aqui.
-- ----------------------------------------------------------------------------
create or replace function fn_preparar_versao_arte_portal()
returns trigger as $$
declare
  v_favorecido_portal uuid;
  v_projeto_cliente_id uuid;
begin
  v_favorecido_portal := auth_portal_favorecido_id();

  if v_favorecido_portal is null then
    return new; -- inserção pelo staff, segue como já era
  end if;

  select cliente_id into v_projeto_cliente_id from projetos_arte where id = new.projeto_id;

  if v_projeto_cliente_id is distinct from v_favorecido_portal then
    raise exception 'Este projeto de arte não pertence ao cliente autenticado.';
  end if;

  new.enviado_por_portal := (select auth.uid());
  new.enviado_por := null;
  new.numero_versao := coalesce((select max(numero_versao) from arte_versoes where projeto_id = new.projeto_id), 0) + 1;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_preparar_versao_arte_portal
  before insert on arte_versoes
  for each row execute function fn_preparar_versao_arte_portal();

-- ----------------------------------------------------------------------------
-- AFTER INSERT: só reage a upload feito pelo cliente (enviado_por_portal
-- setado) — não muda em nada o comportamento do upload pelo staff, que
-- continua definindo o status manualmente na tela interna, como já era.
-- ----------------------------------------------------------------------------
create or replace function fn_atualizar_status_projeto_arte_por_upload_portal()
returns trigger as $$
begin
  if new.enviado_por_portal is not null then
    update projetos_arte set status = 'em_andamento' where id = new.projeto_id;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_atualizar_status_projeto_arte_upload_portal
  after insert on arte_versoes
  for each row execute function fn_atualizar_status_projeto_arte_por_upload_portal();
