// Spider Buddy, in the page. While the app is climbing this page (and only
// then) it says how far the page has scrolled — and which parts of it
// scroll on their own, and which stay put — and when it has changed, so
// the app looks at it again. Where things are, never what they are: no
// text, no addresses, nothing typed.
(() => {
  if (window.top !== window) return;

  let port = null;
  let on = false;
  let observer = null;
  let changedAt = 0;
  let changeTimer = null;
  let layoutTimer = null;
  let scrollFrame = 0;
  const dirty = new Set();
  // Scrolling elements, by the number the app knows them by (0 is the page).
  const ids = new WeakMap();
  const byId = new Map();
  let nextId = 1;

  function connect() {
    try {
      port = chrome.runtime.connect({ name: "page" });
    } catch (e) {
      port = null; // the extension has gone (reloaded, removed)
      return;
    }
    port.onMessage.addListener((m) => {
      if (m && m.type === "measure") setOn(!!m.on);
    });
    port.onDisconnect.addListener(() => {
      port = null;
      setOn(false);
      // The go-between sleeps now and then; call it back up.
      setTimeout(() => { if (!port && chrome.runtime && chrome.runtime.id) connect(); }, 2000);
    });
  }

  function post(m) {
    if (!port) return;
    try { port.postMessage(m); } catch (e) {}
  }

  function setOn(v) {
    if (v === on) return;
    on = v;
    if (on) {
      window.addEventListener("scroll", onScroll, { capture: true, passive: true });
      window.addEventListener("resize", layoutSoon, { passive: true });
      observer = new MutationObserver(changed);
      observer.observe(document.documentElement, {
        childList: true, subtree: true, attributes: true,
        attributeFilter: ["class", "style", "hidden", "open", "aria-expanded", "aria-hidden"],
      });
      layout();
    } else {
      window.removeEventListener("scroll", onScroll, { capture: true });
      window.removeEventListener("resize", layoutSoon);
      if (observer) observer.disconnect();
      observer = null;
      clearTimeout(changeTimer);
      clearTimeout(layoutTimer);
    }
  }

  function idOf(el) {
    if (!el || el === document || el === document.documentElement || el === document.body || el === document.scrollingElement) return 0;
    let id = ids.get(el);
    if (id === undefined) {
      id = nextId++;
      ids.set(el, id);
      byId.set(id, new WeakRef(el));
    }
    return id;
  }

  function offsets(id) {
    if (id === 0) return [Math.round(window.scrollX * 10) / 10, Math.round(window.scrollY * 10) / 10];
    const el = byId.get(id) && byId.get(id).deref();
    return el ? [el.scrollLeft, el.scrollTop] : null;
  }

  // A scroll: which part moved and to where — sent once a frame at most.
  function onScroll(e) {
    const id = idOf(e.target);
    if (id !== 0 && !isKnown(id)) layoutSoon();
    dirty.add(id);
    if (!scrollFrame) scrollFrame = requestAnimationFrame(flushScroll);
  }

  let known = new Set([0]);
  function isKnown(id) { return known.has(id); }

  function flushScroll() {
    scrollFrame = 0;
    const s = [];
    for (const id of dirty) {
      const o = offsets(id);
      if (o) s.push([id, o[0], o[1]]);
    }
    dirty.clear();
    if (s.length) post({ type: "scroll", s, t: performance.now() });
  }

  // Something changed: the app is told (a moment after it settles, and not
  // more than a few times a second), and the scrolling parts are found again.
  function changed() {
    if (changeTimer) return;
    const wait = Math.max(250, 700 - (performance.now() - changedAt));
    changeTimer = setTimeout(() => {
      changeTimer = null;
      changedAt = performance.now();
      post({ type: "changed" });
      layout();
    }, wait);
  }

  function layoutSoon() {
    clearTimeout(layoutTimer);
    layoutTimer = setTimeout(layout, 200);
  }

  const scrolls = (v) => v === "auto" || v === "scroll" || v === "overlay";

  // What scrolls and what stays put, found from a grid of points over the
  // window: only what can be seen counts. Each scrolling part is given
  // with the part it is itself carried by (0 the page, -1 nothing: it is
  // in something that stays put), so a scroll of the page moves what is in
  // a list on it too.
  function layout() {
    if (!on) return;
    const W = window.innerWidth, H = window.innerHeight;
    const scrollers = [[0, -1, 0, 0, W, H, window.scrollX, window.scrollY]];
    const fixed = [];
    known = new Set([0]);
    const style = new Map(), moves = new Map(), inner = new Map();
    const css = (el) => {
      let cs = style.get(el);
      if (!cs) { cs = getComputedStyle(el); style.set(el, cs); }
      return cs;
    };
    const top = (el) => !el || el === document.body || el === document.documentElement;

    // What an element is carried by when something scrolls.
    function carrier(el) {
      if (top(el)) return 0;
      if (moves.has(el)) return moves.get(el);
      const cs = css(el);
      let c;
      if (cs.position === "fixed") {
        c = -1;
        const r = el.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) fixed.push([r.left, r.top, r.width, r.height]);
      } else {
        c = within(el.parentElement);
        if (cs.position === "sticky") {
          const r = el.getBoundingClientRect();
          if (r.width > 0 && r.height > 0) fixed.push([r.left, r.top, r.width, r.height]);
        }
      }
      moves.set(el, c);
      return c;
    }

    // What an element's contents are carried by: itself, if it scrolls.
    function within(el) {
      if (top(el)) return 0;
      if (inner.has(el)) return inner.get(el);
      const cs = css(el);
      let c;
      if ((scrolls(cs.overflowY) && el.scrollHeight > el.clientHeight + 2)
          || (scrolls(cs.overflowX) && el.scrollWidth > el.clientWidth + 2)) {
        c = idOf(el);
        if (!known.has(c)) {
          known.add(c);
          const r = el.getBoundingClientRect();
          scrollers.push([c, carrier(el), r.left + el.clientLeft, r.top + el.clientTop,
                          el.clientWidth, el.clientHeight, el.scrollLeft, el.scrollTop]);
        }
      } else {
        c = carrier(el);
      }
      inner.set(el, c);
      return c;
    }

    const stepX = Math.max(40, W / 32), stepY = Math.max(40, H / 24);
    for (let y = stepY / 2; y < H; y += stepY) {
      for (let x = stepX / 2; x < W; x += stepX) {
        const el = document.elementFromPoint(x, y);
        if (el) within(el);
      }
    }
    post({
      type: "layout",
      view: { w: W, h: H, dpr: window.devicePixelRatio, ow: window.outerWidth, oh: window.outerHeight,
              sx: window.screenX, sy: window.screenY },
      scrollers, fixed,
    });
  }

  connect();
})();
