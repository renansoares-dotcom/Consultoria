-- ============================================================================
-- MIGRAÇÃO 023 — DRE: classificação ajustável por lançamento
--
-- Decisão registrada no Product Decisions Log em 25/07/2026 (diretriz trazida
-- pelo ChatGPT): mesma conta pode representar coisas diferentes dependendo da
-- origem real (mão de obra direta vs administrativa; frete de compra vs de
-- entrega). Campo opcional: quando preenchido, sobrepõe a classificação
-- padrão da conta só para aquele lançamento específico.
-- ============================================================================

alter table lancamentos add column classificacao_dre_override classificacao_dre;

comment on column lancamentos.classificacao_dre_override is
  'Sobrepõe plano_contas.classificacao_dre só para este lançamento. NULL = usa a classificação padrão da conta (comportamento normal).';

create or replace view vw_dre_lancamentos as
select
  l.id as lancamento_id,
  l.tenant_id,
  l.grupo_empresarial_id,
  l.data,
  l.valor,
  coalesce(l.classificacao_dre_override, pc.classificacao_dre) as classificacao_dre,
  pc.tipo as tipo_plano_contas,
  pc.nome_conta
from lancamentos l
join plano_contas pc on pc.id = l.plano_conta_id
where pc.tipo <> 'transferencia';

alter view vw_dre_lancamentos set (security_invoker = on);
