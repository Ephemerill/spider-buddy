// Spider Buddy's go-between: keeps a line open to the app on this Mac
// (a WebSocket on 127.0.0.1 only), tells the pages the app is climbing to
// report on themselves, and passes what they report on — with the window
// they are in, so the app can tell which of its windows it is.
//
// The app says which windows it is climbing (by where they are on the
// screen); in each, only the tab showing is asked. Nothing is sent anywhere
// but the app, and nothing a page says is kept here.

const PORTS = [47219, 47220, 47221];
let socket = null;
let open = false;
let portIndex = 0;
let retrying = null;
// Windows the app is climbing: [{left, top, width, height}], screen points.
let wanted = [];
// Pages connected to us, by tab id.
const pages = new Map();
// Tabs asked to report, and where their windows are.
const measuring = new Map();

function connect() {
  if (socket) return;
  retrying = null;
  let ws;
  try {
    ws = new WebSocket(`ws://127.0.0.1:${PORTS[portIndex]}/spider`);
  } catch (e) {
    retry();
    return;
  }
  socket = ws;
  ws.onopen = () => {
    open = true;
    send({ type: "hello", v: 1 });
  };
  ws.onmessage = (e) => {
    let m;
    try { m = JSON.parse(e.data); } catch (err) { return; }
    if (m.type === "want") {
      wanted = Array.isArray(m.windows) ? m.windows : [];
      choose();
    } else if (m.type === "ping") {
      send({ type: "pong" });
    }
  };
  ws.onclose = () => {
    socket = null;
    if (!open) portIndex = (portIndex + 1) % PORTS.length;
    open = false;
    wanted = [];
    choose();
    retry();
  };
  ws.onerror = () => {};
}

function retry() {
  if (retrying) return;
  retrying = setTimeout(() => { retrying = null; connect(); }, 4000);
}

function send(m) {
  if (socket && open) {
    try { socket.send(JSON.stringify(m)); } catch (e) {}
  }
}

function near(a, b) {
  return Math.abs(a.left - b.left) <= 6 && Math.abs(a.top - b.top) <= 6
    && Math.abs(a.width - b.width) <= 6 && Math.abs(a.height - b.height) <= 6;
}

// Which tabs should be reporting: the one showing in each window the app
// is climbing. Every other page is told to stop.
async function choose() {
  const on = new Map();
  if (wanted.length) {
    let windows = [];
    try { windows = await chrome.windows.getAll({ populate: true }); } catch (e) {}
    for (const w of windows) {
      if (w.state === "minimized") continue;
      const box = { left: w.left, top: w.top, width: w.width, height: w.height };
      if (!wanted.some((r) => near(r, box))) continue;
      const tab = (w.tabs || []).find((t) => t.active);
      if (tab) on.set(tab.id, { ...box, state: w.state, id: w.id });
    }
  }
  for (const [tab, port] of pages) {
    const was = measuring.has(tab);
    const now = on.has(tab);
    if (now) measuring.set(tab, on.get(tab)); else measuring.delete(tab);
    if (was !== now) {
      try { port.postMessage({ type: "measure", on: now }); } catch (e) {}
      if (!now) send({ type: "gone", tab });
    }
  }
}

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== "page" || !port.sender || !port.sender.tab) return;
  const tab = port.sender.tab.id;
  pages.set(tab, port);
  connect();
  port.onMessage.addListener((m) => {
    const where = measuring.get(tab);
    if (!where || typeof m !== "object" || !m) return;
    send({ ...m, tab, window: where });
  });
  port.onDisconnect.addListener(() => {
    if (pages.get(tab) === port) pages.delete(tab);
    if (measuring.delete(tab)) send({ type: "gone", tab });
  });
  choose();
});

chrome.tabs.onActivated.addListener(() => choose());
chrome.windows.onBoundsChanged && chrome.windows.onBoundsChanged.addListener(() => choose());
chrome.windows.onFocusChanged.addListener(() => choose());
chrome.runtime.onStartup.addListener(() => connect());
chrome.runtime.onInstalled.addListener(() => connect());
connect();
// While the app is there, a word now and then keeps this worker (and the
// line) from being put to sleep.
setInterval(() => { if (open) send({ type: "alive" }); }, 20000);
