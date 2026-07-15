-- ============================================================================
-- MIGRAÇÃO 008 — Borderô de Antecipação de Recebíveis (FIDC/Factoring)
-- Rode em duas etapas (igual à migração 005 — o ALTER TYPE precisa ser
-- executado sozinho antes do resto).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ETAPA 1 — rode ISOLADO primeiro:
-- ----------------------------------------------------------------------------
alter type tipo_favorecido add value if not exists 'fidc_factoring';


-- ----------------------------------------------------------------------------
-- ETAPA 2 — depois de rodar a linha acima sozinha, rode o resto:
-- ----------------------------------------------------------------------------

create table operacoes_antecipacao (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references tenants(id) on delete cascade,
  grupo_empresarial_id  uuid not null references grupos_empresariais(id),
  favorecido_id         uuid not null references favorecidos(id), -- o FIDC/Factoring
  numero_bordero        text,
  data_operacao         date not null,
  chave_acesso_nfe      text,
  xml_anexo_url         text,
  xml_anexo_nome        text,
  plano_conta_id        uuid references plano_contas(id), -- usado só quando NÃO há títulos vinculados
  valor_face            numeric(16,2) not null,
  taxa_desagio          numeric(6,3),
  valor_desagio         numeric(16,2) not null default 0,
  iof                   numeric(16,2) not null default 0,
  outras_taxas          numeric(16,2) not null default 0,
  valor_liquido         numeric(16,2) not null,
  conta_bancaria_id     uuid not null references contas_bancarias(id), -- conta que recebe o dinheiro
  observacoes           text,
  criado_por            uuid references usuarios(id),
  criado_em             timestamptz not null default now()
);
create index idx_borderos_tenant on operacoes_antecipacao(tenant_id, data_operacao);

-- Rastreabilidade: liga baixas e transferências geradas de volta ao borderô que as originou
alter table baixas add column if not exists bordero_id uuid references operacoes_antecipacao(id);
alter table lancamentos add column if not exists bordero_id uuid references operacoes_antecipacao(id);

alter table operacoes_antecipacao enable row level security;
create policy tenant_isolation_borderos on operacoes_antecipacao
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

create trigger trg_auditoria_borderos
  after insert or update or delete on operacoes_antecipacao
  for each row execute function fn_auditoria();
