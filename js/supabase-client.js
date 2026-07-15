// ============================================================================
// Cliente Supabase — importado por todas as páginas via <script type="module">
// Preencha SUPABASE_URL e SUPABASE_ANON_KEY com os dados do seu projeto
// (Supabase Dashboard > Project Settings > API). A anon key é pública e
// segura de expor no front-end: a segurança real vem do RLS (schema.sql).
// ============================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = 'https://qandcrcjecawcfsvqfhr.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFhbmRjcmNqZWNhd2Nmc3ZxZmhyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM4ODc5MjYsImV4cCI6MjA5OTQ2MzkyNn0.T8TMWvSkDXc5AidbBpx8KXrrztZl9rv8HvgBKIUQG8U';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Garante sessão ativa ou redireciona para login em páginas internas.
// Usa import.meta.url (a localização real deste arquivo, sempre em /js/)
// pra calcular a raiz do site — funciona não importa a profundidade da
// página que chamou, e não importa se o site está numa subpasta (como
// acontece no GitHub Pages de projeto: usuario.github.io/NomeDoRepo/).
export async function exigirSessao() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    const raizSite = new URL('../', import.meta.url).href;
    window.location.href = raizSite + 'index.html';
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
