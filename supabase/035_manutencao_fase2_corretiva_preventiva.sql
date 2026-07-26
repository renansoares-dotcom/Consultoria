-- ============================================================================
-- MIGRAÇÃO 035 — Manutenção Fase 2 (Corretiva e Preventiva) — 100% aditivo
--
-- Decisão registrada no Product Decisions Log em 25/07/2026. Não altera
-- nenhuma coluna existente de ordens_manutencao — só adiciona.
-- ============================================================================

create type status_solicitacao_manutencao as enum ('aberta', 'triada', 'convertida', 'rejeitada');
create type tipo_gatilho_plano as enum ('calendario', 'medidor');

create table solicitacoes_manutencao (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  equipamento_id        uuid not null references equipamentos(id),
  solicitante_id        uuid references usuarios(id),
  descricao             text not null,
  prioridade_sugerida   prioridade_manutencao not null default 'media',
  status                status_solicitacao_manutencao not null default 'aberta',
  ordem_manutencao_id   uuid references ordens_manutencao(id),
  motivo_rejeicao       text,
  criado_em             timestamptz not null default now()
);
create index idx_solicitacoes_manutencao_status on solicitacoes_manutencao(tenant_id, status);

alter table ordens_manutencao
  add column solicitacao_id         uuid references solicitacoes_manutencao(id),
  add column plano_manutencao_id    uuid,   -- FK criada depois de planos_manutencao existir
  add column causa                  text,
  add column sla_previsto           timestamptz,
  add column requer_aprovacao       boolean not null default false,
  add column aprovado_por           uuid references usuarios(id),
  add column aprovado_em            timestamptz,
  add column ultima_alteracao_por   uuid references usuarios(id);

create table tarefas_os (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  ordem_manutencao_id   uuid not null references ordens_manutencao(id) on delete cascade,
  descricao             text not null,
  concluida             boolean not null default false,
  concluida_por         uuid references usuarios(id),
  concluida_em          timestamptz,
  ordem                 integer not null default 0,
  criado_em             timestamptz not null default now()
);
create index idx_tarefas_os_ordem on tarefas_os(ordem_manutencao_id);

create table apontamentos_manutencao (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  ordem_manutencao_id   uuid not null references ordens_manutencao(id) on delete cascade,
  executante_id         uuid references usuarios(id),
  data                  date not null default current_date,
  horas_trabalhadas     numeric(6,2) not null,
  descricao             text,
  criado_em             timestamptz not null default now()
);
create index idx_apontamentos_manutencao_ordem on apontamentos_manutencao(ordem_manutencao_id);

create table ordens_manutencao_anexos (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  ordem_manutencao_id   uuid not null references ordens_manutencao(id) on delete cascade,
  arquivo_path          text not null,
  arquivo_nome          text not null,
  enviado_por           uuid references usuarios(id),
  criado_em             timestamptz not null default now()
);

create table planos_manutencao (
  id                          uuid primary key default gen_random_uuid(),
  tenant_id                   uuid not null references tenants(id) on delete cascade,
  equipamento_id              uuid not null references equipamentos(id),
  nome                        text not null,
  tipo_gatilho                tipo_gatilho_plano not null default 'calendario',
  periodicidade_dias          integer,
  proxima_execucao_data       date,
  medidor_id                  uuid references medidores(id),
  intervalo_leitura           numeric(16,3),
  proxima_execucao_leitura    numeric(16,3),
  prioridade                  prioridade_manutencao not null default 'media',
  ativo                       boolean not null default true,
  criado_em                   timestamptz not null default now(),
  check (
    (tipo_gatilho = 'calendario' and periodicidade_dias is not null and proxima_execucao_data is not null) or
    (tipo_gatilho = 'medidor' and medidor_id is not null and intervalo_leitura is not null)
  )
);

create table tarefas_plano_manutencao (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references tenants(id) on delete cascade,
  plano_id    uuid not null references planos_manutencao(id) on delete cascade,
  descricao   text not null,
  ordem       integer not null default 0
);

alter table ordens_manutencao add constraint fk_ordens_manutencao_plano foreign key (plano_manutencao_id) references planos_manutencao(id);

create table ordens_manutencao_historico (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references tenants(id) on delete cascade,
  ordem_manutencao_id     uuid not null references ordens_manutencao(id) on delete cascade,
  status_anterior         status_ordem_manutencao,
  status_novo             status_ordem_manutencao,
  responsavel_anterior    uuid references usuarios(id),
  responsavel_novo        uuid references usuarios(id),
  alterado_por            uuid references usuarios(id),
  criado_em               timestamptz not null default now()
);

