-- ============================================================================
-- MIGRAÇÃO 014 — Plano de Contas padrão por favorecido
-- Completa o conjunto de "padrões" do favorecido (conta bancária e centro de
-- custo já existiam desde a 013) — agora também o Plano de Contas referencial,
-- preenchido automaticamente ao selecionar o favorecido num lançamento novo.
-- ============================================================================

alter table favorecidos
  add column if not exists plano_conta_padrao_id uuid references plano_contas(id);
