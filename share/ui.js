/* md reader UX — outline modes, resizable tray, document search, shortcuts. */
(function(){
"use strict";
var M = window.__md; if (!M) return;
var doc = M.doc;
var root = document.documentElement;
var toc = document.getElementById('toc');
var scrim = document.getElementById('scrim');
var bar = document.querySelector('.bar');
var narrow = function(){ return innerWidth <= 1180; };
function ls(k, v){
  try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch(e){}
  return null;
}

/* ── outline: full → mini → hidden ───────────────────────────────────── */
var MODES = ['full','mini','hidden'];
var tocBtn = document.getElementById('tocbtn');
var hasToc = toc && !toc.hidden;
if (!hasToc && tocBtn) tocBtn.style.display = 'none';

function setMode(m, remember){
  if (!hasToc) return;
  if (narrow() && m === 'mini') m = 'hidden';
  toc.dataset.mode = m;
  toc.classList.toggle('drawer', narrow() && m === 'full');
  scrim.classList.toggle('on', narrow() && m === 'full');
  if (tocBtn){
    tocBtn.classList.toggle('on', m !== 'hidden');
    tocBtn.title = 'Outline: ' + m + ' (o)';
  }
  if (remember !== false) ls('md-toc-mode', m);
  if (typeof syncShift === 'function') syncShift();
}
function cycleMode(){
  var cur = toc.dataset.mode || 'full';
  var next = narrow()
    ? (cur === 'full' ? 'hidden' : 'full')
    : MODES[(MODES.indexOf(cur) + 1) % MODES.length];
  setMode(next);
}
// on a narrow window the outline is an overlay — never open it unasked
var hookMode = !!(M.META && M.META.hook);
setMode(narrow() ? 'hidden' : (ls('md-toc-mode') || (hookMode ? 'mini' : 'full')), false);
if (tocBtn) tocBtn.addEventListener('click', cycleMode);
scrim.addEventListener('click', function(){ setMode('hidden'); });
toc && toc.addEventListener('click', function(e){
  if (narrow() && e.target.tagName === 'A') setMode('hidden');
});
addEventListener('resize', function(){ setMode(toc && toc.dataset.mode || 'full', false); syncShift(); });

/* ── resizable tray ──────────────────────────────────────────────────── */
var tray = document.getElementById('tray');
function clampW(w){ return Math.max(300, Math.min(w, Math.min(760, innerWidth - 360))); }
var savedW = parseInt(ls('md-tray-w') || '', 10);
if (savedW) root.style.setProperty('--tray-w', clampW(savedW) + 'px');
function syncShift(){
  var open = document.body.classList.contains('tray-open');
  var w = getComputedStyle(root).getPropertyValue('--tray-w').trim() || '352px';
  root.style.setProperty('--tray-shift', open && !narrow() ? w : '0px');
  document.body.classList.toggle('cramped', !outlineFits());
}
/* true when the outline still clears the text column in its current mode —
   mini needs far less room than full, which is the point of it */
function outlineFits(){
  if (!hasToc) return true;
  var mode = (toc && toc.dataset.mode) || 'full';
  if (mode === 'hidden') return true;
  var open = document.body.classList.contains('tray-open');
  var used = open && !narrow()
    ? (parseInt(getComputedStyle(root).getPropertyValue('--tray-w'), 10) || 0) : 0;
  var avail = innerWidth - used;
  var w   = mode === 'mini' ? 34  : 212;
  var off = mode === 'mini' ? 452 : 620;
  var contentW = Math.min(812, avail - 56);
  var contentLeft = (avail - contentW) / 2;
  return Math.max(20, avail / 2 - off) + w + 10 <= contentLeft + 28;   // +28 = .wrap padding
}
new MutationObserver(syncShift).observe(document.body, { attributes:true, attributeFilter:['class'] });
syncShift();

if (tray){
  var rz = document.createElement('div');
  rz.className = 'rz'; rz.title = 'Drag to resize';
  tray.appendChild(rz);
  rz.addEventListener('pointerdown', function(e){
    e.preventDefault();
    rz.setPointerCapture(e.pointerId);
    document.body.classList.add('resizing');
    var move = function(ev){
      var w = clampW(innerWidth - ev.clientX);
      root.style.setProperty('--tray-w', w + 'px');
      syncShift();
    };
    var up = function(ev){
      rz.releasePointerCapture(e.pointerId);
      document.body.classList.remove('resizing');
      rz.removeEventListener('pointermove', move);
      rz.removeEventListener('pointerup', up);
      ls('md-tray-w', parseInt(getComputedStyle(root).getPropertyValue('--tray-w'), 10));
    };
    rz.addEventListener('pointermove', move);
    rz.addEventListener('pointerup', up);
  });
  rz.addEventListener('dblclick', function(){
    root.style.setProperty('--tray-w', '352px'); ls('md-tray-w', 352); syncShift();
  });
}

/* ── reading progress ────────────────────────────────────────────────── */
var prog = document.getElementById('prog');
var ticking = false;
function onScroll(){
  if (ticking) return;
  ticking = true;
  requestAnimationFrame(function(){
    ticking = false;
    var h = document.documentElement.scrollHeight - innerHeight;
    prog.style.width = (h > 0 ? Math.min(100, (scrollY / h) * 100) : 0) + '%';
  });
}
addEventListener('scroll', onScroll, { passive:true });
onScroll();

/* ── tidier path in the bar ──────────────────────────────────────────── */
(function(){
  var d = document.getElementById('fdir');
  if (!d) return;
  var full = d.textContent;
  d.title = full;
  if (full.length > 46){
    var parts = full.split('/').filter(Boolean);
    d.textContent = '…/' + parts.slice(-2).join('/');
  }
})();

/* ── document search ─────────────────────────────────────────────────── */
var box = document.getElementById('search');
var input = document.getElementById('s-input');
var countEl = document.getElementById('s-count');
var nodes = null, flat = '', ranges = [], cur = -1, hlAll = null, hlCur = null, debounce = null;

try {
  if (window.Highlight && CSS.highlights){
    hlAll = new Highlight(); hlCur = new Highlight();
    CSS.highlights.set('md-search', hlAll);
    CSS.highlights.set('md-search-cur', hlCur);
  }
} catch(e){}

function buildIndex(){
  nodes = []; flat = '';
  var w = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT, {
    acceptNode: function(n){
      var p = n.parentElement;
      if (!p || p.closest('.anchor, .mermaid, svg, .lang, .copy')) return NodeFilter.FILTER_REJECT;
      return n.nodeValue ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
    }
  });
  var n;
  while ((n = w.nextNode())){ nodes.push([n, flat.length]); flat += n.nodeValue; }
  flat = flat.toLowerCase();
}
function locate(i, isEnd){
  for (var k = 0; k < nodes.length; k++){
    var node = nodes[k][0], s = nodes[k][1], len = node.nodeValue.length;
    if (isEnd ? (i <= s + len) : (i < s + len)) return [node, i - s];
  }
  var last = nodes[nodes.length - 1];
  return [last[0], last[0].nodeValue.length];
}
function clearHits(){
  ranges = []; cur = -1;
  if (hlAll){ hlAll.clear(); hlCur.clear(); }
}
function run(q){
  clearHits();
  q = (q || '').toLowerCase();
  if (q.length < 2){ countEl.textContent = ''; countEl.classList.remove('none'); return; }
  if (!nodes) buildIndex();
  var at = 0, guard = 0;
  while (guard++ < 600){
    var i = flat.indexOf(q, at);
    if (i < 0) break;
    at = i + q.length;
    var a = locate(i, false), b = locate(i + q.length, true);
    var r = document.createRange();
    try { r.setStart(a[0], a[1]); r.setEnd(b[0], b[1]); ranges.push(r); if (hlAll) hlAll.add(r); } catch(e){}
  }
  countEl.classList.toggle('none', !ranges.length);
  if (!ranges.length){ countEl.textContent = 'no matches'; return; }
  // start from the match nearest the current viewport
  var best = 0;
  for (var k = 0; k < ranges.length; k++){
    if (ranges[k].getBoundingClientRect().top > 60){ best = k; break; }
  }
  go(best);
}
function go(i){
  if (!ranges.length) return;
  cur = (i + ranges.length) % ranges.length;
  var r = ranges[cur];
  if (hlCur){ hlCur.clear(); hlCur.add(r); }
  var box2 = r.getBoundingClientRect();
  if (box2.top < 90 || box2.bottom > innerHeight - 60){
    scrollTo({ top: scrollY + box2.top - Math.round(innerHeight * 0.32), behavior:'smooth' });
  }
  countEl.textContent = (cur + 1) + ' / ' + ranges.length;
}
function openSearch(){
  box.classList.add('show');
  input.focus(); input.select();
  if (input.value) run(input.value);
}
function closeSearch(){
  box.classList.remove('show');
  clearHits();
  countEl.textContent = '';
  input.blur();
}
function searchOpen(){ return box.classList.contains('show'); }

input.addEventListener('input', function(){
  clearTimeout(debounce);
  debounce = setTimeout(function(){ run(input.value); }, 130);
});
input.addEventListener('keydown', function(e){
  if (e.key === 'Enter'){ e.preventDefault(); go(cur + (e.shiftKey ? -1 : 1)); }
  if (e.key === 'Escape'){ e.preventDefault(); closeSearch(); }
  if (e.key === 'ArrowDown'){ e.preventDefault(); go(cur + 1); }
  if (e.key === 'ArrowUp'){ e.preventDefault(); go(cur - 1); }
});
document.getElementById('s-next').addEventListener('click', function(){ go(cur + 1); input.focus(); });
document.getElementById('s-prev').addEventListener('click', function(){ go(cur - 1); input.focus(); });
document.getElementById('s-close').addEventListener('click', closeSearch);
var searchBtn = document.getElementById('searchbtn');
if (searchBtn) searchBtn.addEventListener('click', function(){ searchOpen() ? closeSearch() : openSearch(); });

/* ── shortcuts sheet ─────────────────────────────────────────────────── */
var sheet = document.getElementById('sheet');
var sheetBg = document.getElementById('sheet-bg');
var SHEET = [
  ['Reading', [
    ['j / k', 'move between blocks'], ['/', 'search the document'],
    ['o', 'outline: full, mini, hidden'], ['t', 'light / dark'],
    ['⌘ P', 'print or save as PDF']
  ]],
  ['Review', [
    ['c', 'change — rewrite this'], ['?', 'question — explain this'],
    ['x', 'cut — remove this'], ['e', 'expand — go deeper'],
    ['n', 'note — context, no change asked'],
    ['a', 'approve — keep as-is'], ['f', 'feedback panel'],
    ['⌘ ⏎', 'copy feedback'], ['esc', 'close what is open']
  ]]
];
sheet.innerHTML =
  '<button class="close" id="sheet-x" aria-label="Close">✕</button><h3>Shortcuts</h3><div class="cols">' +
  SHEET.map(function(g){
    return '<div class="grp"><b>' + g[0] + '</b>' + g[1].map(function(r){
      return '<div class="row"><kbd>' + r[0] + '</kbd><span>' + r[1] + '</span></div>';
    }).join('') + '</div>';
  }).join('') + '</div>';
function toggleSheet(force){
  var on = force === undefined ? !sheet.classList.contains('show') : force;
  sheet.classList.toggle('show', on);
  sheetBg.classList.toggle('show', on);
}
document.getElementById('sheet-x').addEventListener('click', function(){ toggleSheet(false); });
sheetBg.addEventListener('click', function(){ toggleSheet(false); });
['keysbtn','keysbtn2'].forEach(function(id){
  var b = document.getElementById(id);
  if (b) b.addEventListener('click', function(){ toggleSheet(); });
});

/* ── keys (capture phase, so it wins over the review layer) ──────────── */
document.addEventListener('keydown', function(e){
  var t = e.target;
  var typing = /^(INPUT|TEXTAREA)$/.test(t.tagName) || t.isContentEditable;

  if (e.key === 'Escape'){
    if (sheet.classList.contains('show')){ toggleSheet(false); e.stopPropagation(); return; }
    if (searchOpen()){ closeSearch(); e.stopPropagation(); return; }
    return;
  }
  if ((e.metaKey || e.ctrlKey) && e.key === 'f'){
    e.preventDefault(); e.stopPropagation(); openSearch(); return;
  }
  if ((e.metaKey || e.ctrlKey) && e.key === '/'){
    e.preventDefault(); e.stopPropagation(); toggleSheet(); return;
  }
  if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === '/'){ e.preventDefault(); e.stopPropagation(); openSearch(); return; }
  if (e.key === 'o'){ e.preventDefault(); e.stopPropagation(); cycleMode(); return; }
}, true);

window.__mdUI = { setMode: setMode, openSearch: openSearch, closeSearch: closeSearch,
                  toggleSheet: toggleSheet, search: run, matches: function(){ return ranges.length; } };
})();
