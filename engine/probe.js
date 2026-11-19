// LawEditor's probe: added to a project's page only when the app shows it in its own frame (the address
// ends in ?inspect; harness/INSPECT.bend, server.bend). The page lives at another address than the app,
// so the app can't read it: this script reads the page's boxes and tells the frame, which draws them.
// It only reads and tells. In the page it changes one thing: the pointer, while a tool that picks is on.
//
// To the frame:  { laweditor: "boxes", boxes, hover, picked, pins }   what to draw (Bend-UI's inspect)
//                { laweditor: "pick", tool, name, text, part, fresh }  a part was clicked with a tool on
// From the frame: { laweditor: "tools", measures, tool }               which tools are on
//                 { laweditor: "pins", do: "keep" | "drop" | "clear" } the comment was sent, given up, or all go
//
// A box has the shape Bend-UI's readBox gives ({ x, y, w, h, pad, margin, rowGap, colGap, kids }), in the
// page's own window measures: the frame's drawing sits exactly over the page.
(() => {
  if (window.parent === window) return;   // only inside a frame
  const S = { measures: false, tool: "", hover: null, picked: null, pins: [], fresh: null };
  const MAX = 1500;   // a page with more parts than this is measured up to here
  const SKIP = new Set(["SCRIPT", "STYLE", "LINK", "META", "HEAD", "TITLE", "NOSCRIPT", "TEMPLATE", "BR"]);
  const tell = (m) => window.parent.postMessage(m, "*");
  const px = (v) => parseFloat(v) || 0;
  const rect = (el) => { const r = el.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; };
  const sides = (c, what) => [px(c[what + "Top"]), px(c[what + "Right"]), px(c[what + "Bottom"]), px(c[what + "Left"])];
  const outer = (el) => { const r = rect(el), [t, e, b, l] = sides(getComputedStyle(el), "margin"); return { x: r.x - l, y: r.y - t, w: r.w + l + e, h: r.h + t + b }; };
  const seen = (r) => r.w > 0 && r.h > 0 && r.x < innerWidth && r.y < innerHeight && r.x + r.w > 0 && r.y + r.h > 0;
  const nameOf = (el) => el.tagName.toLowerCase() + (el.classList[0] ? "." + el.classList[0] : "");

  function box(el) {
    const c = getComputedStyle(el), flow = /flex|grid/.test(c.display), rowGap = flow ? px(c.rowGap) : 0, colGap = flow ? px(c.columnGap) : 0;
    return { ...rect(el), pad: sides(c, "padding"), margin: sides(c, "margin"), rowGap, colGap,
      kids: rowGap || colGap ? [...el.children].filter((k) => k.offsetWidth && k.offsetHeight).map(outer) : [] };
  }
  const plain = (el) => (el && el.isConnected ? rect(el) : null);
  function boxes() {
    if (!S.measures || !document.body) return [];
    const out = [];
    for (const el of [document.body, ...document.body.querySelectorAll("*")]) {
      if (SKIP.has(el.tagName)) continue;
      if (seen(rect(el))) out.push(box(el));
      if (out.length >= MAX) break;
    }
    return out;
  }
  // One part's values, as Bend-UI's facts() shows them.
  function part(el) {
    const c = getComputedStyle(el), r = rect(el), flow = /flex|grid/.test(c.display);
    return { name: nameOf(el), w: r.w, h: r.h, pad: sides(c, "padding"), margin: sides(c, "margin"),
      gap: flow ? px(c.rowGap) || px(c.columnGap) : 0, radius: px(c.borderTopLeftRadius), size: px(c.fontSize), weight: c.fontWeight };
  }

  let due = false;
  function say() {
    if (due) return; due = true;
    requestAnimationFrame(() => {
      due = false;
      const pins = S.pins.map((p, i) => ({ box: plain(p.el), fx: p.fx, fy: p.fy, label: i + 1 })).filter((p) => p.box);
      if (S.fresh && S.fresh.el.isConnected) pins.push({ box: rect(S.fresh.el), fx: S.fresh.fx, fy: S.fresh.fy, label: "+", fresh: true });
      tell({ laweditor: "boxes", boxes: boxes(), hover: S.tool ? plain(S.hover) : null, picked: S.tool === "inspect" ? plain(S.picked) : null, pins });
    });
  }

  // While a tool that picks is on, the pointer reads the page and does nothing else to it.
  const style = document.createElement("style");
  style.textContent = "html.laweditor-picks, html.laweditor-picks * { cursor: crosshair !important; }";
  document.documentElement.append(style);
  const target = (e) => (e.target instanceof Element && !SKIP.has(e.target.tagName) ? e.target : null);
  const hold = (e) => { if (!S.tool) return false; e.preventDefault(); e.stopImmediatePropagation(); return true; };
  for (const kind of ["pointerdown", "pointerup", "mousedown", "mouseup", "dblclick", "contextmenu"]) addEventListener(kind, hold, true);
  addEventListener("pointermove", (e) => { if (!S.tool) return; const el = target(e); if (el !== S.hover) { S.hover = el; say(); } }, true);
  document.documentElement.addEventListener("pointerleave", () => { if (S.hover) { S.hover = null; say(); } });
  addEventListener("click", (e) => {
    if (!hold(e)) return;
    const el = target(e); if (!el) return;
    const r = el.getBoundingClientRect();
    if (S.tool === "inspect") S.picked = el;
    else S.fresh = { el, fx: r.width ? (e.clientX - r.left) / r.width : 0.5, fy: r.height ? (e.clientY - r.top) / r.height : 0.5 };
    tell({ laweditor: "pick", tool: S.tool, name: nameOf(el), text: (el.innerText || "").trim().replace(/\s+/g, " ").slice(0, 200), part: part(el) });
    say();
  }, true);

  addEventListener("message", (e) => {
    if (e.source !== window.parent || !e.data || typeof e.data !== "object") return;
    const m = e.data;
    if (m.laweditor === "tools") {
      S.measures = !!m.measures; S.tool = m.tool === "inspect" || m.tool === "comment" ? m.tool : "";
      if (!S.tool) S.hover = null;
      if (S.tool !== "comment") S.fresh = null;
      document.documentElement.classList.toggle("laweditor-picks", !!S.tool);
    }
    if (m.laweditor === "pins") {
      if (m.do === "keep" && S.fresh) S.pins.push(S.fresh);
      if (m.do === "clear") S.pins = [];
      S.fresh = null;
    }
    say();
  });

  // The page moved or changed: the drawing follows.
  addEventListener("scroll", say, { capture: true, passive: true });
  addEventListener("resize", say);
  new MutationObserver(say).observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });
  setInterval(() => { if (S.measures || S.tool || S.pins.length) say(); }, 400);   // what moves by itself (an animation, a font that arrives)
  tell({ laweditor: "ready" });
})();
