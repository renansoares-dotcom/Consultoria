-- ============================================================================
-- MIGRAÇÃO 015 — Correntista robusto
-- O cadastro de "Favorecido" evolui para um cadastro completo de Correntista,
-- servindo tanto ao Financeiro quanto à futura emissão de nota fiscal e CRM.
-- A operação (venda/compra/pagamento) é quem decide se ele age como cliente
-- ou fornecedor — o cadastro passa a ser único e mais robusto.
-- ============================================================================

alter table favorecidos
  -- Dados gerais
  add column if not exists nome_fantasia text,
  add column if not exists telefone text,
  add column if not exists email text,
  add column if not exists site text,

  -- Endereço
  add column if not exists cep text,
  add column if not exists logradouro text,
  add column if not exists numero text,
  add column if not exists complemento text,
  add column if not exists bairro text,
  add column if not exists cidade text,
  add column if not exists uf text,
  add column if not exists pais text default 'Brasil',

  -- Dados fiscais (relevantes para emissão de NFe)
  add column if not exists inscricao_estadual text,
  add column if not exists inscricao_municipal text,
  add column if not exists indicador_ie text, -- 'contribuinte' | 'isento' | 'nao_contribuinte'
  add column if not exists regime_tributario text, -- 'simples_nacional' | 'lucro_presumido' | 'lucro_real'
  add column if not exists observacoes_fiscais text,

  -- Comercial / CRM
  add column if not exists contato_responsavel text,
  add column if not exists telefone_contato text,
  add column if not exists email_contato text,
  add column if not exists limite_credito numeric(16,2),
  add column if not exists observacoes_comerciais text;
