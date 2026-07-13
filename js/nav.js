// ============================================================================
// Navegação do menu superior em cascata — compartilhado por todas as páginas.
// Antes dependia só de :hover (CSS), o que travava/prendia o painel aberto em
// cliques, telas touch e movimentos diagonais do mouse. Agora é controlado
// por classe .open via JS: abre no clique, fecha ao clicar fora, fecha com
// Esc, e fecha o painel anterior ao abrir outro.
// ============================================================================
export function initNav() {
  const itens = document.querySelectorAll('.nav-item');

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

  document.addEventListener('click', () => {
    itens.forEach(i => i.classList.remove('open'));
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') itens.forEach(i => i.classList.remove('open'));
  });
}
