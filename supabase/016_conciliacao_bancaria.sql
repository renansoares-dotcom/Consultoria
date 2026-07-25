-- ============================================================================
-- MIGRAÇÃO 016 — Conciliação Bancária (importação de extrato .ofx)
--
-- Decisão registrada no Product Decisions Log em 24/07/2026: conciliação via
-- importação de arquivo .ofx (padrão universal suportado por todos os bancos
-- brasileiros), com matching semi-automático — nunca baixa automática sem
-- confirmação do usuário.
--
-- Modelo: cada IMPORTAÇÃO gera um cabeçalho (extratos_importados) e uma linha
-- por transação do extrato (extrato_linhas). Cada linha pode ser conciliada
-- contra uma BAIXA já existente (baixas é o ponto de verdade do que já saiu/
-- entrou de fato numa conta bancária — ver 007_views_baixas_parciais.sql).
-- Uma baixa só pode ser conciliada uma vez (unique em baixa_id).
-- ============================================================================

create type status_conciliacao as enum ('pendente', 'conciliado', 'ignorado');

create table extratos_importados (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references tenants(id) on delete cascade,
  conta_bancaria_id uuid not null references contas_bancarias(id),
  nome_arquivo      text,
  periodo_inicio    date,
  periodo_fim       date,
  saldo_final_informado numeric(16,2),   -- <BALAMT> do OFX, quando presente — só referência, não é gravado em lugar nenhum
  total_linhas      integer not null default 0,
  criado_por        uuid references usuarios(id),
  criado_em         timestamptz not null default now()
);

create table extrato_linhas (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references tenants(id) on delete cascade,
  extrato_importado_id uuid not null references extratos_importados(id) on delete cascade,
  conta_bancaria_id   uuid not null references contas_bancarias(id),
  fitid               text,             -- ID único da transação dado pelo banco (OFX <FITID>) — usado pra não reimportar a mesma linha duas vezes
  data                date not null,
  valor               numeric(16,2) not null,   -- positivo=crédito, negativo=débito (mesma convenção do OFX)
  descricao           text,
  tipo_ofx            text,             -- <TRNTYPE> do OFX (DEBIT, CREDIT, FEE, ...) — só informativo
  status              status_conciliacao not null default 'pendente',
  baixa_id            uuid references baixas(id),
  conciliado_por      uuid references usuarios(id),
  conciliado_em       timestamptz,
  criado_em           timestamptz not null default now()
);

-- Uma mesma linha de extrato (mesmo FITID, mesma conta) não pode ser
-- importada duas vezes — protege contra reimportar um período sobreposto.
-- Parcial porque nem todo banco garante FITID preenchido.
create unique index uq_extrato_linha_fitid
  on extrato_linhas (tenant_id, conta_bancaria_id, fitid)
  where fitid is not null;

-- Uma baixa só pode estar conciliada com uma linha de extrato por vez.
create unique index uq_extrato_linha_baixa
  on extrato_linhas (baixa_id)
  where baixa_id is not null;

create index idx_extrato_linhas_conta_status on extrato_linhas(tenant_id, conta_bancaria_id, status);
create index idx_extrato_linhas_data on extrato_linhas(tenant_id, data);

alter table extratos_importados enable row level security;
alter table extrato_linhas enable row level security;

create policy tenant_isolation_extratos_importados on extratos_importados
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());
create policy tenant_isolation_extrato_linhas on extrato_linhas
  for all using (tenant_id = auth_tenant_id()) with check (tenant_id = auth_tenant_id());

-- ----------------------------------------------------------------------------
-- Sugestões de conciliação: candidatas a match entre linhas pendentes do
-- extrato e baixas ainda não conciliadas com nenhuma linha, na mesma conta,
-- com o mesmo valor (considerando juros/multa/desconto no valor líquido da
-- baixa) e data em uma janela de 3 dias — o front decide o que fazer com
-- isso, a view só reduz o trabalho de busca.
-- ----------------------------------------------------------------------------
create or replace view vw_conciliacao_sugestoes as
select
  el.id as extrato_linha_id,
  el.tenant_id,
  el.conta_bancaria_id,
  el.data as data_extrato,
  el.valor as valor_extrato,
  el.descricao,
  b.id as baixa_id,
  b.data as data_baixa,
  (b.valor_pago + b.juros + b.multa - b.desconto) as valor_baixa_liquido,
  l.descricao as descricao_lancamento,
  abs(el.data - b.data) as diferenca_dias
from extrato_linhas el
join baixas b
  on b.tenant_id = el.tenant_id
  and coalesce(b.conta_bancaria_id, (select l2.conta_bancaria_id from lancamentos l2 where l2.id = b.lancamento_id)) = el.conta_bancaria_id
  and abs((b.valor_pago + b.juros + b.multa - b.desconto) - abs(el.valor)) < 0.01
  and abs(el.data - b.data) <= 3
join lancamentos l on l.id = b.lancamento_id
where el.status = 'pendente'
  and not exists (select 1 from extrato_linhas x where x.baixa_id = b.id);

alter view vw_conciliacao_sugestoes set (security_invoker = on);
