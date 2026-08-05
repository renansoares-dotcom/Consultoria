(() => {
  'use strict';

  /* ---------- Ano no rodapé ---------- */
  const yearEl = document.getElementById('year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  /* ---------- Nav: estado de scroll (fundo com blur) ---------- */
  const nav = document.getElementById('nav');
  function atualizarEstadoNav() {
    if (window.scrollY > 12) nav.classList.add('is-scrolled');
    else nav.classList.remove('is-scrolled');
  }
  atualizarEstadoNav();
  window.addEventListener('scroll', atualizarEstadoNav, { passive: true });

  /* ---------- Menu mobile ---------- */
  const burger = document.getElementById('navBurger');
  const navLinksWrap = document.querySelector('.nav-links');
  if (burger && navLinksWrap) {
    burger.addEventListener('click', () => {
      const aberto = navLinksWrap.classList.toggle('is-open');
      burger.setAttribute('aria-expanded', String(aberto));
    });
    // fecha o menu ao clicar num link (mobile)
    navLinksWrap.querySelectorAll('a').forEach((a) => {
      a.addEventListener('click', () => {
        navLinksWrap.classList.remove('is-open');
        burger.setAttribute('aria-expanded', 'false');
      });
    });
  }

  /* ---------- Botão de rolagem do hero ---------- */
  const scrollCue = document.getElementById('scrollCue');
  if (scrollCue) {
    scrollCue.addEventListener('click', () => {
      const proximaSecao = document.getElementById('filosofia');
      if (proximaSecao) proximaSecao.scrollIntoView({ behavior: 'smooth' });
    });
  }

  /* ---------- Revelação ao rolar (IntersectionObserver) ----------
     Marca as seções/blocos com [data-reveal] pra animar de forma
     discreta quando entram na tela — não repete a animação, então
     não pisca de novo se o usuário rolar pra cima e pra baixo. */
  const alvosRevelacao = document.querySelectorAll(
    '.philosophy-grid, .ecosystem-diagram, .product-feature, .product-next-grid, ' +
    '.solutions-grid, .engineering-grid, .diff-grid, .process-item, .stack-board, .cta-final-inner'
  );
  alvosRevelacao.forEach((el) => el.setAttribute('data-reveal', ''));

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(
      (entradas) => {
        entradas.forEach((entrada) => {
          if (entrada.isIntersecting) {
            entrada.target.classList.add('is-visible');
            observer.unobserve(entrada.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: '0px 0px -60px 0px' }
    );
    alvosRevelacao.forEach((el) => observer.observe(el));
  } else {
    // sem suporte a IntersectionObserver: mostra tudo direto, sem animação
    alvosRevelacao.forEach((el) => el.classList.add('is-visible'));
  }
})();
