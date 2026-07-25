// ============================================================================
// Tema claro/escuro — chamado por initNav() em toda página autenticada, e
// importado isoladamente em index.html/redefinir-senha.html (que não têm
// topbar) só para respeitar a preferência salva.
// ============================================================================
const CHAVE = 'livrocaixa-tema';

export function temaAtual() {
  const salvo = localStorage.getItem(CHAVE);
  if (salvo) return salvo;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function aplicarTema(tema) {
  document.documentElement.setAttribute('data-theme', tema);
}

export function salvarTema(tema) {
  aplicarTema(tema);
  localStorage.setItem(CHAVE, tema);
}

export function initTheme() {
  aplicarTema(temaAtual());

  // Páginas com sidebar de módulos já têm o controle fixo #theme-toggle-sidebar
  // (ligado separadamente em nav.js) — não duplicar o botão no topbar nesse caso.
  if (document.getElementById('theme-toggle-sidebar')) return;

  const alvo = document.querySelector('.topbar-right');
  if (!alvo || alvo.querySelector('.theme-toggle')) return; // sem topbar (login) ou botão já existe

  const btn = document.createElement('button');
  btn.className = 'theme-toggle';
  btn.type = 'button';
  btn.setAttribute('aria-label', 'Alternar tema claro/escuro');
  btn.innerHTML = document.documentElement.getAttribute('data-theme') === 'dark' ? '<i data-lucide="sun"></i> Claro' : '<i data-lucide="moon"></i> Escuro';
  alvo.insertBefore(btn, alvo.firstChild);
  if (window.lucide) lucide.createIcons();

  btn.addEventListener('click', () => {
    const novo = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    salvarTema(novo);
    btn.innerHTML = novo === 'dark' ? '<i data-lucide="sun"></i> Claro' : '<i data-lucide="moon"></i> Escuro';
    if (window.lucide) lucide.createIcons();
  });
}
