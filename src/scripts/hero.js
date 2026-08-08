/* =========================================================================
   I Costanti — motore dell'hero
   -------------------------------------------------------------------------
   Sequenza di fotogrammi su canvas, scrubbata dallo scroll.

   Perche' fotogrammi e non un <video>: scrubbare un H.264 costringe il
   browser a decodificare a ritroso fino al keyframe, e per evitarlo servirebbe
   un file tutto-intra che a 1280px pesa 16-25 MB. La sequenza a q0.42 pesa
   6.5 MB, non ha decodifica a ritroso, e su iOS non dipende da
   `video.currentTime`, che li' e' inaffidabile. In piu' il taglio verticale
   per il mobile si genera in fase di estrazione invece che rattoppato con
   object-position.

   Nessuna dipendenza. GSAP e Lenis entrano nelle sezioni di contenuto.
   ========================================================================= */

/* --- Soglie temporali ----------------------------------------------------
   Tutte le fasi dell'hero in frazione di avanzamento (0 = inizio, 1 = porta
   attraversata). Si regola il ritmo qui dentro, senza toccare la logica. */
export const SOGLIE = {
  TITOLO_TENUTA:        0.10,  // fin qui il titolo resta pieno
  TITOLO_USCITA:        0.30,  // qui e' sparito: comincia il reveal del casale
  FRASE_ENTRATA:        0.36,  // "Dove il tempo rallenta" entra
  FRASE_PIENA:          0.47,
  FRASE_USCITA:         0.58,
  FRASE_FINE:           0.68,  // da qui in poi nessun testo: resta l'immagine
  SCALA_INIZIO:         0.90,  // ultimo 10%: si attraversa la soglia
  APERTURA_INIZIO:      0.94,  // il varco si allarga e si mangia le ante
  CANVAS_USCITA:        0.985, // il canvas si spegne sotto la maschera ormai piena
  FINE:                 1.00,
};

export const PARAMETRI = {
  TITOLO_PARALLASSE_PX: -90,   // negativo = il titolo sale
  FRASE_PARALLASSE_PX:  -34,
  CANVAS_SCALA_MAX:     1.15,
  APERTURA_MAX:         145,   // % del raggio del gradiente: 145 copre gli angoli
  INSEGUIMENTO:         0.16,  // lerp dell'avanzamento: sostituisce lo scrub di GSAP
  DPR_MAX:              1.75,  // il sorgente e' alto 630px: oltre si sprecano pixel
  CANVAS_PX_MAX:        2560,
  FPS_RIPRODUZIONE:     24,
};

/* --- Dove si trova il varco dentro ciascun taglio -------------------------
   Misurato sull'ultimo frame, non stimato: la fessura fra le ante occupa le
   colonne 607..849 di 1470 (centro 49.52%), il bagliore in fondo al corridoio
   sta al 36.33% dell'altezza. Il taglio verticale e' gia' ricentrato in fase
   di estrazione, quindi li' il varco cade esatto a meta'. */
const VARCO = {
  land: { u: 0.4952, v: 0.3633, dir: 'land' },
  port: { u: 0.5000, v: 0.3633, dir: 'port' },
};

const TOTALE_FRAME = 120;
const PASSO_PRIMA_MANO = 4;   // 30 frame ~1.6 MB: l'hero e' gia' scrubbabile

/* --- Utilita' ----------------------------------------------------------- */
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const norma = (v, a, b) => clamp((v - a) / (b - a));
const lisci = (t) => t * t * (3 - 2 * t);          // smoothstep
const tra = (a, b, t) => a + (b - a) * t;

