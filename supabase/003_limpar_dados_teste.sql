-- ============================================================================
-- LIMPEZA DE DADOS DE TESTE
-- Apaga lançamentos e todos os cadastros (plano de contas, grupos, contas
-- bancárias, centros de custo, favorecidos, orçamentos) do seu tenant.
-- NÃO apaga: o tenant em si, seu usuário/login, nem os perfis de acesso —
-- assim você continua logando normalmente e recomeça o cadastro do zero.
--
-- Rode no SQL Editor do Supabase.
-- ============================================================================

do $$
declare
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from usuarios where email = 'renansoaresgualberto@gmail.com';

  if v_tenant_id is null then
    raise exception 'Tenant não encontrado para esse e-mail — confira antes de rodar.';
  end if;

  delete from auditoria     where tenant_id = v_tenant_id;
  delete from lancamentos   where tenant_id = v_tenant_id;
  delete from orcamentos    where tenant_id = v_tenant_id;
  delete from plano_contas  where tenant_id = v_tenant_id;
  delete from contas_bancarias where tenant_id = v_tenant_id;
  delete from centros_custo where tenant_id = v_tenant_id;
  delete from favorecidos   where tenant_id = v_tenant_id;
  delete from grupos_empresariais where tenant_id = v_tenant_id;

  raise notice 'Dados de teste apagados para o tenant %', v_tenant_id;
end $$;
