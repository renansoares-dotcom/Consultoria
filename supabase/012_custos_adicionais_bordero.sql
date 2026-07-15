-- ============================================================================
-- MIGRAÇÃO 012 — Novos campos de custo + ajuste de arredondamento no Borderô
--
-- outras_taxas passa a representar "Despesas Bancárias/Boletos" (valor
-- TOTAL da operação, não mais por título) — sem mudança de schema, só de
-- uso no app. Dois campos novos de custo, e um campo de ajuste manual pra
-- reconciliar diferença de centavos com o valor realmente transferido.
-- ============================================================================

alter table operacoes_antecipacao
  add column if not exists valor_assinatura_eletronica numeric(16,2) not null default 0,
  add column if not exists valor_outras_despesas numeric(16,2) not null default 0,
  add column if not exists ajuste_valor_final numeric(16,2) not null default 0;

comment on column operacoes_antecipacao.outras_taxas is
  'Despesas Bancárias / Boletos — valor TOTAL da operação (rateado proporcionalmente entre os títulos), não por título.';
comment on column operacoes_antecipacao.ajuste_valor_final is
  'Ajuste manual (+/-) para reconciliar pequenas diferenças de centavos entre o valor calculado e o valor realmente transferido pelo FIDC.';
