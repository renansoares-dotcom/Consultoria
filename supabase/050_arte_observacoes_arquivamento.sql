-- ============================================================================
-- Migration: 050_arte_observacoes_arquivamento
-- Data: 27/07/2026
--
-- 3 pedidos do Renan sobre Pré-impressão/Aprovação de Arte:
-- 1. Campo de observação em cada modificação (cada versão enviada).
-- 2. Relatório em PDF (não precisa de banco — é geração no navegador com os
--    dados já existentes, mas a coluna de observações abaixo alimenta ele).
-- 3. Exclusão do PROJETO INTEIRO, só pelo sistema principal — decisão do
--    Renan: exclusão SUAVE (some da tela normal, mas fica no histórico de
--    auditoria pra sempre). Mantém a promessa de "histórico completo,
--    imutável" que já está na própria tela.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Observação por versão — a coluna JÁ EXISTE desde a migration 032
--    (arte_versoes.observacoes), só nunca foi usada em nenhuma tela. Esta
--    migration não recria a coluna, só conecta o resto (front-end).
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- 2. Exclusão suave do projeto — nunca DELETE de verdade.
-- ----------------------------------------------------------------------------
alter table projetos_arte add column arquivado_em timestamptz;
alter table projetos_arte add column arquivado_por uuid references usuarios(id);
alter table projetos_arte add column motivo_arquivamento text;

create index idx_projetos_arte_arquivado_em on projetos_arte(arquivado_em);

-- Log de auditoria — registra CADA arquivamento/restauração, não só o
-- estado atual. Populado por INSERT explícito do app (mesmo padrão já
-- usado em arte_aprovacoes/solicitacoes_prorrogacao), não por trigger de
-- diff — mais simples de raciocinar e consistente com o resto do sistema.
create table projetos_arte_arquivamento_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  projeto_id uuid not null references projetos_arte(id) on delete cascade,
  acao text not null check (acao in ('arquivado', 'restaurado')),
  motivo text,
  realizado_por uuid references usuarios(id),
  realizado_em timestamptz not null default now()
);

create index idx_projetos_arte_arquivamento_log_tenant on projetos_arte_arquivamento_log(tenant_id);
create index idx_projetos_arte_arquivamento_log_projeto on projetos_arte_arquivamento_log(projeto_id);

alter table projetos_arte_arquivamento_log enable row level security;

-- Só colaborador interno — é auditoria de uma ação que só o sistema
-- principal pode fazer. Portal nunca precisa ler isto.
create policy tenant_isolation_projetos_arte_arquivamento_log on projetos_arte_arquivamento_log
  for all
  using (tenant_id = auth_tenant_id())
  with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- 3. Projeto arquivado fica congelado — nem staff nem cliente conseguem
--    mandar arquivo ou decidir nele enquanto estiver arquivado (precisa
--    restaurar primeiro). Vale pros dois lados, não só pro portal.
-- ----------------------------------------------------------------------------
create or replace function fn_bloquear_versao_projeto_arquivado()
returns trigger as $$
begin
  if exists (select 1 from projetos_arte where id = new.projeto_id and arquivado_em is not null) then
    raise exception 'Este projeto foi excluído — não é possível enviar novos arquivos. Restaure o projeto primeiro.';
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_bloquear_versao_projeto_arquivado
  before insert on arte_versoes
  for each row execute function fn_bloquear_versao_projeto_arquivado();

create or replace function fn_bloquear_aprovacao_projeto_arquivado()
returns trigger as $$
declare
  v_projeto_id uuid;
begin
  select projeto_id into v_projeto_id from arte_versoes where id = new.versao_id;
  if exists (select 1 from projetos_arte where id = v_projeto_id and arquivado_em is not null) then
    raise exception 'Este projeto foi excluído — não é possível registrar decisões. Restaure o projeto primeiro.';
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_bloquear_aprovacao_projeto_arquivado
  before insert on arte_aprovacoes
  for each row execute function fn_bloquear_aprovacao_projeto_arquivado();

-- ----------------------------------------------------------------------------
-- 4. Portal nunca enxerga projeto arquivado — nem por leitura direta, nem
--    através dos EXISTS de arte_versoes/arte_aprovacoes. Reescreve as
--    políticas do portal pra incluir essa condição.
-- ----------------------------------------------------------------------------
drop policy if exists portal_select_projetos_arte on projetos_arte;
create policy portal_select_projetos_arte on projetos_arte
  for select
  using (cliente_id = auth_portal_favorecido_id() and arquivado_em is null);

drop policy if exists portal_select_arte_versoes on arte_versoes;
create policy portal_select_arte_versoes on arte_versoes
  for select
  using (exists (
    select 1 from projetos_arte pa
    where pa.id = arte_versoes.projeto_id
      and pa.cliente_id = auth_portal_favorecido_id()
      and pa.arquivado_em is null
  ));

drop policy if exists portal_select_arte_aprovacoes on arte_aprovacoes;
create policy portal_select_arte_aprovacoes on arte_aprovacoes
  for select
  using (exists (
    select 1 from arte_versoes av join projetos_arte pa on pa.id = av.projeto_id
    where av.id = arte_aprovacoes.versao_id
      and pa.cliente_id = auth_portal_favorecido_id()
      and pa.arquivado_em is null
  ));

drop policy if exists portal_insert_arte_versoes on arte_versoes;
create policy portal_insert_arte_versoes on arte_versoes
  for insert
  with check (exists (
    select 1 from projetos_arte pa
    where pa.id = arte_versoes.projeto_id
      and pa.cliente_id = auth_portal_favorecido_id()
      and pa.arquivado_em is null
  ));

drop policy if exists portal_insert_arte_aprovacoes on arte_aprovacoes;
create policy portal_insert_arte_aprovacoes on arte_aprovacoes
  for insert
  with check (exists (
    select 1 from arte_versoes av join projetos_arte pa on pa.id = av.projeto_id
    where av.id = arte_aprovacoes.versao_id
      and pa.cliente_id = auth_portal_favorecido_id()
      and pa.arquivado_em is null
  ));
