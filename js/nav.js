// ============================================================================
// Navegação do menu superior em cascata — compartilhado por todas as páginas.
// Antes dependia só de :hover (CSS), o que travava/prendia o painel aberto em
// cliques, telas touch e movimentos diagonais do mouse. Agora é controlado
// por classe .open via JS: abre no clique, fecha ao clicar fora, fecha com
// Esc, e fecha o painel anterior ao abrir outro.
// ============================================================================
import { initTheme } from './theme.js';

export function initNav() {
  initTheme();

  const nav = document.querySelector('.nav-cascade');
  const topbar = document.querySelector('.topbar');
  const itens = document.querySelectorAll('.nav-item');

  // Botão hambúrguer (mobile) — injetado via JS, não exige editar cada página
  if (nav && topbar && !topbar.querySelector('.menu-toggle')) {
    const btn = document.createElement('button');
    btn.className = 'menu-toggle';
    btn.setAttribute('aria-label', 'Abrir menu');
    btn.innerHTML = '☰';
    topbar.insertBefore(btn, nav);
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      nav.classList.toggle('mobile-open');
      itens.forEach(i => i.classList.remove('open'));
    });
  }

  itens.forEach(item => {
    const botao = item.querySelector(':scope > button');
    if (!botao) return; // item sem submenu (ex: link "Início")

    botao.addEventListener('click', (e) => {
      e.stopPropagation();
      const jaAberto = item.classList.contains('open');
      itens.forEach(i => i.classList.remove('open'));
      if (!jaAberto) item.classList.add('open');
    });
  });

  document.addEventListener('click', (e) => {
    itens.forEach(i => i.classList.remove('open'));
    if (nav && !nav.contains(e.target) && !e.target.closest('.menu-toggle')) {
      nav.classList.remove('mobile-open');
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      itens.forEach(i => i.classList.remove('open'));
      nav?.classList.remove('mobile-open');
    }
  });
}
