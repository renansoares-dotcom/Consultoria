-- ============================================================================
-- MIGRAÇÃO 025b — Requisição de Compra: novo status "atendida"
--
-- Precisa rodar isolada (ALTER TYPE ... ADD VALUE não pode estar na mesma
-- migration que já usa o novo valor — regra já registrada nos Aprendizados
-- Críticos da Documentação Técnica).
--
-- "atendida" marca a requisição que já virou item de um Pedido de Compra
-- (módulo Compras, migração 025) — para não aparecer de novo como pendente.
-- ============================================================================

alter type status_requisicao_compra add value if not exists 'atendida';