export function inizializzaHero(radice) {
  const pin = radice.querySelector('.hero__pin');
  const canvas = radice.querySelector('.hero__canvas');
  const poster = radice.querySelector('.hero__poster');
  const scorri = radice.querySelector('.hero__scorri');
  const ctx = canvas?.getContext('2d', { alpha: false });
  if (!pin || !canvas || !ctx) return;

  const base = radice.dataset.frames || '/hero';
  const riduzione = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const tocco = !matchMedia('(hover: hover) and (pointer: fine)').matches;

  /* statico      -> un fotogramma fermo, nessun movimento
     riproduzione -> la sequenza scorre una volta sola all'ingresso (mobile)
     scrub        -> hero pinnato, guidato dallo scroll (desktop)            */
  const modalita = riduzione ? 'statico' : tocco ? 'riproduzione' : 'scrub';
  radice.dataset.modalita = modalita;

  let taglio = scegliTaglio();
  const frame = new Array(TOTALE_FRAME);
  let pronti = 0;
  let ultimoIndice = -1;
  let geometria = null;

  let avanzamentoTarget = 0;
  let avanzamentoReso = 0;
  let rafId = 0;
  let scorriNascosto = false;

  function scegliTaglio() {
    return innerWidth / innerHeight < 1.05 ? VARCO.port : VARCO.land;
  }

  /* --- Caricamento progressivo ------------------------------------------
     Prima una mano rada (1 frame su 4) perche' l'hero diventi usabile
     presto, poi il riempimento. Se non arriva nulla la pagina resta
     scrollabile: non si intrappola mai l'utente in attesa di un asset. */
  function carica(indice) {
    return new Promise((risolvi) => {
      if (frame[indice]) return risolvi();
      const img = new Image();
      img.decoding = 'async';
      img.onload = () => { frame[indice] = img; pronti++; risolvi(); };
      img.onerror = () => risolvi();
      img.src = `${base}/${taglio.dir}/f_${String(indice).padStart(3, '0')}.jpg`;
    });
  }

  async function caricaTutto() {
    const rada = [];
    for (let i = 0; i < TOTALE_FRAME; i += PASSO_PRIMA_MANO) rada.push(i);
    if (!rada.includes(TOTALE_FRAME - 1)) rada.push(TOTALE_FRAME - 1);
    await Promise.all(rada.map(carica));

    avvia();

    const resto = [];
    for (let i = 0; i < TOTALE_FRAME; i++) if (!frame[i]) resto.push(i);
    for (const i of resto) await carica(i);   // in coda, senza saturare la rete
  }

  /* Il fotogramma disponibile piu' vicino, finche' la seconda mano non arriva */
  function piuVicino(indice) {
    if (frame[indice]) return frame[indice];
    for (let d = 1; d < TOTALE_FRAME; d++) {
      if (frame[indice - d]) return frame[indice - d];
      if (frame[indice + d]) return frame[indice + d];
    }
    return null;
  }

  /* --- Disegno ----------------------------------------------------------- */
  function ridimensiona() {
    const r = pin.getBoundingClientRect();
    const dpr = Math.min(devicePixelRatio || 1, PARAMETRI.DPR_MAX);
    const w = Math.min(Math.round(r.width * dpr), PARAMETRI.CANVAS_PX_MAX);
    const h = Math.round(w * (r.height / r.width));
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
      ultimoIndice = -1;   // forza il ridisegno
    }
    const nuovo = scegliTaglio();
    if (nuovo !== taglio) {
      taglio = nuovo;
      frame.length = 0;
      frame.length = TOTALE_FRAME;
      pronti = 0;
      ultimoIndice = -1;
      caricaTutto();
    }
  }

  function disegna(indice) {
    const img = piuVicino(indice);
    if (!img) return;
    const cw = canvas.width, ch = canvas.height;
    const s = Math.max(cw / img.naturalWidth, ch / img.naturalHeight);
    const w = img.naturalWidth * s, h = img.naturalHeight * s;
    const x = (cw - w) / 2, y = (ch - h) / 2;
    ctx.drawImage(img, x, y, w, h);

    /* La posizione del varco nel viewport dipende dal crop `cover`, che
       cambia a ogni breakpoint. Ricalcolata qui, l'ancora della maschera e
       dell'origine dello scale restano agganciate al pixel giusto. */
    const nuova = `${((x + taglio.u * w) / cw * 100).toFixed(2)}%|${((y + taglio.v * h) / ch * 100).toFixed(2)}%`;
    if (nuova !== geometria) {
      geometria = nuova;
      const [lx, ly] = nuova.split('|');
      /* Sulla radice del documento, non sull'hero: la stessa origine luminosa
         deve valere per ogni sezione, altrimenti il bagliore si sposta di
         qualche pixel nel passaggio e la giunzione si vede. */
      const doc = document.documentElement.style;
      doc.setProperty('--luce-x', lx);
      doc.setProperty('--luce-y', ly);
    }
    if (poster && poster.style.opacity !== '0') poster.style.opacity = '0';
  }

  /* --- Stato del testo e della transizione, dato l'avanzamento ------------ */
  function applica(p) {
    const s = radice.style;

    // Titolo: parallasse verso l'alto, poi dissolvenza
    const uscita = norma(p, SOGLIE.TITOLO_TENUTA, SOGLIE.TITOLO_USCITA);
    s.setProperty('--titolo-op', String(1 - lisci(uscita)));
    s.setProperty('--titolo-y',
      `${tra(0, PARAMETRI.TITOLO_PARALLASSE_PX, lisci(norma(p, 0, SOGLIE.TITOLO_USCITA)))}px`);

    // Seconda riga: entra, tiene, esce
    const entra = lisci(norma(p, SOGLIE.FRASE_ENTRATA, SOGLIE.FRASE_PIENA));
    const esce  = lisci(norma(p, SOGLIE.FRASE_USCITA, SOGLIE.FRASE_FINE));
    s.setProperty('--frase-op', String(entra * (1 - esce)));

    // Ultimo 10%: si attraversa la soglia, ancorati al varco
    const avvicina = lisci(norma(p, SOGLIE.SCALA_INIZIO, SOGLIE.FINE));
    s.setProperty('--canvas-scala', String(tra(1, PARAMETRI.CANVAS_SCALA_MAX, avvicina)));

    // Il varco si allarga e diventa la pagina
    const apre = lisci(norma(p, SOGLIE.APERTURA_INIZIO, SOGLIE.FINE));
    s.setProperty('--apertura', String(apre * PARAMETRI.APERTURA_MAX));

    // Il canvas si spegne quando la maschera lo copre gia' del tutto
    s.setProperty('--canvas-op', String(1 - norma(p, SOGLIE.CANVAS_USCITA, SOGLIE.FINE)));

    if (!scorriNascosto && p > 0.015) {
      scorriNascosto = true;
      s.setProperty('--scorri-op', '0');
      scorri?.setAttribute('aria-hidden', 'true');
    }
  }

  /* --- Modalita' scrub --------------------------------------------------- */
  function avanzamentoDaScroll() {
    const r = radice.getBoundingClientRect();
    const corsa = radice.offsetHeight - innerHeight;
    return corsa > 0 ? clamp(-r.top / corsa) : 0;
  }

  function ciclo() {
    rafId = 0;
    const delta = avanzamentoTarget - avanzamentoReso;
    // Insegue con un lerp leggero: nasconde le micro-esitazioni di decodifica.
    // Sotto il mezzo fotogramma di distanza si aggancia, cosi' la fine
    // dell'hero non resta mai "quasi" chiusa.
    avanzamentoReso = Math.abs(delta) < 0.0015
      ? avanzamentoTarget
      : avanzamentoReso + delta * PARAMETRI.INSEGUIMENTO;

    const indice = Math.round(avanzamentoReso * (TOTALE_FRAME - 1));
    if (indice !== ultimoIndice) { ultimoIndice = indice; disegna(indice); }
    applica(avanzamentoReso);

    if (avanzamentoReso !== avanzamentoTarget) rafId = requestAnimationFrame(ciclo);
  }

  /* Ogni evento di scroll ripianifica il fotogramma invece di affidarsi a un
     flag "sto animando": se un rAF viene scartato — succede quando la scheda
     non e' in primo piano — il ciclo non resta incastrato spento. */
  function sveglia() {
    avanzamentoTarget = avanzamentoDaScroll();
    if (rafId) cancelAnimationFrame(rafId);
    rafId = requestAnimationFrame(ciclo);
  }

  /* --- Modalita' riproduzione (mobile): una passata sola ------------------ */
  function riproduci() {
    const durata = TOTALE_FRAME / PARAMETRI.FPS_RIPRODUZIONE * 1000;
    const inizio = performance.now();
    const passo = (ora) => {
      const p = clamp((ora - inizio) / durata);
      const indice = Math.round(p * (TOTALE_FRAME - 1));
      if (indice !== ultimoIndice) { ultimoIndice = indice; disegna(indice); }
      // Il testo segue la stessa linea temporale, ma senza rubare lo scroll.
      applica(p * SOGLIE.FRASE_FINE);
      if (p < 1) requestAnimationFrame(passo);
    };
    requestAnimationFrame(passo);
  }

  function avvia() {
    ridimensiona();
    if (modalita === 'scrub') {
      sveglia();
      addEventListener('scroll', sveglia, { passive: true });
    } else if (modalita === 'riproduzione') {
      disegna(0);
      const oss = new IntersectionObserver((voci) => {
        if (voci.some((v) => v.isIntersecting)) { oss.disconnect(); riproduci(); }
      }, { threshold: 0.35 });
      oss.observe(radice);
    } else {
      disegna(0);
      applica(0);
    }
  }

  addEventListener('resize', () => {
    ridimensiona();
    if (modalita === 'scrub') sveglia();
    else disegna(Math.max(ultimoIndice, 0));
  }, { passive: true });

  caricaTutto();
}

/* --- Emersione dei contenuti oltre la soglia ------------------------------
   Gli occhi che si abituano alla penombra. Nessuna attesa: l'osservatore
   scatta prima che l'elemento sia al centro, cosi' il testo e' gia' li'
   quando lo sguardo ci arriva. */
export function inizializzaEmersione(radice = document) {
  const elementi = radice.querySelectorAll('.emergi');
  if (!elementi.length) return;
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
    elementi.forEach((e) => e.classList.add('is-visibile'));
    return;
  }
  const oss = new IntersectionObserver((voci) => {
    for (const v of voci) {
      if (v.isIntersecting) { v.target.classList.add('is-visibile'); oss.unobserve(v.target); }
    }
  }, { rootMargin: '0px 0px -12% 0px', threshold: 0.01 });
  elementi.forEach((e) => oss.observe(e));
}
