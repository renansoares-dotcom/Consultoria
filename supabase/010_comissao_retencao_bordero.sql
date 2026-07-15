-- ============================================================================
-- MIGRAÇÃO 010 — Comissão (ad valorem) e Retenção/Recompra no Borderô
-- Baseado em um borderô real de FIDC. Dois conceitos que faltavam:
--   - Comissão: taxa de serviço proporcional ao valor (separada do deságio)
--   - Retenção/Recompra: valor retido como garantia — NÃO é custo, é um
--     valor a receber depois. Por isso existem dois "líquidos":
--       Líquido da Operação        = Face − Deságio − Comissão − Despesas − IOF
--       Valor Pago ao Cedente      = Líquido da Operação − Retenção  (é o que
--                                     realmente cai na conta bancária)
-- ============================================================================

alter table operacoes_antecipacao
  add column if not exists numero_contrato text,
  add column if not exists taxa_comissao numeric(6,3),
  add column if not exists valor_comissao numeric(16,2) not null default 0,
  add column if not exists taxa_retencao numeric(6,3),
  add column if not exists valor_retencao numeric(16,2) not null default 0,
  add column if not exists valor_pago_cedente numeric(16,2);

comment on column operacoes_antecipacao.valor_liquido is
  'Líquido da Operação = Face − Deságio − Comissão − Despesas Bancárias − IOF (ainda inclui a retenção).';
comment on column operacoes_antecipacao.valor_pago_cedente is
  'Valor que realmente cai na conta bancária = Líquido da Operação − Retenção/Recompra. É este valor (não o valor_liquido) que deve ser usado para conferir baixas e transferências.';
