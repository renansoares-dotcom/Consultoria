-- ============================================================================
-- MIGRAÇÃO 005 — Lançamento vira "Compromisso" completo
-- Rode em duas etapas separadas (ver aviso abaixo sobre o ALTER TYPE).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ETAPA 1 — rode ISOLADO primeiro (selecione só este bloco e execute):
-- Postgres exige que um novo valor de enum seja "commitado" antes de ser
-- usado em outras instruções na mesma migração.
-- ----------------------------------------------------------------------------
alter type status_lancamento add value if not exists 'parcial';


-- ----------------------------------------------------------------------------
-- ETAPA 2 — depois de rodar a linha acima sozinha, rode o resto abaixo:
-- ----------------------------------------------------------------------------

-- Novos campos no compromisso (antigo "lançamento")
alter table lancamentos
  add column if not exists numero_documento text,
  add column if not exists parcela_numero integer,
  add column if not exists parcela_total integer,
  add column if not exists data_emissao date,
  add column if not exists data_prorrogacao_vencimento date,
  add column if not exists motivo_prorrogacao text,
  add column if not exists forma_pagamento text,
  add column if not exists anexo_url text,
  add column if not exists anexo_nome text,
  add column if not exists aprovado_por uuid references usuarios(id),
  add column if not exists aprovado_em timestamptz;

-- ----------------------------------------------------------------------------
-- BAIXAS — permite quitar um compromisso em mais de uma vez (pagamento
-- parcial). O status do lançamento é recalculado automaticamente (trigger
-- no final deste arquivo) sempre que uma baixa é criada/editada/excluída.
-- ----------------------------------------------------------------------------
create table baixas (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants(id) on delete cascade,
  lancamento_id   uuid not null references lancamentos(id) on delete cascade,
  data            date not null,
  valor_pago      numeric(16,2) not null,
  juros           numeric(16,2) not null default 0,
  multa           numeric(16,2) not null default 0,
  desconto        numeric(16,2) not null default 0,
  forma_pagamento text,
  conta_bancaria_id uuid references contas_bancarias(id),
  observacoes     text,
  criado_por      uuid references usuarios(id),
  criado_em       timestamptz not null default now()
);
create index idx_baixas_lancamento on baixas(lancamento_id);

-- ----------------------------------------------------------------------------
-- DISTRIBUIÇÃO (rateio) — divide o mesmo compromisso entre múltiplas contas
-- do plano de contas e/ou múltiplos centros de custo, cada um com percentual.
-- Os campos lancamentos.plano_conta_id / centro_custo_id continuam existindo
-- e são sincronizados automaticamente com a linha de MAIOR percentual (isso
-- mantém todos os relatórios já existentes funcionando sem alteração).
-- ----------------------------------------------------------------------------
create table lancamento_distribuicao_conta (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  lancamento_id  uuid not null references lancamentos(id) on delete cascade,
  plano_conta_id uuid not null references plano_contas(id),
  percentual     numeric(5,2) not null,
  valor          numeric(16,2) not null,
  criado_em      timestamptz not null default now()
);
create index idx_dist_conta_lancamento on lancamento_distribuicao_conta(lancamento_id);

create table lancamento_distribuicao_cc (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenants(id) on delete cascade,
  lancamento_id   uuid not null references lancamentos(id) on delete cascade,
  centro_custo_id uuid not null references centros_custo(id),
  percentual      numeric(5,2) not null,
  valor           numeric(16,2) not null,
  criado_em       timestamptz not null default now()
);
create index idx_dist_cc_lancamento on lancamento_distribuicao_cc(lancamento_id);

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table baixas enable row level security;
alter table lancamento_distribuicao_conta enable row level security;
alter table lancamento_distribuicao_cc enable row level security;

create policy tenant_isolation_baixas on baixas for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
create policy tenant_isolation_dist_conta on lancamento_distribuicao_conta for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
create policy tenant_isolation_dist_cc on lancamento_distribuicao_cc for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- Auditoria também nas tabelas novas
-- ----------------------------------------------------------------------------
create trigger trg_auditoria_baixas after insert or update or delete on baixas for each row execute function fn_auditoria();
create trigger trg_auditoria_dist_conta after insert or update or delete on lancamento_distribuicao_conta for each row execute function fn_auditoria();
create trigger trg_auditoria_dist_cc after insert or update or delete on lancamento_distribuicao_cc for each row execute function fn_auditoria();

-- ----------------------------------------------------------------------------
-- Recalcula automaticamente o status do compromisso (Pago / Parcial /
-- mantém Em aberto ou Inadimplente) sempre que uma baixa muda.
-- ----------------------------------------------------------------------------
create or replace function fn_atualizar_status_lancamento() returns trigger as $$
declare
  v_lancamento_id uuid := coalesce(new.lancamento_id, old.lancamento_id);
  v_valor numeric;
  v_pago numeric;
begin
  select abs(valor) into v_valor from lancamentos where id = v_lancamento_id;
  select coalesce(sum(valor_pago + desconto), 0) into v_pago from baixas where lancamento_id = v_lancamento_id;

  update lancamentos
  set status = case
        when v_pago >= v_valor then 'pago'
        when v_pago > 0 then 'parcial'
        else status
      end,
      data_pagamento = case when v_pago >= v_valor then (select max(data) from baixas where lancamento_id = v_lancamento_id) else data_pagamento end
  where id = v_lancamento_id;

  return coalesce(new, old);
end;
$$ language plpgsql security definer;

create trigger trg_atualizar_status_lancamento
  after insert or update or delete on baixas
  for each row execute function fn_atualizar_status_lancamento();

-- ----------------------------------------------------------------------------
-- STORAGE — bucket privado para anexos (notas fiscais, comprovantes)
-- Caminho do arquivo segue o padrão: {tenant_id}/{lancamento_id}/{arquivo}
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('anexos', 'anexos', false)
on conflict (id) do nothing;

create policy "tenant_le_seus_anexos" on storage.objects for select
  using (bucket_id = 'anexos' and (storage.foldername(name))[1] = auth_tenant_id()::text);

create policy "tenant_sobe_seus_anexos" on storage.objects for insert
  with check (bucket_id = 'anexos' and (storage.foldername(name))[1] = auth_tenant_id()::text);

create policy "tenant_exclui_seus_anexos" on storage.objects for delete
  using (bucket_id = 'anexos' and (storage.foldername(name))[1] = auth_tenant_id()::text);
