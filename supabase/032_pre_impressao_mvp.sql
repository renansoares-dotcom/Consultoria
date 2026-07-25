-- ============================================================================
-- MIGRAÇÃO 032 — Pré-impressão e Aprovação de Artes (MVP)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: projeto de arte
-- ligado a cliente/produto/pedido, versões imutáveis (arquivo no bucket
-- 'anexos' já existente), aprovação com prova auditável, regra de liberação
-- como aviso na UI (não trigger rígido — sem dados de uso reais ainda).
-- ============================================================================

create type status_projeto_arte as enum ('em_andamento', 'aguardando_aprovacao', 'aprovado', 'reprovado', 'cancelado');
create type decisao_arte as enum ('aprovado', 'reprovado', 'solicitar_alteracao');

create table projetos_arte (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id  uuid references grupos_empresariais(id),
  nome                  text not null,
  cliente_id            uuid references favorecidos(id),
  produto_id            uuid references produtos(id),
  pedido_venda_id        uuid references pedidos_venda(id),
  status                status_projeto_arte not null default 'em_andamento',
  observacoes           text,
  criado_por            uuid references usuarios(id),
  criado_em             timestamptz not null default now()
);

create index idx_projetos_arte_cliente on projetos_arte(cliente_id);
create index idx_projetos_arte_pedido on projetos_arte(pedido_venda_id);
create index idx_projetos_arte_status on projetos_arte(tenant_id, status);

-- Versões são imutáveis por natureza: só cria, nunca edita/deleta.
create table arte_versoes (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  projeto_id        uuid not null references projetos_arte(id) on delete cascade,
  numero_versao     integer not null,
  arquivo_path      text not null,     -- caminho no bucket 'anexos': {tenant_id}/artes/{projeto_id}/v{n}_{nome}
  arquivo_nome      text not null,
  arquivo_tipo      text,
  hash_arquivo      text,              -- SHA-256 do conteúdo, calculado no navegador — prova auditável
  tamanho_bytes     bigint,
  observacoes       text,
  enviado_por       uuid references usuarios(id),
  criado_em         timestamptz not null default now(),
  unique (tenant_id, projeto_id, numero_versao)
);

create table arte_aprovacoes (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references tenants(id) on delete cascade,
  versao_id     uuid not null references arte_versoes(id) on delete cascade,
  decisao       decisao_arte not null,
  comentario    text,
  decidido_por  uuid references usuarios(id),
  criado_em     timestamptz not null default now()
);

alter table projetos_arte enable row level security;
create policy tenant_isolation_projetos_arte on projetos_arte
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table arte_versoes enable row level security;
create policy tenant_isolation_arte_versoes on arte_versoes
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table arte_aprovacoes enable row level security;
create policy tenant_isolation_arte_aprovacoes on arte_aprovacoes
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- Regra de liberação para produção: vínculo opcional + exceção formal quando
-- precisar liberar sem arte aprovada (verificado na UI, não bloqueado aqui).
alter table ordens_producao add column projeto_arte_id uuid references projetos_arte(id);
alter table ordens_producao add column excecao_arte_motivo text;
alter table ordens_producao add column excecao_arte_autorizado_por uuid references usuarios(id);

-- Ao registrar uma decisão de aprovação, atualiza o status do projeto.
create or replace function fn_atualizar_status_projeto_arte()
returns trigger as $$
declare
  v_projeto_id uuid;
begin
  select projeto_id into v_projeto_id from arte_versoes where id = new.versao_id;

  update projetos_arte
  set status = (case new.decisao
    when 'aprovado' then 'aprovado'
    when 'reprovado' then 'reprovado'
    when 'solicitar_alteracao' then 'em_andamento'
  end)::status_projeto_arte
  where id = v_projeto_id;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_atualizar_status_projeto_arte
  after insert on arte_aprovacoes
  for each row execute function fn_atualizar_status_projeto_arte();
