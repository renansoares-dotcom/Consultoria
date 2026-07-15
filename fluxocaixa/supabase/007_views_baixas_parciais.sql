-- ============================================================================
-- MIGRAÇÃO 007 — Views de apoio para relatórios considerarem baixas parciais
--
-- Até aqui, os relatórios somavam lancamentos.valor quando status='pago'.
-- Isso quebra com o novo modelo de baixas múltiplas: um compromisso
-- "parcial" tem uma parte já paga (deveria contar no Fluxo de Caixa) e uma
-- parte ainda em aberto (deveria contar em Contas a Receber/Pagar).
--
-- vw_realizado    → uma linha por BAIXA, já com tipo/grupo/conta do
--                    lançamento e datada pela data real do pagamento
--                    (não pela data de competência do lançamento).
-- vw_saldo_lancamento → uma linha por LANÇAMENTO com o saldo que ainda
--                    falta pagar (valor original − total já baixado).
-- ============================================================================

create or replace view vw_realizado as
select
  b.id as baixa_id,
  b.data as data_baixa,
  b.valor_pago,
  b.juros,
  b.multa,
  b.desconto,
  (b.valor_pago + b.juros + b.multa) as valor_desembolsado,
  l.id as lancamento_id,
  l.tenant_id,
  l.grupo_empresarial_id,
  l.plano_conta_id,
  l.centro_custo_id,
  l.favorecido_id,
  l.conta_bancaria_id,
  l.conta_destino_id,
  pc.tipo,
  pc.codigo_grupo,
  pc.nome_grupo,
  pc.codigo_conta,
  pc.nome_conta
from baixas b
join lancamentos l on l.id = b.lancamento_id
join plano_contas pc on pc.id = l.plano_conta_id;

alter view vw_realizado set (security_invoker = on);

create or replace view vw_saldo_lancamento as
select
  l.id as lancamento_id,
  l.tenant_id,
  l.status,
  l.valor as valor_original,
  coalesce(sum(b.valor_pago + b.desconto), 0) as total_quitado,
  abs(l.valor) - coalesce(sum(b.valor_pago + b.desconto), 0) as saldo_aberto
from lancamentos l
left join baixas b on b.lancamento_id = l.id
group by l.id, l.tenant_id, l.status, l.valor;

alter view vw_saldo_lancamento set (security_invoker = on);
