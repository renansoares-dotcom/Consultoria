// ============================================================================
// Cliente Supabase do Portal do Cliente — espelha js/supabase-client.js, mas
// lê a identidade de `usuarios_portal`, NUNCA de `usuarios`.
//
// Por quê um arquivo separado: manter os dois caminhos de identidade
// visualmente e estruturalmente distintos no código, do mesmo jeito que são
// distintos no banco (usuarios x usuarios_portal, auth_tenant_id() x
// auth_portal_favorecido_id()). Reduz a chance de alguém colar por engano
// o import de supabase-client.js numa tela do portal no futuro.
// ============================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = 'https://qandcrcjecawcfsvqfhr.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhbmRjcmNqZWNhd2Nmc3ZxZmhyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM4ODc5MjYsImV4cCI6MjA5OTQ2MzkyNn0.T8TMWvSkDXc5AidbBpx8KXrrztZl9rv8HvgBKIUQG8U';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Garante sessão ativa E que essa sessão pertence a um usuário do portal
// (existe em usuarios_portal). Se for uma sessão de colaborador interno que
// caiu aqui por engano, ou não houver sessão, redireciona pro login do
// portal — nunca pro login interno.
export async function exigirSessaoPortal() {
  const { data: { session } } = await supabase.auth.getSession();
  const raizSite = new URL('../', import.meta.url).href;
  if (!session) {
    window.location.href = raizSite + 'portal/login.html';
    return null;
  }
  const usuario = await usuarioPortalAtual();
  if (!usuario) {
    // Sessão válida no Supabase Auth, mas sem registro em usuarios_portal
    // (ex: colaborador interno tentando abrir uma URL do portal). Encerra
    // a sessão pra não deixar estado ambíguo e manda pro login certo.
    await supabase.auth.signOut();
    window.location.href = raizSite + 'portal/login.html?erro=acesso';
    return null;
  }
  return session;
}

// Retorna o registro do usuário do portal logado (tabela usuarios_portal),
// nunca `usuarios`.
export async function usuarioPortalAtual() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabase
    .from('usuarios_portal')
    .select('*, favorecidos(nome)')
    .eq('id', user.id)
    .eq('ativo', true)
    .maybeSingle();
  if (error) { console.error(error); return null; }
  return data;
}
