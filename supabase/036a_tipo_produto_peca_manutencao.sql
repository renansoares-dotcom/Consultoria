-- ============================================================================
-- MIGRAÇÃO 036a — Novo tipo de produto: peça de manutenção (MRO)
--
-- Isolada de propósito: ALTER TYPE ... ADD VALUE não pode estar na mesma
-- migration que já usa o novo valor (regra registrada nos Aprendizados
-- Críticos da Documentação Técnica).
-- ============================================================================

alter type tipo_produto add value if not exists 'peca_manutencao';
