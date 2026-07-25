-- ============================================================================
-- MIGRAÇÃO 028 — Módulo Manutenção (MVP)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: cadastro de
-- equipamentos + ordens de manutenção (preventiva/corretiva). Primeiro
-- módulo do Bloco C desacoplado do fluxo central — não mexe em
-- estoque/produção/financeiro.
-- ============================================================================

create type status_equipamento as enum ('ativo', 'em_manutencao', 'inativo');
create type tipo_ordem_manutencao as enum ('preventiva', 'corretiva');
create type status_ordem_manutencao as enum ('aberta', 'em_andamento', 'concluida', 'cancelada');
create type prioridade_manutencao as enum ('baixa', 'media', 'alta', 'critica');

create table equipamentos (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  codigo                text not null,
  nome                  text not null,
  tipo                  text,          -- máquina, veículo, instalação... texto livre, sem enum pra não engessar
  localizacao           text,
  fabricante            text,
  modelo                text,
  numero_serie          text,
  data_aquisicao        date,
  status                status_equipamento not null default 'ativo',
  periodicidade_preventiva_dias integer,   -- ex: 90 = revisão a cada 90 dias
  proxima_preventiva    date,
  observacoes           text,
  criado_em             timestamptz not null default now()
);
create unique index idx_equipamentos_codigo on equipamentos(tenant_id, codigo);

create table ordens_manutencao (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references tenants(id) on delete cascade,
  equipamento_id      uuid not null references equipamentos(id),
  tipo                tipo_ordem_manutencao not null,
  prioridade          prioridade_manutencao not null default 'media',
  status              status_ordem_manutencao not null default 'aberta',
  descricao_problema  text not null,
  solucao_aplicada    text,
  data_abertura       date not null default current_date,
  data_prevista       date,
  data_conclusao      date,
  custo_pecas         numeric(16,2) default 0,
  custo_mao_obra      numeric(16,2) default 0,
  responsavel_id      uuid references usuarios(id),
  criado_por          uuid references usuarios(id),
  criado_em           timestamptz not null default now()
);

create index idx_ordens_manutencao_status on ordens_manutencao(tenant_id, status);
create index idx_ordens_manutencao_equipamento on ordens_manutencao(equipamento_id);

alter table equipamentos enable row level security;
create policy tenant_isolation_equipamentos on equipamentos
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table ordens_manutencao enable row level security;
create policy tenant_isolation_ordens_manutencao on ordens_manutencao
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- Ao abrir uma ordem CORRETIVA, o equipamento vira "em_manutencao"
-- automaticamente — reflete a realidade (máquina quebrada/parada).
create or replace function fn_marcar_equipamento_em_manutencao()
returns trigger as $$
begin
  if new.tipo = 'corretiva' and new.status in ('aberta','em_andamento') then
    update equipamentos set status = 'em_manutencao' where id = new.equipamento_id;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_marcar_equipamento_em_manutencao
  after insert on ordens_manutencao
  for each row execute function fn_marcar_equipamento_em_manutencao();

-- Ao concluir/cancelar QUALQUER ordem, se não houver outra ordem aberta pro
-- mesmo equipamento, ele volta a "ativo" e a próxima preventiva é recalculada.
create or replace function fn_liberar_equipamento_pos_manutencao()
returns trigger as $$
declare
  v_outras_abertas integer;
begin
  if new.status in ('concluida','cancelada') and old.status not in ('concluida','cancelada') then
    select count(*) into v_outras_abertas from ordens_manutencao
    where equipamento_id = new.equipamento_id and status in ('aberta','em_andamento') and id <> new.id;

    if v_outras_abertas = 0 then
      update equipamentos set status = 'ativo' where id = new.equipamento_id;
    end if;

    if new.tipo = 'preventiva' and new.status = 'concluida' then
      update equipamentos
      set proxima_preventiva = current_date + (periodicidade_preventiva_dias || ' days')::interval
      where id = new.equipamento_id and periodicidade_preventiva_dias is not null;
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_liberar_equipamento_pos_manutencao
  after update of status on ordens_manutencao
  for each row execute function fn_liberar_equipamento_pos_manutencao();
