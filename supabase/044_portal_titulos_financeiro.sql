-- ============================================================================
-- Migration: 044_portal_titulos_financeiro
-- Portal do Cliente — Slice 2 (Financeiro: meus títulos, leitura)
-- Data: 2026-07-27
--
-- Depende da identidade separada já construída na 043
-- (usuarios_portal / auth_portal_favorecido_id()).
--
-- Mesmo raciocínio do portal_meus_produtos() da 043: `lancamentos` tem
-- colunas de operação interna que o cliente NUNCA pode ver —
--   situacao_fidc / bordero_id: se o título foi vendido pra uma FIDC/factoring;
--   aprovado_por, centro_custo_id, plano_conta_id, classificacao_dre_override:
--   operação contábil/financeira interna.
-- RLS é por LINHA, não por coluna — uma política aditiva ali deixaria esses
-- campos tecnicamente acessíveis via API direta (fora da UI), mesmo escopada
-- por favorecido_id. Por isso, de novo, função SECURITY DEFINER só com os
-- campos seguros — nenhuma política de RLS adicionada em `lancamentos`.
--
-- Fiscal (emissão de NFe/DANFE) ainda é placeholder no sistema — não existe
-- NF-e emitida de verdade ainda. O que existe é chave_acesso_nfe/
-- numero_documento vindos do import de XML já usado no Borderô — exponho
-- isso como referência, mas não prometo download de DANFE (não há PDF
-- armazenado).
-- ============================================================================

create or replace function portal_meus_titulos()
returns table(
  id uuid,
  numero_documento text,
  descricao text,
  data_emissao date,
  data_vencimento date,
  data_pagamento date,
  valor numeric,
  status status_lancamento,
  chave_acesso_nfe text,
  data_prorrogacao_vencimento date,
  motivo_prorrogacao text
)
language sql
stable
security definer
as $$
  select l.id, l.numero_documento, l.descricao, l.data_emissao, l.data_vencimento,
         l.data_pagamento, l.valor, l.status, l.chave_acesso_nfe,
         l.data_prorrogacao_vencimento, l.motivo_prorrogacao
  from lancamentos l
  where l.favorecido_id = auth_portal_favorecido_id()
  order by l.data_vencimento desc nulls last
$$;
