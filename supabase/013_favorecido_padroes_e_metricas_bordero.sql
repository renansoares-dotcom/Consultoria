-- ============================================================================
-- MIGRAÇÃO 013
-- 1) Favorecido ganha Conta Bancária e Centro de Custo padrão (preenchimento
--    automático ao selecioná-lo num lançamento).
-- 2) Borderô passa a guardar o prazo médio (dias) e a taxa de deságio
--    equivalente ao mês (normalizada), pra comparar operações de prazos
--    diferentes de forma justa.
-- ============================================================================

alter table favorecidos
  add column if not exists conta_bancaria_padrao_id uuid references contas_bancarias(id),
  add column if not exists centro_custo_padrao_id uuid references centros_custo(id);

alter table operacoes_antecipacao
  add column if not exists prazo_medio_dias numeric(6,2),
  add column if not exists taxa_desagio_mensal_efetiva numeric(6,3);

comment on column operacoes_antecipacao.prazo_medio_dias is
  'Prazo médio (em dias) dos títulos antecipados, ponderado pelo valor de cada um.';
comment on column operacoes_antecipacao.taxa_desagio_mensal_efetiva is
  'Taxa de deságio normalizada para % ao mês, considerando o prazo médio — permite comparar operações com prazos diferentes.';
