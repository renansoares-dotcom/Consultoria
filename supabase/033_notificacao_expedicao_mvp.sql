-- ============================================================================
-- MIGRAÇÃO 033 — Notificação de Expedição (MVP): montagem do conteúdo
--
-- Decisão registrada no Product Decisions Log em 25/07/2026: expande
-- expedicoes com detalhes físicos do envio (volumes, pesos, veículo,
-- rastreio, previsão), e notas_fiscais com upload de DANFE/XML. Sem envio
-- automático (e-mail/SMS) ainda — isso depende de decisão de infraestrutura
-- de provedor de e-mail, registrada em Ideias Futuras.
-- ============================================================================

alter table expedicoes
  add column numero_volumes  integer,
  add column peso_liquido    numeric(12,3),
  add column peso_bruto      numeric(12,3),
  add column veiculo_placa   text,
  add column codigo_rastreio text,
  add column previsao_entrega date;

alter table notas_fiscais
  add column danfe_path text,   -- caminho no bucket 'anexos'
  add column xml_path   text;

-- ----------------------------------------------------------------------------
-- Monta o conteúdo completo da notificação: pedido, cliente, NF-e vinculada
-- (se houver) e detalhes físicos do envio.
-- ----------------------------------------------------------------------------
create or replace view vw_notificacao_expedicao as
select
  e.id as expedicao_id,
  e.tenant_id,
  e.numero_expedicao,
  e.data_expedicao,
  e.transportadora,
  e.veiculo_placa,
  e.codigo_rastreio,
  e.previsao_entrega,
  e.numero_volumes,
  e.peso_liquido,
  e.peso_bruto,
  pv.id as pedido_venda_id,
  pv.numero_pedido,
  pv.cliente_id,
  fv.nome as cliente_nome,
  fv.email as cliente_email,
  nf.id as nota_fiscal_id,
  nf.numero as nf_numero,
  nf.serie as nf_serie,
  nf.chave_acesso as nf_chave_acesso,
  nf.danfe_path,
  nf.xml_path
from expedicoes e
join pedidos_venda pv on pv.id = e.pedido_venda_id
left join favorecidos fv on fv.id = pv.cliente_id
left join notas_fiscais nf on nf.expedicao_id = e.id
where e.status = 'expedido';

alter view vw_notificacao_expedicao set (security_invoker = on);
