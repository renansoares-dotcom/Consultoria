-- ============================================================================
-- MIGRAÇÃO 038 — Manutenção Fases 5+6 (Mobilidade + Camada IoT/Alertas)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026. 100% aditivo.
-- Sem hardware IoT real; sem decisão automática (só alerta pra humano agir).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Fase 5 — Perfis de acesso relevantes pra Manutenção (primeira vez que
-- permissão é realmente semeada além do Administrador padrão).
-- ----------------------------------------------------------------------------
insert into perfis_acesso (tenant_id, nome, permissoes)
select 'fc45b57b-ea56-4e20-88b0-14ad00030cdf', nome, permissoes::jsonb
from (values
  ('Operador', '{"manutencao_solicitar":"rw","manutencao_executar":"rw"}'),
  ('Mantenedor', '{"manutencao_solicitar":"rw","manutencao_executar":"rw","manutencao_os":"rw","manutencao_pecas":"rw"}'),
  ('Planejador', '{"manutencao_solicitar":"rw","manutencao_executar":"rw","manutencao_os":"rw","manutencao_pecas":"rw","manutencao_planos":"rw","manutencao_cadastro":"rw"}'),
  ('Gestor', '{"manutencao_solicitar":"rw","manutencao_executar":"rw","manutencao_os":"rw","manutencao_pecas":"rw","manutencao_planos":"rw","manutencao_cadastro":"rw","manutencao_custos":"r","manutencao_aprovacao":"rw"}')
) as novos(nome, permissoes)
where not exists (select 1 from perfis_acesso p where p.tenant_id = 'fc45b57b-ea56-4e20-88b0-14ad00030cdf' and p.nome = novos.nome);

-- ----------------------------------------------------------------------------
-- Fase 6 — Camada de dados pra sensores: limites por medidor + alerta
-- automático quando uma leitura ultrapassa o limite. NUNCA cria OS sozinho.
-- ----------------------------------------------------------------------------
create table limites_medidor (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  medidor_id        uuid not null references medidores(id) on delete cascade,
  limite_minimo     numeric(16,3),
  limite_maximo     numeric(16,3),
  ativo             boolean not null default true,
  criado_em         timestamptz not null default now(),
  check (limite_minimo is not null or limite_maximo is not null)
);
create unique index idx_limites_medidor_unico on limites_medidor(medidor_id) where ativo = true;

create type status_alerta_medidor as enum ('pendente', 'revisado', 'convertido_em_solicitacao', 'ignorado');

create table alertas_medidor (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  medidor_id        uuid not null references medidores(id),
  leitura_id        uuid references leituras_medidores(id),
  leitura_valor     numeric(16,3) not null,
  limite_violado    text not null,   -- 'minimo' ou 'maximo'
  status            status_alerta_medidor not null default 'pendente',
  revisado_por      uuid references usuarios(id),
  revisado_em       timestamptz,
  criado_em         timestamptz not null default now()
);
create index idx_alertas_medidor_status on alertas_medidor(tenant_id, status);

alter table limites_medidor enable row level security;
create policy tenant_isolation_limites_medidor on limites_medidor for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
alter table alertas_medidor enable row level security;
create policy tenant_isolation_alertas_medidor on alertas_medidor for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- Ao registrar uma leitura, confere contra o limite ativo do medidor. Se
-- violar, só cria o ALERTA — nunca abre solicitação/OS sozinho.
create or replace function fn_verificar_limite_medidor()
returns trigger as $$
declare
  v_limite limites_medidor%rowtype;
begin
  select * into v_limite from limites_medidor where medidor_id = new.medidor_id and ativo = true limit 1;
  if v_limite.id is null then
    return new;
  end if;

  if v_limite.limite_maximo is not null and new.leitura > v_limite.limite_maximo then
    insert into alertas_medidor (tenant_id, medidor_id, leitura_id, leitura_valor, limite_violado)
    values (new.tenant_id, new.medidor_id, new.id, new.leitura, 'maximo');
  elsif v_limite.limite_minimo is not null and new.leitura < v_limite.limite_minimo then
    insert into alertas_medidor (tenant_id, medidor_id, leitura_id, leitura_valor, limite_violado)
    values (new.tenant_id, new.medidor_id, new.id, new.leitura, 'minimo');
  end if;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_verificar_limite_medidor
  after insert on leituras_medidores
  for each row execute function fn_verificar_limite_medidor();

-- ----------------------------------------------------------------------------
-- Previsão simples (heurística estatística, não modelo treinado): próxima
-- falha provável = fim da última parada + MTBF médio do equipamento.
-- ----------------------------------------------------------------------------
create or replace view vw_previsao_falha_equipamento as
select
  ce.equipamento_id,
  ce.tenant_id,
  ce.codigo,
  ce.nome,
  ce.mtbf_horas,
  ultima.fim as ultima_parada_fim,
  case when ce.mtbf_horas is not null and ultima.fim is not null
    then ultima.fim + (ce.mtbf_horas || ' hours')::interval
    else null
  end as proxima_falha_estimada
from vw_confiabilidade_equipamento ce
left join lateral (
  select fim from paradas_producao pp
  where pp.equipamento_id = ce.equipamento_id and pp.fim is not null
  order by pp.fim desc limit 1
) ultima on true;

alter view vw_previsao_falha_equipamento set (security_invoker = on);
