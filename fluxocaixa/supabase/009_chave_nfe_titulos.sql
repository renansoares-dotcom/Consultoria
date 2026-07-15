-- ============================================================================
-- MIGRAÇÃO 009 — Chave de acesso NFe por título (para importação em lote)
-- Diferente da chave no cabeçalho do borderô (essa é da nota do FIDC), esta
-- é a chave de CADA título/duplicata antecipado, usada para evitar importar
-- a mesma nota duas vezes.
-- ============================================================================

alter table lancamentos add column if not exists chave_acesso_nfe text;
create index if not exists idx_lancamentos_chave_nfe on lancamentos(chave_acesso_nfe) where chave_acesso_nfe is not null;
