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

  const alvo = document.querySelector('.topbar-right');
  if (!alvo || alvo.querySelector('.theme-toggle')) return; // sem topbar (login) ou botão já existe

  const btn = document.createElement('button');
  btn.className = 'theme-toggle';
  btn.type = 'button';
  btn.setAttribute('aria-label', 'Alternar tema claro/escuro');
  btn.textContent = document.documentElement.getAttribute('data-theme') === 'dark' ? '☀️ Claro' : '🌙 Escuro';
  alvo.insertBefore(btn, alvo.firstChild);

  btn.addEventListener('click', () => {
    const novo = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    salvarTema(novo);
    btn.textContent = novo === 'dark' ? '☀️ Claro' : '🌙 Escuro';
  });
}
