-- ============================================================================
-- Migration: 048_portal_storage_artes
-- Portal do Cliente — correção: acesso ao Storage pra arquivos de arte
-- Data: 2026-07-27
--
-- BUG REAL encontrado em produção: as políticas de storage.objects do bucket
-- 'anexos' (tenant_le_seus_anexos, tenant_sobe_seus_anexos) exigem
-- auth_tenant_id() = primeiro segmento do caminho. auth_tenant_id() sempre
-- retorna NULL pra sessão do portal (não existe em `usuarios`, por design).
-- Resultado prático: createSignedUrl() falhava silenciosamente pro cliente
-- (por isso a imagem não abria), e o upload de arquivo pelo cliente (Slice
-- 5, migration 047) também falhava no passo de storage.upload() — só a
-- gravação na tabela arte_versoes tinha sido testada, não o storage de
-- verdade. Corrigido e testado os dois juntos agora.
--
-- Escopo restrito: só o padrão de caminho `{tenant}/artes/{projeto_id}/...`
-- — nunca abre o bucket 'anexos' inteiro pro portal (lá também tem FISPQ da
-- Casa de Tintas, anexos de Borderô, etc., que nunca podem ficar
-- acessíveis a um cliente externo).
-- ============================================================================

create policy portal_le_artes_do_proprio_cliente on storage.objects
  for select
  using (
    bucket_id = 'anexos'
    and (storage.foldername(name))[2] = 'artes'
    and exists (
      select 1 from projetos_arte pa
      where pa.id::text = (storage.foldername(name))[3]
        and pa.cliente_id = auth_portal_favorecido_id()
    )
  );

create policy portal_sobe_artes_do_proprio_cliente on storage.objects
  for insert
  with check (
    bucket_id = 'anexos'
    and (storage.foldername(name))[2] = 'artes'
    and exists (
      select 1 from projetos_arte pa
      where pa.id::text = (storage.foldername(name))[3]
        and pa.cliente_id = auth_portal_favorecido_id()
    )
  );
