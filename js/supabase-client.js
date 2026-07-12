// ============================================================================
// Cliente Supabase — importado por todas as páginas via <script type="module">
// Preencha SUPABASE_URL e SUPABASE_ANON_KEY com os dados do seu projeto
// (Supabase Dashboard > Project Settings > API). A anon key é pública e
// segura de expor no front-end: a segurança real vem do RLS (schema.sql).
// ============================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = 'https://SEU-PROJETO.supabase.co';
const SUPABASE_ANON_KEY = 'SUA-ANON-KEY-AQUI';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Garante sessão ativa ou redireciona para login em páginas internas
export async function exigirSessao() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    window.location.href = '/index.html';
    return null;
  }
  return session;
}

// Retorna o registro de negócio do usuário logado (tabela usuarios)
export async function usuarioAtual() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabase
    .from('usuarios')
    .select('*, perfis_acesso(nome, permissoes)')
    .eq('id', user.id)
    .single();
  if (error) { console.error(error); return null; }
  return data;
}
