-- ============================================================================
-- MIGRAÇÃO 002 — Transferências em lançamento único
-- Rode este script no SQL Editor do Supabase (depois do schema.sql original).
-- Decisão de produto: transferência = 1 lançamento com conta de origem
-- (conta_bancaria_id, já existente) e conta de destino (nova coluna).
-- Status "Pago" baixa o saldo na hora — não existe conciliação separada,
-- os relatórios somam lançamentos com status='pago' em tempo real.
-- ============================================================================

alter table lancamentos
  add column if not exists conta_destino_id uuid references contas_bancarias(id);

comment on column lancamentos.conta_bancaria_id is
  'Conta de débito/crédito para Entrada e Saída. Para Transferência, é a conta de ORIGEM.';
comment on column lancamentos.conta_destino_id is
  'Preenchido apenas quando o plano de contas é do tipo "transferencia" — conta de DESTINO dos recursos.';

create index if not exists idx_lancamentos_conta_destino on lancamentos(conta_destino_id);

-- View de apoio: saldo por conta bancária, considerando entrada/saída direto
-- na conta e o efeito de transferências (sai da origem, entra no destino).
-- Só soma lançamentos com status = 'pago' (saldo realizado/baixado).
create or replace view vw_saldo_contas as
select
  cb.id as conta_bancaria_id,
  cb.tenant_id,
  cb.nome,
  cb.saldo_inicial
    + coalesce(sum(case when l.conta_bancaria_id = cb.id and l.status = 'pago' and l.conta_destino_id is null then l.valor end), 0)
    + coalesce(sum(case when l.conta_bancaria_id = cb.id and l.status = 'pago' and l.conta_destino_id is not null then -abs(l.valor) end), 0)
    + coalesce(sum(case when l.conta_destino_id = cb.id and l.status = 'pago' then abs(l.valor) end), 0)
    as saldo_atual
from contas_bancarias cb
left join lancamentos l
  on l.conta_bancaria_id = cb.id or l.conta_destino_id = cb.id
group by cb.id, cb.tenant_id, cb.nome, cb.saldo_inicial;

alter view vw_saldo_contas set (security_invoker = on);
