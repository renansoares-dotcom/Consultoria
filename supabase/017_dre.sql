-- ============================================================================
-- MIGRAÇÃO 017 — DRE (Demonstrativo de Resultado do Exercício)
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: DRE por regime
-- de competência (usa lancamentos.data e lancamentos.valor, não depende de
-- estar pago), com uma classificação gerencial própria no Plano de Contas —
-- o campo "tipo" existente (entrada/saída/transferência) não tem granularidade
-- suficiente para montar as linhas do DRE.
--
-- Contas sem classificação (padrão ao criar) aparecem agrupadas como "Não
-- classificado" no relatório — nunca escondidas, pra não gerar um DRE que
-- pareça fechar mas esteja incompleto.
-- ============================================================================

create type classificacao_dre as enum (
  'receita_bruta',
  'deducoes',
  'cmv',
  'despesa_administrativa',
  'despesa_comercial',
  'receita_financeira',
  'despesa_financeira',
  'outras_receitas',
  'outras_despesas',
  'ir_csll',
  'nao_classificado'
);

alter table plano_contas
  add column classificacao_dre classificacao_dre not null default 'nao_classificado';

comment on column plano_contas.classificacao_dre is
  'Linha do DRE em que esta conta entra. Independente de plano_contas.tipo (que é sobre fluxo de caixa: entrada/saída/transferência).';

-- ----------------------------------------------------------------------------
-- View de apoio: soma lancamentos por classificação DRE, por competência
-- (lancamentos.data), excluindo transferências (não são resultado, são só
-- movimentação entre contas). O front agrupa isso nas linhas do relatório e
-- aplica os filtros de período/grupo empresarial.
-- ----------------------------------------------------------------------------
create or replace view vw_dre_lancamentos as
select
  l.id as lancamento_id,
  l.tenant_id,
  l.grupo_empresarial_id,
  l.data,
  l.valor,
  pc.classificacao_dre,
  pc.tipo as tipo_plano_contas,
  pc.nome_conta
from lancamentos l
join plano_contas pc on pc.id = l.plano_conta_id
where pc.tipo <> 'transferencia';

alter view vw_dre_lancamentos set (security_invoker = on);
