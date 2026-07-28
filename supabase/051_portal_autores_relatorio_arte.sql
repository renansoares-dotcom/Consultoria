-- ============================================================================
-- Migration: 051_portal_autores_relatorio_arte
-- Data: 27/07/2026
--
-- O relatório em PDF de um projeto de arte precisa mostrar QUEM enviou cada
-- versão e QUEM decidiu cada aprovação. Do lado do portal, isso inclui
-- possivelmente nomes de colaboradores internos (staff) — e o portal não
-- tem (e não deve ter) acesso de leitura à tabela `usuarios`.
--
-- Mesmo padrão de portal_meus_produtos()/portal_meus_titulos(): função
-- SECURITY DEFINER devolvendo só (id, nome, tipo), nunca uma política de
-- RLS em `usuarios`. Escopo ainda mais restrito que os anteriores: só
-- devolve nomes de gente que efetivamente enviou/decidiu algo NUM PROJETO
-- ESPECÍFICO que já pertence ao cliente autenticado — não é um lookup
-- genérico de usuário por id, evita qualquer enumeração.
-- ============================================================================

create or replace function portal_autores_projeto_arte(p_projeto_id uuid)
returns table(usuario_id uuid, nome text)
language sql
stable
security definer
as $$
  select u.id, u.nome
  from usuarios u
  where u.id in (
    select enviado_por from arte_versoes where projeto_id = p_projeto_id and enviado_por is not null
    union
    select ap.decidido_por from arte_aprovacoes ap
      join arte_versoes av on av.id = ap.versao_id
      where av.projeto_id = p_projeto_id and ap.decidido_por is not null
  )
  and exists (select 1 from projetos_arte pa where pa.id = p_projeto_id and pa.cliente_id = auth_portal_favorecido_id())

  union all

  select up.id, up.nome
  from usuarios_portal up
  where up.id in (
    select enviado_por_portal from arte_versoes where projeto_id = p_projeto_id and enviado_por_portal is not null
    union
    select ap.decidido_por_portal from arte_aprovacoes ap
      join arte_versoes av on av.id = ap.versao_id
      where av.projeto_id = p_projeto_id and ap.decidido_por_portal is not null
  )
  and exists (select 1 from projetos_arte pa where pa.id = p_projeto_id and pa.cliente_id = auth_portal_favorecido_id())
$$;
