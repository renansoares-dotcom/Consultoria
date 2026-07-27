// ============================================================================
// Editor de Arte — módulo compartilhado entre o Portal do Cliente e a tela
// interna de Pré-impressão. Usa Fabric.js (carregado via <script> na página
// que importa este módulo, precisa estar disponível como window.fabric
// antes de chamar criarEditorArte).
//
// Slice A (27/07/2026): só imagem (JPG/PNG). PDF fica pro Slice B — editar
// PDF exige renderizar a página num canvas primeiro (pdf.js), é uma peça
// separada.
// ============================================================================

const CORES = ['#e11d48', '#f59e0b', '#16a34a', '#2563eb', '#7c3aed', '#0f172a', '#ffffff'];

export function criarEditorArte({ containerId, imagemUrl }) {
  const container = document.getElementById(containerId);
  if (!window.fabric) throw new Error('Fabric.js não carregado — inclua o script antes de iniciar o editor.');

  container.innerHTML = `
    <div style="display:flex; gap:16px; flex-wrap:wrap;">
      <div style="flex:1; min-width:0;">
        <div id="ea-toolbar" style="display:flex; flex-wrap:wrap; gap:6px; margin-bottom:10px; padding:10px; background:var(--paper-raised); border-radius:var(--radius-sm); border:1px solid var(--border-soft);">
          <button class="btn ghost ea-ferramenta" data-ferramenta="selecionar" title="Selecionar"><i data-lucide="mouse-pointer-2"></i></button>
          <button class="btn ghost ea-ferramenta" data-ferramenta="lapis" title="Desenho livre"><i data-lucide="pencil"></i></button>
          <button class="btn ghost ea-ferramenta" data-ferramenta="linha" title="Linha"><i data-lucide="minus"></i></button>
          <button class="btn ghost ea-ferramenta" data-ferramenta="seta" title="Seta"><i data-lucide="move-up-right"></i></button>
          <button class="btn ghost ea-ferramenta" data-ferramenta="retangulo" title="Retângulo"><i data-lucide="square"></i></button>
          <button class="btn ghost ea-ferramenta" data-ferramenta="circulo" title="Círculo"><i data-lucide="circle"></i></button>
          <button class="btn ghost ea-ferramenta" data-ferramenta="texto" title="Texto"><i data-lucide="type"></i></button>
          <span style="width:1px; background:var(--border-soft); margin:0 4px;"></span>
          <button class="btn ghost" id="ea-desfazer" title="Desfazer"><i data-lucide="undo-2"></i></button>
          <button class="btn ghost" id="ea-refazer" title="Refazer"><i data-lucide="redo-2"></i></button>
          <button class="btn ghost" id="ea-limpar" title="Limpar marcações"><i data-lucide="eraser"></i></button>
          <span style="width:1px; background:var(--border-soft); margin:0 4px;"></span>
          <button class="btn ghost ea-ferramenta" data-ferramenta="corte" title="Cortar"><i data-lucide="crop"></i></button>
          <button class="btn ghost" id="ea-girar-esq" title="Girar 90° à esquerda"><i data-lucide="rotate-ccw"></i></button>
          <button class="btn ghost" id="ea-girar-dir" title="Girar 90° à direita"><i data-lucide="rotate-cw"></i></button>
        </div>
        <div id="ea-corte-acoes" style="display:none; margin-bottom:10px; gap:8px;">
          <button class="btn primary" id="ea-aplicar-corte">Aplicar Corte</button>
          <button class="btn ghost" id="ea-cancelar-corte">Cancelar Corte</button>
        </div>
        <div style="border:1px solid var(--border-soft); border-radius:var(--radius-sm); overflow:auto; background:#33383f; display:flex; align-items:center; justify-content:center; padding:12px;">
          <canvas id="ea-canvas"></canvas>
        </div>
      </div>
      <div style="width:140px; flex-shrink:0;">
        <div class="field-label" style="margin-bottom:6px;">Cor</div>
        <div id="ea-cores" style="display:grid; grid-template-columns:repeat(4,1fr); gap:6px; margin-bottom:14px;">
          ${CORES.map((c, i) => `<button class="ea-cor" data-cor="${c}" style="width:26px; height:26px; border-radius:50%; border:2px solid ${i===0 ? 'var(--accent)' : 'var(--border-soft)'}; background:${c}; cursor:pointer;"></button>`).join('')}
        </div>
        <div class="field-label" style="margin-bottom:6px;">Espessura</div>
        <input type="range" id="ea-espessura" min="1" max="20" value="4" style="width:100%; margin-bottom:14px;">
      </div>
    </div>`;
  if (window.lucide) lucide.createIcons();

  const canvasEl = document.getElementById('ea-canvas');
  const canvas = new fabric.Canvas(canvasEl, { backgroundColor: '#fff' });

  let ferramenta = 'selecionar';
  let corAtual = CORES[0];
  let espessuraAtual = 4;
  let desenhando = false;
  let formaAtual = null;
  let pontoInicial = null;
  let retanguloCorte = null;

  function ajustarBotoesFerramenta() {
    document.querySelectorAll('.ea-ferramenta').forEach(b => b.classList.toggle('primary', b.dataset.ferramenta === ferramenta));
    canvas.isDrawingMode = ferramenta === 'lapis';
    if (canvas.isDrawingMode) {
      canvas.freeDrawingBrush.color = corAtual;
      canvas.freeDrawingBrush.width = espessuraAtual;
    }
    canvas.selection = ferramenta === 'selecionar';
    canvas.forEachObject(o => { if (o !== retanguloCorte) o.selectable = ferramenta === 'selecionar'; });

    const emCorte = ferramenta === 'corte';
    document.getElementById('ea-corte-acoes').style.display = emCorte ? 'flex' : 'none';
    if (emCorte && !retanguloCorte) {
      const w = canvas.getWidth(), h = canvas.getHeight();
      retanguloCorte = new fabric.Rect({
        left: w * 0.15, top: h * 0.15, width: w * 0.7, height: h * 0.7,
        fill: 'rgba(37,99,235,0.15)', stroke: '#2563eb', strokeDashArray: [6, 4], strokeWidth: 2,
        cornerColor: '#2563eb', transparentCorners: false,
      });
      canvas.add(retanguloCorte);
      canvas.setActiveObject(retanguloCorte);
    }
    if (!emCorte && retanguloCorte) { canvas.remove(retanguloCorte); retanguloCorte = null; }
    canvas.requestRenderAll();
  }

  document.querySelectorAll('.ea-ferramenta').forEach(btn => {
    btn.addEventListener('click', () => { ferramenta = btn.dataset.ferramenta; ajustarBotoesFerramenta(); });
  });

  document.querySelectorAll('.ea-cor').forEach(btn => {
    btn.addEventListener('click', () => {
      corAtual = btn.dataset.cor;
      document.querySelectorAll('.ea-cor').forEach(b => b.style.borderColor = 'var(--border-soft)');
      btn.style.borderColor = 'var(--accent)';
      if (canvas.isDrawingMode) canvas.freeDrawingBrush.color = corAtual;
    });
  });
  document.getElementById('ea-espessura').addEventListener('input', (e) => {
    espessuraAtual = Number(e.target.value);
    if (canvas.isDrawingMode) canvas.freeDrawingBrush.width = espessuraAtual;
  });

  // ---------- Desenho de formas (linha, seta, retângulo, círculo) ----------
  canvas.on('mouse:down', (opt) => {
    if (!['linha', 'seta', 'retangulo', 'circulo'].includes(ferramenta)) return;
    desenhando = true;
    const p = canvas.getPointer(opt.e);
    pontoInicial = p;

    if (ferramenta === 'retangulo') {
      formaAtual = new fabric.Rect({ left: p.x, top: p.y, width: 1, height: 1, fill: 'transparent', stroke: corAtual, strokeWidth: espessuraAtual, selectable: false });
    } else if (ferramenta === 'circulo') {
      formaAtual = new fabric.Ellipse({ left: p.x, top: p.y, rx: 1, ry: 1, fill: 'transparent', stroke: corAtual, strokeWidth: espessuraAtual, selectable: false });
    } else {
      formaAtual = new fabric.Line([p.x, p.y, p.x, p.y], { stroke: corAtual, strokeWidth: espessuraAtual, selectable: false });
    }
    canvas.add(formaAtual);
  });

  canvas.on('mouse:move', (opt) => {
    if (!desenhando || !formaAtual) return;
    const p = canvas.getPointer(opt.e);
    if (ferramenta === 'retangulo') {
      formaAtual.set({ width: Math.abs(p.x - pontoInicial.x), height: Math.abs(p.y - pontoInicial.y), left: Math.min(p.x, pontoInicial.x), top: Math.min(p.y, pontoInicial.y) });
    } else if (ferramenta === 'circulo') {
      formaAtual.set({ rx: Math.abs(p.x - pontoInicial.x) / 2, ry: Math.abs(p.y - pontoInicial.y) / 2, left: Math.min(p.x, pontoInicial.x), top: Math.min(p.y, pontoInicial.y) });
    } else {
      formaAtual.set({ x2: p.x, y2: p.y });
    }
    canvas.requestRenderAll();
  });

  canvas.on('mouse:up', () => {
    if (!desenhando) return;
    desenhando = false;

    if (ferramenta === 'seta' && formaAtual) {
      const { x1, y1, x2, y2 } = formaAtual;
      const angulo = Math.atan2(y2 - y1, x2 - x1);
      const tamanhoPonta = 10 + espessuraAtual;
      const ponta = new fabric.Triangle({
        left: x2, top: y2, width: tamanhoPonta, height: tamanhoPonta,
        fill: corAtual, angle: (angulo * 180 / Math.PI) + 90, originX: 'center', originY: 'center',
      });
      const grupo = new fabric.Group([formaAtual, ponta], { selectable: ferramenta === 'selecionar' });
      canvas.remove(formaAtual);
      canvas.add(grupo);
    }

    if (formaAtual) formaAtual.set({ selectable: true });
    formaAtual = null;
    pontoInicial = null;
    canvas.fire('object:modified');
  });

  canvas.on('mouse:down', (opt) => {
    if (ferramenta !== 'texto') return;
    const p = canvas.getPointer(opt.e);
    const texto = new fabric.IText('Texto', { left: p.x, top: p.y, fill: corAtual, fontSize: 20 + espessuraAtual * 2, fontFamily: 'Inter, sans-serif' });
    canvas.add(texto);
    canvas.setActiveObject(texto);
    texto.enterEditing();
    ferramenta = 'selecionar';
    ajustarBotoesFerramenta();
  });

  // ---------- Desfazer / Refazer ----------
  let historico = [];
  let indiceHistorico = -1;
  let restaurando = false;

  function salvarEstado() {
    if (restaurando) return;
    historico = historico.slice(0, indiceHistorico + 1);
    historico.push(JSON.stringify(canvas.toJSON()));
    indiceHistorico = historico.length - 1;
  }
  canvas.on('object:added', salvarEstado);
  canvas.on('object:modified', salvarEstado);
  canvas.on('object:removed', salvarEstado);

  function restaurarEstado(json) {
    restaurando = true;
    canvas.loadFromJSON(json, () => { canvas.requestRenderAll(); restaurando = false; });
  }
  document.getElementById('ea-desfazer').addEventListener('click', () => {
    if (indiceHistorico <= 0) return;
    indiceHistorico--;
    restaurarEstado(historico[indiceHistorico]);
  });
  document.getElementById('ea-refazer').addEventListener('click', () => {
    if (indiceHistorico >= historico.length - 1) return;
    indiceHistorico++;
    restaurarEstado(historico[indiceHistorico]);
  });
  document.getElementById('ea-limpar').addEventListener('click', () => {
    if (!confirm('Apagar todas as marcações (mantém a imagem base)?')) return;
    canvas.getObjects().filter(o => o !== fundoImagem && o !== retanguloCorte).forEach(o => canvas.remove(o));
    salvarEstado();
  });

  // ---------- Corte ----------
  document.getElementById('ea-aplicar-corte').addEventListener('click', () => {
    if (!retanguloCorte) return;
    const rect = retanguloCorte.getBoundingRect();
    canvas.remove(retanguloCorte);
    retanguloCorte = null;

    const dataUrl = canvas.toDataURL({ format: 'png', left: rect.left, top: rect.top, width: rect.width, height: rect.height });
    fabric.Image.fromURL(dataUrl, (img) => {
      canvas.clear();
      canvas.setWidth(rect.width);
      canvas.setHeight(rect.height);
      fundoImagem = img;
      canvas.add(img);
      canvas.centerObject(img);
      img.set({ left: 0, top: 0, selectable: false, evented: false });
      canvas.requestRenderAll();
      salvarEstado();
    });
    ferramenta = 'selecionar';
    ajustarBotoesFerramenta();
  });
  document.getElementById('ea-cancelar-corte').addEventListener('click', () => { ferramenta = 'selecionar'; ajustarBotoesFerramenta(); });

  // ---------- Girar 90° ----------
  function girar(graus) {
    const dataUrl = canvas.toDataURL({ format: 'png' });
    const wAtual = canvas.getWidth(), hAtual = canvas.getHeight();
    const img = new Image();
    img.onload = () => {
      const off = document.createElement('canvas');
      off.width = hAtual; off.height = wAtual;
      const ctx = off.getContext('2d');
      ctx.translate(off.width / 2, off.height / 2);
      ctx.rotate(graus * Math.PI / 180);
      ctx.drawImage(img, -wAtual / 2, -hAtual / 2);
      fabric.Image.fromURL(off.toDataURL('image/png'), (novaImg) => {
        canvas.clear();
        canvas.setWidth(hAtual);
        canvas.setHeight(wAtual);
        fundoImagem = novaImg;
        novaImg.set({ left: 0, top: 0, selectable: false, evented: false });
        canvas.add(novaImg);
        canvas.requestRenderAll();
        salvarEstado();
      });
    };
    img.src = dataUrl;
  }
  document.getElementById('ea-girar-esq').addEventListener('click', () => girar(-90));
  document.getElementById('ea-girar-dir').addEventListener('click', () => girar(90));

  // ---------- Carrega a imagem inicial ----------
  let fundoImagem = null;
  const carregado = new Promise((resolve) => {
    fabric.Image.fromURL(imagemUrl, (img) => {
      const maxLargura = Math.min(900, window.innerWidth - 340);
      const escala = Math.min(1, maxLargura / img.width);
      canvas.setWidth(img.width * escala);
      canvas.setHeight(img.height * escala);
      img.scale(escala);
      img.set({ left: 0, top: 0, selectable: false, evented: false });
      fundoImagem = img;
      canvas.add(img);
      canvas.requestRenderAll();
      salvarEstado();
      resolve();
    }, { crossOrigin: 'anonymous' });
  });

  ajustarBotoesFerramenta();

  return {
    pronto: carregado,
    async exportarPNG() {
      const dataUrl = canvas.toDataURL({ format: 'png' });
      const resposta = await fetch(dataUrl);
      return await resposta.blob();
    },
  };
}
