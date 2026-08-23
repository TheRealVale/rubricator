/* md review layer — annotate a rendered document, export feedback for an AI. */
(function(){
"use strict";
/* one chrome, many documents. Everything per-document is reassigned by
   openDoc(), so every closure below keeps working when a second file is
   loaded into the same page — that is what lets the workspace reuse it. */
var doc = null, META = {}, raw = '', body = '', fmLines = 0, rawLines = [];
var PATH = '', SHORT = '';

var VERBS = {
  change:  { label:'Change',   color:'var(--v-change)',   key:'c' },
  question:{ label:'Question', color:'var(--v-question)', key:'?' },
  cut:     { label:'Cut',      color:'var(--v-cut)',      key:'x' },
  expand:  { label:'Expand',   color:'var(--v-expand)',   key:'e' },
  note:    { label:'Note',     color:'var(--v-note)',     key:'n' },
  approve: { label:'Approve',  color:'var(--v-approve)',  key:'a' }
};
var ORDER = ['change','question','cut','expand','note','approve'];
var TYPES = { change:'CHANGE', question:'QUESTION', cut:'CUT', expand:'EXPAND', approve:'APPROVE' };
var SILENT = { approve:1, cut:1 };   // verbs that don't need a note
/* a Note records context; it asks for nothing. It rides along as an appendix
   rather than as a numbered instruction, and it never turns an approval into a
   rejection. */
function isAsk(it){ return it.verb !== 'note' && it.verb !== 'approve'; }
function askItems(){ return exportItems().filter(isAsk); }
function noteItems(){ return exportItems().filter(function(i){ return i.verb === 'note'; }); }

/* ── storage ─────────────────────────────────────────── */
function hash(s){ var h=5381,i=s.length; while(i) h=(h*33^s.charCodeAt(--i))>>>0; return h.toString(36); }
var DEFAULT_PRE = "Apply this feedback. Don't restructure anything I didn't mention.";
var KEY = '';
var store = { seq:1, preamble:DEFAULT_PRE, template:'apply', items:[] };
/* where notes live. The default is this browser; a host that has somewhere
   better — a served workspace with a repo to write into — replaces these two. */
var Storage = {
  get: function(key){
    try { return JSON.parse(localStorage.getItem(key) || 'null'); } catch(e){ return null; }
  },
  set: function(key, val){
    try { localStorage.setItem(key, JSON.stringify(val)); } catch(e){}
  }
};
function loadStore(){
  KEY = 'md-review:' + hash(META.path || (META.dir + '/' + META.name));
  store = { seq:1, preamble:DEFAULT_PRE, template:'apply', items:[] };
  var saved = null;
  try { saved = Storage.get(KEY, META.path); } catch(e){}
  if (saved && typeof saved === 'object'){ for (var k in saved) store[k] = saved[k]; }
  if (store.template === 'notes') store.template = 'raw';   // renamed, freeing the word for the verb
}
function save(){
  store.saved = Date.now();          // lets two stores be merged by recency
  try { Storage.set(KEY, store, META.path); } catch(e){}
}

/* ── source helpers ──────────────────────────────────── */
function srcSlice(a, b){ return rawLines.slice(a-1, b).join('\n').replace(/\s+$/,''); }
function lineOfOffset(off){ return fmLines + body.slice(0, off).split('\n').length; }

/* ── 1. map rendered blocks to source lines ──────────── */
function mapLines(){
  var tokens;
  try { tokens = marked.lexer(body); } catch(e){ return; }
  var probe = document.createElement('template'), off = 0, idx = 0;
  tokens.forEach(function(t){
    var start = lineOfOffset(off);
    var end = start + t.raw.replace(/\n+$/,'').split('\n').length - 1;
    off += t.raw.length;
    if (t.type === 'space') return;
    var n = 1;
    try { probe.innerHTML = marked.parser([t]); n = probe.content.children.length; } catch(e){}
    for (var i = 0; i < n; i++){
      var el = doc.children[idx + i];
      if (el){ el.dataset.lineStart = start; el.dataset.lineEnd = end; }
    }
    idx += n;
  });
}

var blocks = [];
function blockAtLine(l){
  for (var i=0;i<blocks.length;i++){
    if (+blocks[i].dataset.lineStart <= l && l <= +blocks[i].dataset.lineEnd) return blocks[i];
  }
  return null;
}
function headingFor(el){
  var n = el;
  while (n){
    if (/^H[1-6]$/.test(n.tagName)) return n.textContent.replace(/^#/,'').trim();
    n = n.previousElementSibling;
  }
  return '';
}
function headingLevel(line){ var m = /^(#{1,6})\s/.exec(line || ''); return m ? m[1].length : 0; }
function sectionEnd(startLine){
  var lvl = headingLevel(rawLines[startLine - 1]);
  if (!lvl) return startLine;
  for (var i = startLine; i < rawLines.length; i++){
    var l = headingLevel(rawLines[i]);
    if (l && l <= lvl){
      var end = i;                       // rawLines[i] is the next heading (0-based)
      while (end > startLine && !rawLines[end - 1].trim()) end--;
      return end;
    }
  }
  var last = rawLines.length;
  while (last > startLine && !rawLines[last - 1].trim()) last--;
  return last;
}
function blockOf(node){
  var el = node && (node.nodeType === 1 ? node : node.parentElement);
  return el ? el.closest('[data-line-start]') : null;
}

/* ── 2. re-anchor stored items against the current source ── */
function reanchor(){
  store.items.forEach(function(it){
    var i = it.anchor ? raw.indexOf(it.anchor) : -1;
    if (i >= 0){
      it.state = 'open';
      it.lineStart = raw.slice(0, i).split('\n').length;
      it.lineEnd = it.section ? sectionEnd(it.lineStart)
                 : it.lineStart + it.anchor.replace(/\n+$/,'').split('\n').length - 1;
      if (!it.partial) it.quote = srcSlice(it.lineStart, it.lineEnd);
    } else {
      it.state = 'stale';
    }
  });
  store.items.sort(function(x, y){ return x.lineStart - y.lineStart || x.id - y.id; });
  save();
}

/* the workspace keeps this chrome on a page that also shows lists; the layer
   must not react to keys or selections while its document is hidden */
function live(){ return !!doc && doc.isConnected && doc.offsetParent !== null; }

/* ── highlights ──────────────────────────────────────── */
var HL = null;
try { if (window.Highlight && CSS.highlights){ HL = new Highlight(); CSS.highlights.set('md-anno', HL); } } catch(e){}
function findRange(root, text){
  if (!root || !text) return null;
  var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), nodes = [], full = '', n;
  while ((n = w.nextNode())){ nodes.push([n, full.length]); full += n.nodeValue; }
  var at = full.indexOf(text);
  if (at < 0) return null;
  function pos(i, end){
    for (var k=0;k<nodes.length;k++){
      var node = nodes[k][0], s = nodes[k][1], len = node.nodeValue.length;
      if (end ? (i <= s + len) : (i < s + len)) return [node, i - s];
    }
    var last = nodes[nodes.length-1];
    return [last[0], last[0].nodeValue.length];
  }
  var a = pos(at, false), b = pos(at + text.length, true);
  var r = document.createRange();
  try { r.setStart(a[0], a[1]); r.setEnd(b[0], b[1]); } catch(e){ return null; }
  return r;
}

/* ── 3. paint markers ────────────────────────────────── */
function paint(){
  blocks.forEach(function(el){ el.classList.remove('has-anno'); el.style.removeProperty('--anno-color'); });
  if (HL) HL.clear();
  store.items.forEach(function(it){
    if (it.state !== 'open') return;
    blocks.forEach(function(el){
      if (+el.dataset.lineEnd < it.lineStart || +el.dataset.lineStart > it.lineEnd) return;
      if (!el.classList.contains('has-anno')){
        el.classList.add('has-anno');
        el.style.setProperty('--anno-color', VERBS[it.verb].color);
      }
    });
    if (HL && it.partial && it.quote){
      var r = findRange(blockAtLine(it.lineStart), it.quote);
      if (r) HL.add(r);
    }
  });
}

/* ── ui scaffolding ──────────────────────────────────── */
var pop = document.getElementById('pop');
var composer = document.getElementById('composer');
var tray = document.getElementById('tray');
var trayList = document.getElementById('tray-list');
var trayCount = document.getElementById('tray-count');
var revBtn = document.getElementById('revbtn');
var revCnt = document.getElementById('revcnt');
var toastEl = document.getElementById('toast');
var preBox = document.getElementById('pre-box');
var goBtn = document.getElementById('go');
var toastT = null;
function toast(msg){
  toastEl.textContent = msg; toastEl.classList.add('show');
  clearTimeout(toastT); toastT = setTimeout(function(){ toastEl.classList.remove('show'); }, 1900);
}

/* popover buttons */
ORDER.forEach(function(v){
  var b = document.createElement('button');
  b.innerHTML = '<span class="dot" style="background:' + VERBS[v].color + '"></span>' + VERBS[v].label;
  b.addEventListener('mousedown', function(e){ e.preventDefault(); });
  b.addEventListener('click', function(){ addFromSelection(v); });
  pop.appendChild(b);
});
(function(){
  var sep = document.createElement('span'); sep.className = 'sep'; pop.appendChild(sep);
  var b = document.createElement('button'); b.className = 'k'; b.textContent = 'Copy';
  b.addEventListener('mousedown', function(e){ e.preventDefault(); });
  b.addEventListener('click', function(){
    var s = String(getSelection()); if (s) { copy(s); toast('Copied selection'); }
    hidePop(); getSelection().removeAllRanges();
  });
  pop.appendChild(b);
})();

/* ── selection → popover ─────────────────────────────── */
function selInfo(){
  var sel = getSelection();
  if (!sel || sel.isCollapsed || !sel.rangeCount) return null;
  var r = sel.getRangeAt(0);
  if (!doc.contains(r.commonAncestorContainer)) return null;
  var text = String(sel).replace(/\s+$/,'');
  if (!text.trim()) return null;
  var b1 = blockOf(r.startContainer), b2 = blockOf(r.endContainer) || b1;
  if (!b1) return null;
  return { text:text, a:+b1.dataset.lineStart, b:+(b2 || b1).dataset.lineEnd,
           block:b1, rect:r.getBoundingClientRect() };
}
function showPop(rect){
  pop.classList.add('show');
  var w = pop.offsetWidth, h = pop.offsetHeight;
  var left = scrollX + rect.left + rect.width/2 - w/2;
  left = Math.max(8, Math.min(left, scrollX + innerWidth - w - 8));
  var top = scrollY + rect.top - h - 9;
  if (rect.top - h - 9 < 52) top = scrollY + rect.bottom + 9;
  pop.style.left = Math.round(left) + 'px';
  pop.style.top = Math.round(top) + 'px';
}
function hidePop(){ pop.classList.remove('show'); }
document.addEventListener('selectionchange', function(){
  if (!live()) return;
  if (composer.classList.contains('show')) return;
  var s = selInfo();
  if (s) showPop(s.rect); else hidePop();
});

/* ── creating items ──────────────────────────────────── */
function addItem(verb, quote, a, b, partial, el, section){
  var it = {
    id: store.seq++, verb: verb, quote: quote,
    anchor: section ? rawLines[a - 1] : srcSlice(a, b),
    note: '', lineStart: a, lineEnd: b, partial: !!partial, section: !!section,
    heading: headingFor(el || blockAtLine(a) || doc), state: 'open'
  };
  store.items.push(it);
  store.items.sort(function(x, y){ return x.lineStart - y.lineStart || x.id - y.id; });
  save(); paint(); renderTray();
  return it;
}
function addFromSelection(verb){
  var s = selInfo();
  if (!s) return;
  var whole = s.text.trim() === srcSlice(s.a, s.b).trim();
  var it = addItem(verb, s.text.trim(), s.a, s.b, !whole, s.block);
  hidePop();
  getSelection().removeAllRanges();
  if (SILENT[verb]) toast(VERBS[verb].label + ' · line ' + s.a);
  else openComposer(it);
}
function addFromBlock(verb, el){
  if (!el) { toast('Hover a block or select text first'); return; }
  var a = +el.dataset.lineStart, b = +el.dataset.lineEnd, section = false;
  if (/^H[1-6]$/.test(el.tagName)){ b = sectionEnd(a); section = b > a; }
  var it = addItem(verb, srcSlice(a, b), a, b, false, el, section);
  if (SILENT[verb]) toast(VERBS[verb].label + ' · line ' + a);
  else openComposer(it, el);
}

/* ── composer ────────────────────────────────────────── */
var editing = null, saveT = null;
var cChips = document.getElementById('c-chips');
var cText = document.getElementById('c-text');
var cDel = document.getElementById('c-del');
ORDER.forEach(function(v){
  var b = document.createElement('button');
  b.className = 'chip'; b.dataset.verb = v; b.textContent = VERBS[v].label;
  b.addEventListener('click', function(){
    if (!editing) return;
    editing.verb = v; save(); paint(); renderTray(); syncChips();
  });
  cChips.appendChild(b);
});
function syncChips(){
  [].forEach.call(cChips.children, function(b){
    var on = editing && b.dataset.verb === editing.verb;
    b.classList.toggle('on', !!on);
    b.style.setProperty('--chip-color', VERBS[b.dataset.verb].color);
  });
}
function openComposer(it, el){
  editing = it;
  var target = el || blockAtLine(it.lineStart);
  composer.classList.add('show');
  syncChips();
  cText.value = it.note || '';
  var r = target ? target.getBoundingClientRect() : { left: innerWidth/2 - 164, bottom: innerHeight/2, top: 0 };
  var w = composer.offsetWidth;
  var left = Math.max(8, Math.min(scrollX + r.left, scrollX + innerWidth - w - 8));
  composer.style.left = Math.round(left) + 'px';
  composer.style.top = Math.round(scrollY + r.bottom + 8) + 'px';
  cText.focus({ preventScroll: true });   // the composer is already where you're looking
  hidePop();
}
function closeComposer(){
  composer.classList.remove('show'); editing = null;
}
cText.addEventListener('input', function(){
  if (!editing) return;
  editing.note = cText.value;
  clearTimeout(saveT);
  saveT = setTimeout(function(){ save(); renderTray(); }, 250);
});
cText.addEventListener('keydown', function(e){
  if (e.key === 'Enter' && !e.shiftKey){ e.preventDefault(); save(); renderTray(); closeComposer(); }
  if (e.key === 'Escape'){ e.preventDefault(); save(); renderTray(); closeComposer(); }
});
cDel.addEventListener('click', function(){
  if (!editing) return;
  removeItem(editing.id); closeComposer();
});
document.addEventListener('mousedown', function(e){
  if (!composer.contains(e.target) && !pop.contains(e.target) && composer.classList.contains('show')){
    save(); renderTray(); closeComposer();
  }
});

function removeItem(id){
  store.items = store.items.filter(function(i){ return i.id !== id; });
  save(); paint(); renderTray();
}

/* ── tray ────────────────────────────────────────────── */
function openCount(){ return store.items.filter(function(i){ return i.state === 'open'; }).length; }
function renderTray(){
  var open = openCount(), stale = store.items.length - open;
  trayCount.textContent = open + (stale ? ' · ' + stale + ' resolved' : '');
  revCnt.textContent = open;
  revCnt.style.display = open ? '' : 'none';
  goBtn.disabled = !exportItems().length;
  if (!store.items.length){
    if (window.__mdHookSync) window.__mdHookSync();
    trayList.innerHTML = '<div class="empty">Nothing yet.<br><br>' +
      'Select any text for the verb popover, or hover a block and press ' +
      '<kbd>c</kbd> change · <kbd>?</kbd> question · <kbd>x</kbd> cut · ' +
      '<kbd>e</kbd> expand · <kbd>n</kbd> note · <kbd>a</kbd> approve.</div>';
    return;
  }
  if (window.__mdHookSync) window.__mdHookSync();
  trayList.innerHTML = '';
  store.items.forEach(function(it){
    var d = document.createElement('div');
    d.className = 'anno' + (it.state === 'stale' ? ' stale' : '');
    d.style.setProperty('--anno-color', VERBS[it.verb].color);
    d.style.borderLeftColor = it.state === 'stale' ? 'transparent' : VERBS[it.verb].color;
    var loc = SHORT + ':' + it.lineStart + (it.lineEnd > it.lineStart ? '-' + it.lineEnd : '');
    d.innerHTML =
      '<div class="top"><span class="verb">' + VERBS[it.verb].label + '</span>' +
      '<span class="loc">' + esc(loc) + '</span>' +
      (it.state === 'stale' ? '<span class="tag">gone</span>' : '') +
      '<button class="x" title="Delete">&times;</button></div>' +
      '<div class="q">' + esc(clip(it.quote, 220)) + '</div>' +
      '<div class="note">' + esc(it.note) + '</div>';
    d.querySelector('.x').addEventListener('click', function(e){ e.stopPropagation(); removeItem(it.id); });
    d.addEventListener('click', function(){ jumpTo(it); });
    trayList.appendChild(d);
  });
}
function jumpTo(it){
  var el = blockAtLine(it.lineStart);
  if (!el){ toast('That text is no longer in the document'); return; }
  el.scrollIntoView({ block:'center', behavior:'smooth' });
  el.classList.remove('anno-flash'); void el.offsetWidth; el.classList.add('anno-flash');
  setTimeout(function(){ openComposer(it, el); }, 320);
}
function clip(s, n){ s = String(s || ''); return s.length > n ? s.slice(0, n) + '…' : s; }
function esc(s){ return String(s || '').replace(/[&<>"]/g, function(c){
  return { '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;' }[c]; }); }

function toggleTray(force){
  var open = force === undefined ? !tray.classList.contains('open') : force;
  tray.classList.toggle('open', open);
  document.body.classList.toggle('tray-open', open);
}
revBtn.addEventListener('click', function(){ toggleTray(); });
document.getElementById('tray-close').addEventListener('click', function(){ toggleTray(false); });

/* preamble + template */
preBox.addEventListener('input', function(){ store.preamble = preBox.value; save(); });
[].forEach.call(document.querySelectorAll('#tray .tpl button'), function(b){
  b.addEventListener('click', function(){
    store.template = b.dataset.tpl; save(); syncTpl(); renderTray();
  });
});
function syncTpl(){
  [].forEach.call(document.querySelectorAll('#tray .tpl button'), function(b){
    b.classList.toggle('on', b.dataset.tpl === store.template);
  });
  preBox.style.display = store.template === 'apply' ? '' : 'none';
}

/* ── export ──────────────────────────────────────────── */
function exportItems(){
  var open = store.items.filter(function(i){ return i.state === 'open'; });
  if (store.template === 'questions') open = open.filter(function(i){ return i.verb === 'question'; });
  return open;
}
function exportQuote(it){
  var q = String(it.quote || ''), lines = q.split('\n');
  var n = it.lineEnd - it.lineStart + 1;
  if (it.partial) return clip(q, 300).split('\n');
  if (it.section) return [lines[0], '… (' + n + ' lines in this section)'];
  if (lines.length <= 4 && q.length <= 320) return lines;
  return lines.slice(0, 2).concat('… (' + n + ' lines)');
}
function locOf(it){
  return SHORT + ':' + it.lineStart + (it.lineEnd > it.lineStart ? '-' + it.lineEnd : '');
}
function appendNotes(out, notes){
  if (!notes.length) return;
  out.push('Notes — context, not change requests:');
  out.push('');
  notes.forEach(function(it){
    var line = '— ' + locOf(it);
    if (it.heading) line += ' — "' + it.heading + '"';
    out.push(line);
    exportQuote(it).forEach(function(q){ out.push('   > ' + q); });
    if (it.note.trim()) it.note.trim().split('\n').forEach(function(l){ out.push('   ' + l); });
    out.push('');
  });
}
/* the notes appendix on its own — what an approval carries along */
function buildNotes(){
  var notes = noteItems();
  if (!notes.length) return '';
  var out = [];
  appendNotes(out, notes);
  return out.join('\n').replace(/\n+$/, '\n');
}
function buildExport(){
  var items = exportItems();
  if (!items.length) return '';
  var notes = store.template === 'questions' ? [] : noteItems();
  var main  = items.filter(function(i){ return notes.indexOf(i) < 0; });
  var out = [], n = 0;
  var head;
  if (store.template === 'questions')
    head = 'Questions about ' + PATH + ' — ' + items.length + '. Answer them; don\'t edit the file yet.';
  else if (!main.length)
    head = 'Notes on ' + PATH + ' — ' + notes.length + '. Nothing to change.';
  else if (store.template === 'raw')
    head = PATH + ' — ' + main.length + ' item' + (main.length > 1 ? 's' : '') + '.';
  else
    head = 'Feedback on ' + PATH + ' — ' + main.length + ' item' + (main.length > 1 ? 's' : '') + '.';
  out.push(head);
  if (store.template === 'apply' && main.length && store.preamble.trim()) out.push(store.preamble.trim());
  out.push('');
  main.forEach(function(it){
    n++;
    var line = n + '. ' + TYPES[it.verb] + ' — ' + locOf(it);
    if (it.heading) line += ' — "' + it.heading + '"';
    out.push(line);
    exportQuote(it).forEach(function(q){ out.push('   > ' + q); });
    if (it.note.trim()) it.note.trim().split('\n').forEach(function(l){ out.push('   ' + l); });
    out.push('');
  });
  appendNotes(out, notes);
  return out.join('\n').replace(/\n+$/, '\n');
}
function copy(text){
  var done = function(){};
  if (navigator.clipboard && navigator.clipboard.writeText){
    navigator.clipboard.writeText(text).then(done, fallback);
  } else fallback();
  function fallback(){
    var ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.top = '-1000px';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); } catch(e){}
    ta.remove();
  }
}
function doExport(){
  var txt = buildExport();
  if (!txt){ toast('Nothing to export'); return; }
  copy(txt);
  toast('Copied ' + exportItems().length + ' item' + (exportItems().length > 1 ? 's' : '') + ' — paste into your AI');
  toggleTray(true);
}
goBtn.addEventListener('click', doExport);

/* ── keyboard ────────────────────────────────────────── */
var focusIdx = -1;
function setFocus(i, scroll){
  if (focusIdx >= 0 && blocks[focusIdx]) blocks[focusIdx].classList.remove('kb-focus');
  focusIdx = Math.max(0, Math.min(i, blocks.length - 1));
  var el = blocks[focusIdx];
  if (!el) return;
  el.classList.add('kb-focus');
  if (scroll) el.scrollIntoView({ block:'nearest', behavior:'smooth' });
}
function onHover(e){
  var b = blockOf(e.target);
  if (!b) return;
  var i = blocks.indexOf(b);
  if (i >= 0 && i !== focusIdx) setFocus(i, false);
}
document.addEventListener('keydown', function(e){
  if (!live()) return;
  var typing = /^(INPUT|TEXTAREA)$/.test(e.target.tagName) || e.target.isContentEditable;
  if ((e.metaKey || e.ctrlKey) && e.key === 'Enter'){ e.preventDefault(); doExport(); return; }
  if (typing || e.altKey || e.metaKey || e.ctrlKey) return;
  if (e.key === 'Escape'){ hidePop(); closeComposer(); toggleTray(false); return; }
  if (e.key === 'j'){ e.preventDefault(); setFocus(focusIdx + 1, true); return; }
  if (e.key === 'k'){ e.preventDefault(); setFocus(focusIdx <= 0 ? 0 : focusIdx - 1, true); return; }
  if (e.key === 'f'){ e.preventDefault(); toggleTray(); return; }
  for (var v in VERBS){
    if (e.key === VERBS[v].key){
      e.preventDefault();
      if (selInfo()) addFromSelection(v);
      else addFromBlock(v, blocks[focusIdx]);
      return;
    }
  }
});

/* ── go ──────────────────────────────────────────────── */
/* openDoc() loads a document into this chrome. Calling it again swaps the
   document without rebuilding a single listener or leaking the last one's state. */
var booted = false, hovering = null;
function openDoc(m){
  if (!m || !m.doc) return;
  doc = m.doc;
  META = m.META || {};
  raw  = m.raw || '';
  body = m.body != null ? m.body : raw;
  fmLines = m.fmLines || 0;
  rawLines = raw.split('\n');
  PATH  = META.rel || META.name || '';
  SHORT = META.name || PATH;

  hidePop(); closeComposer();
  loadStore();
  mapLines();
  blocks = [].filter.call(doc.children, function(el){ return el.dataset.lineStart; });
  focusIdx = -1;

  if (hovering !== doc){
    if (hovering) hovering.removeEventListener('mouseover', onHover);
    doc.addEventListener('mouseover', onHover);
    hovering = doc;
  }

  reanchor();
  preBox.value = store.preamble;
  syncTpl(); paint(); renderTray();
  if (!booted){ booted = true; hookMode(); }
}

window.MDReview = { open: openDoc, count: openCount, storage: Storage,
                    reload: function(){ if (doc) openDoc({ doc: doc, META: META, raw: raw,
                                                           body: body, fmLines: fmLines }); } };
if (window.__md) openDoc(window.__md);

/* ── hook mode: an agent is blocked on this window ───────────────────── */
function hookMode(){
  var H = META.hook;
  if (!H || !H.url) return;
  document.body.classList.add('hook-mode');

  var banner = document.createElement('div');
  banner.className = 'hk-banner';
  banner.innerHTML = '<span class="dot"></span><span class="txt">Claude is waiting for your review</span>' +
                     '<span class="clock" id="hk-clock"></span>';
  tray.insertBefore(banner, tray.querySelector('.list'));
  tray.querySelector('.th .t').textContent = 'Review';

  var foot = tray.querySelector('.foot');
  var actions = document.createElement('div');
  actions.className = 'hk-actions';
  actions.innerHTML =
    '<button id="hk-approve">Approve <kbd>⌘⇧⏎</kbd></button>' +
    '<button id="hk-send">Send feedback <kbd>⌘⏎</kbd></button>';
  foot.insertBefore(actions, goBtn);
  goBtn.style.display = 'none';
  var copyLink = document.createElement('button');
  copyLink.className = 'lnk hk-copy';
  copyLink.textContent = 'copy to clipboard instead';
  foot.insertBefore(copyLink, goBtn.nextSibling);
  copyLink.addEventListener('click', doExport);

  var approveBtn = document.getElementById('hk-approve');
  var sendBtn = document.getElementById('hk-send');
  var clock = document.getElementById('hk-clock');
  var sent = false, expired = false;

  /* the primary action follows what you've actually done:
     nothing marked up -> approving is the obvious move; marked up -> sending is */
  window.__mdHookSync = function(){
    var n = askItems().length, notes = noteItems().length;
    sendBtn.disabled = expired || !n;
    approveBtn.disabled = expired;
    approveBtn.classList.toggle('primary', !expired && !n);
    sendBtn.classList.toggle('primary', !expired && !!n);
    sendBtn.firstChild.nodeValue = n ? 'Send ' + n + ' item' + (n > 1 ? 's ' : ' ') : 'Send feedback ';
    approveBtn.firstChild.nodeValue = (!n && notes) ? 'Approve with notes ' : 'Approve ';
  };
  window.__mdHookSync();

  function done(action){
    var ok = action === 'approve';
    var el = document.createElement('div');
    el.className = 'hk-done show ' + action;
    el.innerHTML =
      '<div class="card"><div class="ic">' +
      (ok ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>'
          : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>') +
      '</div><h4>' + (ok ? 'Plan approved' : 'Feedback sent') + '</h4>' +
      '<p>' + (ok ? 'Claude is carrying on.' : 'Claude is revising the plan.') + '</p></div>';
    document.body.appendChild(el);
  }

  function verdict(action){
    if (sent || expired && action !== 'closed') return;
    sent = true;
    var text = action === 'feedback' ? buildExport() : (action === 'approve' ? buildNotes() : '');
    done(action);
    try {
      fetch(H.url, { method:'POST', headers:{'Content-Type':'application/json'},
                     body: JSON.stringify({ action:action, text:text }) });
    } catch(e){}
  }
  approveBtn.addEventListener('click', function(){ verdict('approve'); });
  sendBtn.addEventListener('click', function(){ if (askItems().length) verdict('feedback'); });

  /* closing the window is not consent — hand it back to the terminal prompt */
  addEventListener('pagehide', function(){
    if (sent) return;
    try {
      navigator.sendBeacon(H.url, new Blob([JSON.stringify({ action:'closed' })],
                                           { type:'application/json' }));
    } catch(e){}
  });

  document.addEventListener('keydown', function(e){
    if (!(e.metaKey || e.ctrlKey) || e.key !== 'Enter') return;
    e.preventDefault(); e.stopPropagation();
    if (e.shiftKey) verdict('approve');
    else if (askItems().length) verdict('feedback');
  }, true);

  function tick(){
    if (sent) return;
    var left = Math.max(0, Math.round((H.deadline - Date.now()) / 1000));
    clock.textContent = Math.floor(left / 60) + ':' + ('0' + (left % 60)).slice(-2);
    clock.classList.toggle('warn', left <= 60 && left > 0);
    if (left <= 0){
      expired = true;
      banner.classList.add('expired');
      banner.querySelector('.txt').textContent = 'Timed out — Claude fell back to the terminal prompt';
      clock.textContent = '';
      window.__mdHookSync();
      return;
    }
    setTimeout(tick, 1000);
  }
  if (H.deadline) tick();

  toggleTray(true);
}

/* a live handle, not a snapshot — `store` is replaced on every openDoc() */
window.__mdReview = { get store(){ return store; }, build: buildExport, notes: buildNotes };
})();
