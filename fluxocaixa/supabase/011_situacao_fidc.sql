-- ============================================================================
-- MIGRAÇÃO 011 — Situação do título junto ao FIDC/Factoring (coobrigação)
--
-- Quando um título é antecipado, ele já está "pago" para a empresa (o
-- dinheiro entrou via baixa do borderô) — mas para o FIDC ele só fica de
-- fato quitado quando o SACADO paga na data de vencimento. Até lá, a
-- empresa segue coobrigada: se o sacado não pagar, ela é obrigada a
-- recomprar o título.
--
-- Isso é um controle de RISCO, separado do fluxo de caixa — por isso fica
-- em campos próprios, sem tocar em status/baixas já existentes.
--
-- situacao_fidc:
--   'pendente'   → aguardando o sacado pagar o FIDC na data de vencimento
--   'liquidado'  → sacado pagou o FIDC, risco encerrado
--   'recomprado' → sacado não pagou, empresa recomprou o título (gera saída)
-- ============================================================================

alter table lancamentos
  add column if not exists situacao_fidc text check (situacao_fidc in ('pendente','liquidado','recomprado')),
  add column if not exists data_situacao_fidc date;

create index if not exists idx_lancamentos_situacao_fidc on lancamentos(situacao_fidc) where situacao_fidc is not null;