alter table solicitacoes_manutencao enable row level security;
create policy tenant_isolation_solicitacoes_manutencao on solicitacoes_manutencao for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table tarefas_os enable row level security;
create policy tenant_isolation_tarefas_os on tarefas_os for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table apontamentos_manutencao enable row level security;
create policy tenant_isolation_apontamentos_manutencao on apontamentos_manutencao for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table ordens_manutencao_anexos enable row level security;
create policy tenant_isolation_ordens_manutencao_anexos on ordens_manutencao_anexos for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table planos_manutencao enable row level security;
create policy tenant_isolation_planos_manutencao on planos_manutencao for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table tarefas_plano_manutencao enable row level security;
create policy tenant_isolation_tarefas_plano_manutencao on tarefas_plano_manutencao for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table ordens_manutencao_historico enable row level security;
create policy tenant_isolation_ordens_manutencao_historico on ordens_manutencao_historico for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- SLA automático na criação, por prioridade (ajustável depois manualmente se preciso)
create or replace function fn_definir_sla_os()
returns trigger as $$
begin
  if new.sla_previsto is null then
    new.sla_previsto := new.criado_em + (case new.prioridade
      when 'critica' then interval '4 hours'
      when 'alta' then interval '24 hours'
      when 'media' then interval '72 hours'
      else interval '168 hours'
    end);
  end if;
  return new;
end;
$$ language plpgsql;

create trigger trg_definir_sla_os
  before insert on ordens_manutencao
  for each row execute function fn_definir_sla_os();

-- Histórico: toda mudança de status ou responsável vira uma linha auditável
create or replace function fn_registrar_historico_os()
returns trigger as $$
begin
  if new.status is distinct from old.status or new.responsavel_id is distinct from old.responsavel_id then
    insert into ordens_manutencao_historico (tenant_id, ordem_manutencao_id, status_anterior, status_novo, responsavel_anterior, responsavel_novo, alterado_por)
    values (new.tenant_id, new.id, old.status, new.status, old.responsavel_id, new.responsavel_id, new.ultima_alteracao_por);
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_registrar_historico_os
  after update on ordens_manutencao
  for each row execute function fn_registrar_historico_os();

-- ----------------------------------------------------------------------------
-- Geração de OS preventivas vencidas — chamada manualmente (RPC) por enquanto;
-- agendamento automático via pg_cron/Edge Function fica em Ideias Futuras.
-- ----------------------------------------------------------------------------
create or replace function fn_gerar_os_preventivas_vencidas()
returns table(ordem_id uuid, plano_nome text) as $$
declare
  v_plano record;
  v_nova_os_id uuid;
  v_ja_aberta boolean;
begin
  for v_plano in
    select p.* from planos_manutencao p
    where p.ativo = true
      and p.tenant_id = auth_tenant_id()
      and (
        (p.tipo_gatilho = 'calendario' and p.proxima_execucao_data <= current_date)
        or (p.tipo_gatilho = 'medidor' and exists (
          select 1 from medidores m where m.id = p.medidor_id and m.leitura_atual >= p.proxima_execucao_leitura
        ))
      )
  loop
    select exists(
      select 1 from ordens_manutencao om
      where om.plano_manutencao_id = v_plano.id and om.status in ('aberta','em_andamento')
    ) into v_ja_aberta;

    if not v_ja_aberta then
      insert into ordens_manutencao (tenant_id, equipamento_id, tipo, prioridade, descricao_problema, plano_manutencao_id)
      values (v_plano.tenant_id, v_plano.equipamento_id, 'preventiva', v_plano.prioridade, 'Manutenção preventiva: ' || v_plano.nome, v_plano.id)
      returning id into v_nova_os_id;

      insert into tarefas_os (tenant_id, ordem_manutencao_id, descricao, ordem)
      select v_plano.tenant_id, v_nova_os_id, tp.descricao, tp.ordem
      from tarefas_plano_manutencao tp where tp.plano_id = v_plano.id;

      if v_plano.tipo_gatilho = 'calendario' then
        update planos_manutencao set proxima_execucao_data = current_date + (v_plano.periodicidade_dias || ' days')::interval where id = v_plano.id;
      else
        update planos_manutencao set proxima_execucao_leitura = v_plano.proxima_execucao_leitura + v_plano.intervalo_leitura where id = v_plano.id;
      end if;

      ordem_id := v_nova_os_id;
      plano_nome := v_plano.nome;
      return next;
    end if;
  end loop;
end;
$$ language plpgsql security definer;
