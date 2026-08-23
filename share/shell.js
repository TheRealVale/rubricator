/* ── Shell ─────────────────────────────────────────────────────────────────
   The window, and nothing about what is in it. It owns the navigator, the
   panes and their tabs, the palette, the status strip and the keyboard map;
   it knows a *surface* only as an object that can render itself into a div
   and answer a few questions about what to call it.

   The one rule worth stating: a tab owns its DOM for as long as it lives.
   Switching tabs hides an element, it never rebuilds one — which is what
   lets a rendered document keep its annotations, its mermaid diagrams and
   its scroll position while you go and read something else.            */
(function(){
'use strict';
var $ = function(id){ return document.getElementById(id); };
function esc(s){ return String(s == null ? '' : s).replace(/[&<>"]/g, function(c){
  return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }

var APP = {};                 /* make · nav · search · menu · onFocus · spec */
var panes = [], focus = 0, MAXP = 3;
var navMode = 'docs', navRail = false, navW = 252;
var pal = { on:false, q:'', sel:0, kind:'', rows:[] };

/* ── panes and tabs ───────────────────────────────────────────────────── */
function key(kind, id){ return kind + ' ' + (id || ''); }
function pane(){ return panes[focus] || panes[0]; }
function tabOf(p){ return p && p.tabs[p.active]; }
function active(){ return tabOf(pane()); }

function locate(k){
  for (var i = 0; i < panes.length; i++)
    for (var j = 0; j < panes[i].tabs.length; j++)
      if (panes[i].tabs[j].key === k) return { p:i, t:j };
  return null;
}

function newPane(at){
  var p = { tabs:[], active:0, el:null, tabsEl:null, actsEl:null, bodyEl:null, grow:1 };
  p.el = document.createElement('section');
  p.el.className = 'pane';
  p.el.innerHTML = '<div class="tstrip"><div class="tabs"></div><div class="tacts"></div></div>' +
                   '<div class="pbody"></div>';
  p.tabsEl = p.el.querySelector('.tabs');
  p.actsEl = p.el.querySelector('.tacts');
  p.bodyEl = p.el.querySelector('.pbody');
  panes.splice(at == null ? panes.length : at, 0, p);
  layoutPanes();
  return p;
}

function layoutPanes(){
  var host = $('panes');
  host.innerHTML = '';
  panes.forEach(function(p, i){
    if (i){
      var rz = document.createElement('div');
      rz.className = 'rz';
      rz.dataset.pz = i;
      host.appendChild(rz);
    }
    p.el.style.flexGrow = p.grow;
    host.appendChild(p.el);
  });
}

/* the surface a tab shows is built once, on first sight, and kept */
function realise(p, t){
  if (t.el) return;
  t.el = document.createElement('div');
  t.el.className = 'surf';
  p.bodyEl.appendChild(t.el);
  try { t.surf.render(t.el); }
  catch(e){ t.el.innerHTML = '<div class="void">' + esc(e.message) + '</div>'; }
  t.dirty = false;
}

function show(p){
  p.tabs.forEach(function(t, i){
    var on = i === p.active;
    if (on){
      realise(p, t);
      if (t.dirty && t.surf.refresh){ t.surf.refresh(t.el); t.dirty = false; }
      if (!t.el.classList.contains('on')){
        t.el.classList.add('on');
        /* display:none drops the scroll position, so it is kept by hand */
        if (t.scroll) t.el.scrollTop = t.scroll;
      }
    } else if (t.el && t.el.classList.contains('on')){
      t.scroll = t.el.scrollTop;
      t.el.classList.remove('on');
    }
  });
}

function paint(){
  panes.forEach(function(p, i){
    p.el.classList.toggle('focus', i === focus);
    show(p);
    if (!p.tabs.length && !p.bodyEl.querySelector('.void'))
      p.bodyEl.innerHTML = '<div class="void">Nothing open here.<br>' +
        'Pick something on the left, or press &#8984;K.</div>';
    else if (p.tabs.length){
      var v = p.bodyEl.querySelector('.void');
      if (v) v.remove();
    }
    p.tabsEl.innerHTML = p.tabs.map(function(t, j){
      var L = label(t);
      return '<div class="tab' + (j === p.active ? ' on' : '') + '" data-t="' + j + '" data-p="' + i +
        '" title="' + esc(L.tip || L.title) + '">' +
        (L.kd ? '<span class="kd">' + esc(L.kd) + '</span>' : '') +
        '<span class="nm">' + esc(L.title) + '</span>' +
        (L.badge ? '<span class="n">' + esc(L.badge) + '</span>' : '') +
        '<button class="x" data-x="' + j + '" data-p="' + i + '" aria-label="Close">&#215;</button></div>';
    }).join('');
    acts(p);
  });
  status();
}

function label(t){
  var L = t.surf.label ? (t.surf.label() || {}) : {};
  return { title: L.title || t.title, kd: L.kd != null ? L.kd : t.kd,
           badge: L.badge != null ? L.badge : t.badge, tip: L.tip || t.tip };
}

function acts(p){
  var t = tabOf(p), list = (t && t.surf.actions) ? (t.surf.actions() || []) : [];
  p.actsEl.innerHTML = list.map(function(a, i){
    return '<button data-a="' + i + '" class="' + (a.cls || '') + '">' + esc(a.label) + '</button>';
  }).join('');
  p.actsEl._list = list;
}

/* ── the one way in ───────────────────────────────────────────────────── */
function open(spec, where){
  if (!spec) return null;
  var k = key(spec.kind, spec.id), at = locate(k);
  if (at){
    /* already open somewhere: go to it rather than opening a second copy */
    focus = at.p; panes[at.p].active = at.t;
    paint(); focused(); save();
    var got = panes[at.p].tabs[at.t];
    if (spec.then) spec.then(got, got.el);
    return got;
  }
  var p;
  if (where === 'split'){
    if (panes.length < MAXP){ newPane(focus + 1); focus = focus + 1; p = panes[focus]; }
    else { focus = (focus + 1) % panes.length; p = panes[focus]; }
  } else {
    p = pane();
  }
  var surf = APP.make(spec);
  if (!surf) return null;
  var t = { key:k, kind:spec.kind, id:spec.id, title:spec.title || spec.id || spec.kind,
            kd:spec.kd || '', badge:spec.badge || '', tip:spec.tip || '', surf:surf,
            el:null, scroll:0, dirty:false };
  p.tabs.push(t);
  p.active = p.tabs.length - 1;
  focus = panes.indexOf(p);
  paint(); focused(); save();
  if (spec.then) spec.then(t, t.el);
  return t;
}

function closeTab(pi, ti){
  var p = panes[pi], t = p && p.tabs[ti];
  if (!t) return;
  if (t.surf.close){ try { t.surf.close(t.el); } catch(e){} }
  if (t.el) t.el.remove();
  p.tabs.splice(ti, 1);
  if (p.active >= p.tabs.length) p.active = p.tabs.length - 1;
  if (p.active < 0) p.active = 0;
  if (!p.tabs.length && panes.length > 1){
    panes.splice(pi, 1);
    if (focus >= panes.length) focus = panes.length - 1;
    layoutPanes();
  }
  paint(); focused(); save();
}

function focusPane(i){
  if (i < 0 || i >= panes.length || i === focus) return;
  focus = i; paint(); focused(); save();
}
function focused(){
  var t = active();
  if (t){ realise(pane(), t); if (t.surf.focus){ try { t.surf.focus(t.el); } catch(e){} } }
  if (APP.onFocus) APP.onFocus(t || null);
  status();
}

/* everything on screen gets a chance to catch up with new data; a surface
   that is not visible is marked instead, and catches up when it is shown */
function refresh(){
  panes.forEach(function(p){
    p.tabs.forEach(function(t, i){
      if (!t.el) return;
      if (i === p.active && t.surf.refresh){ t.surf.refresh(t.el); t.dirty = false; }
      else t.dirty = true;
    });
  });
  nav(); paint();
}

/* ── the navigator ────────────────────────────────────────────────────── */
var NAVMODES = [
  { id:'docs', label:'Documents',
    icon:'<path d="M4 4h9l5 5v11H4z"/><path d="M13 4v5h5"/>' },
  { id:'sessions', label:'Sessions',
    icon:'<path d="M4 5h16v11H9l-5 4z"/>' },
  { id:'notes', label:'Notes',
    icon:'<path d="M5 4h14v16H5z"/><path d="M8 9h8M8 13h6"/>' }
];
function nav(){
  var n = $('nav');
  n.classList.toggle('rail', navRail);
  n.style.width = navRail ? '' : navW + 'px';
  $('nvmodes').innerHTML = NAVMODES.map(function(m){
    return '<button data-nm="' + m.id + '" class="' + (navMode === m.id ? 'on' : '') + '" title="' +
      m.label + '">' + (navRail ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + m.icon + '</svg>' : m.label) +
      '</button>';
  }).join('');
  if (navRail) return;
  var out = APP.nav ? (APP.nav(navMode) || {}) : {};
  var cur = $('nvq-i');
  var hadFocus = cur && document.activeElement === cur;
  var caret = hadFocus ? [cur.selectionStart, cur.selectionEnd] : null;
  $('nvq').innerHTML = out.filter == null ? '' :
    '<input id="nvq-i" placeholder="' + esc(out.placeholder || 'Filter') + '" value="' +
    esc(out.filter) + '" autocomplete="off" spellcheck="false">';
  $('nvbody').innerHTML = out.html || '';
  $('nvfoot').innerHTML = out.foot || '';
  var i = $('nvq-i');
  if (i){
    i.addEventListener('input', function(){ if (out.onFilter) out.onFilter(i.value); });
    if (hadFocus){ i.focus(); try { i.setSelectionRange(caret[0], caret[1]); } catch(e){} }
  }
}
function setNavMode(m){ navMode = m; navRail = false; nav(); save(); }
function toggleNav(){ navRail = !navRail; nav(); save(); }

/* ── the status strip ─────────────────────────────────────────────────── */
var statLeft = '';
function status(left){
  if (left != null) statLeft = left;
  $('stat-l').innerHTML = statLeft;
  var t = active();
  var hint = t && t.surf.hint ? (t.surf.hint() || '') : '';
  if (!hint) hint = panes.length > 1
    ? '&#8984;1 &#8984;2 focus pane &middot; &#8984;W close tab'
    : '&#8984;K find &middot; &#8984;\\ split &middot; &#8984;B navigator';
  $('stat-r').innerHTML = (panes.length > 1 ? 'pane ' + (focus + 1) + ' focused &middot; ' : '') + hint;
}

/* ── find anything ────────────────────────────────────────────────────── */
function palette(on, seed){
  pal.on = on !== false;
  $('pal').classList.toggle('on', pal.on);
  if (!pal.on) return;
  if (seed != null) pal.q = seed;
  pal.sel = 0;
  var i = $('pal-i');
  i.value = pal.q;
  palDraw();
  i.focus(); i.select();
}
function palDraw(){
  var res = APP.search ? (APP.search(pal.q, pal.kind) || {}) : {};
  var groups = res.groups || [];
  pal.rows = [];
  var out = [];
  groups.forEach(function(g){
    if (!g.rows || !g.rows.length) return;
    out.push('<div class="grp">' + esc(g.label) + '</div>');
    g.rows.forEach(function(r){
      var i = pal.rows.length;
      pal.rows.push(r);
      out.push('<div class="row" data-r="' + i + '">' +
        '<span class="kind">' + esc(r.kind) + '</span>' +
        '<span class="nm">' + (r.html || esc(r.title)) + '</span>' +
        (r.sub ? '<span class="sub">' + esc(r.sub) + '</span>' : '') +
        '<span class="go">&crarr;</span></div>');
    });
  });
  $('pal-list').innerHTML = out.length ? out.join('')
    : '<div class="none">' + (pal.q ? 'Nothing matched &ldquo;' + esc(pal.q) + '&rdquo;.'
        : 'Documents, sessions, your notes, and the surfaces of this window.') + '</div>';
  $('pal-count').textContent = res.count || '';
  $('pal-kinds').innerHTML = (res.kinds || []).map(function(k){
    return '<button data-pk="' + esc(k) + '" class="' + (pal.kind === k ? 'on' : '') + '">' +
      esc(k) + '</button>';
  }).join('');
  palSel(0);
}
function palSel(i){
  var rows = $('pal-list').querySelectorAll('.row');
  if (!rows.length){ pal.sel = 0; return; }
  pal.sel = Math.max(0, Math.min(rows.length - 1, i));
  [].forEach.call(rows, function(r, j){ r.classList.toggle('on', j === pal.sel); });
  rows[pal.sel].scrollIntoView({ block:'nearest' });
}
function palRun(split){
  var r = pal.rows[pal.sel];
  if (!r) return;
  palette(false);
  if (r.run) return r.run(split);
  open(r.open || r, split ? 'split' : 'here');
}

/* ── the surface menu ─────────────────────────────────────────────────── */
function menu(){
  var m = $('more');
  if (m){ m.remove(); return; }
  var items = APP.menu ? APP.menu() : [];
  m = document.createElement('div');
  m.id = 'more';
  m.innerHTML = items.map(function(it, i){
    return it.sep ? '<div class="sep"></div>'
      : '<button data-m="' + i + '">' + esc(it.label) +
        (it.key ? '<span class="k">' + esc(it.key) + '</span>' : '') + '</button>';
  }).join('');
  $('app').appendChild(m);
  m._items = items;
}

/* ── dragging the dividers ────────────────────────────────────────────── */
function dragging(rz, e){
  var isNav = rz.id === 'navrz';
  var x0 = e.clientX, a, b, w0 = 0, aw = 0, bw = 0, i = 0;
  if (isNav){
    if (navRail) return;
    a = $('nav'); w0 = a.getBoundingClientRect().width;
  } else {
    i = +rz.dataset.pz;
    if (!panes[i - 1] || !panes[i]) return;
    a = panes[i - 1].el; b = panes[i].el;
    aw = a.getBoundingClientRect().width; bw = b.getBoundingClientRect().width;
  }
  document.body.classList.add('resizing');
  rz.classList.add('act');
  function move(ev){
    var d = ev.clientX - x0;
    if (isNav){
      navW = Math.max(168, Math.min(480, Math.round(w0 + d)));
      a.style.width = navW + 'px';
    } else {
      var na = Math.max(220, aw + d), nb = Math.max(220, bw - d), tot = na + nb;
      panes[i - 1].grow = na / tot * 2;
      panes[i].grow = nb / tot * 2;
      a.style.flexGrow = panes[i - 1].grow;
      b.style.flexGrow = panes[i].grow;
    }
  }
  function up(){
    document.removeEventListener('mousemove', move);
    document.removeEventListener('mouseup', up);
    document.body.classList.remove('resizing');
    rz.classList.remove('act');
    save();
  }
  document.addEventListener('mousemove', move);
  document.addEventListener('mouseup', up);
  e.preventDefault();
}

/* ── the layout survives a reload ─────────────────────────────────────── */
var KEY = '';
function save(){
  if (!KEY) return;
  try {
    localStorage.setItem(KEY, JSON.stringify({
      nav:{ mode:navMode, rail:navRail, w:navW }, focus:focus,
      panes: panes.map(function(p){
        return { active:p.active, grow:p.grow,
                 tabs:p.tabs.filter(function(t){ return t.surf.keep !== false; })
                            .map(function(t){ return { kind:t.kind, id:t.id }; }) };
      })
    }));
  } catch(e){}
}
function stored(){
  if (!KEY) return null;
  try { return JSON.parse(localStorage.getItem(KEY) || 'null'); } catch(e){ return null; }
}

/* ── wiring ───────────────────────────────────────────────────────────── */
function wire(){
  $('panes').addEventListener('mousedown', function(e){
    var rz = e.target.closest('.rz');
    if (rz) return dragging(rz, e);
    var el = e.target.closest('.pane');
    if (!el) return;
    var i = panes.map(function(p){ return p.el; }).indexOf(el);
    if (i >= 0 && i !== focus) focusPane(i);
  });
  $('navrz').addEventListener('mousedown', function(e){ dragging($('navrz'), e); });

  $('panes').addEventListener('click', function(e){
    var x = e.target.closest('[data-x]');
    if (x){ e.stopPropagation(); return closeTab(+x.dataset.p, +x.dataset.x); }
    var tb = e.target.closest('.tab');
    if (tb){
      var pi = +tb.dataset.p, ti = +tb.dataset.t;
      panes[pi].active = ti; focus = pi;
      paint(); focused(); save();
      return;
    }
    var a = e.target.closest('[data-a]');
    if (a){
      var host = a.closest('.tacts'), act = (host._list || [])[+a.dataset.a];
      if (act && act.fn) act.fn();
    }
  });

  $('nav').addEventListener('click', function(e){
    var m = e.target.closest('[data-nm]');
    if (m) return setNavMode(m.dataset.nm);
  });

  $('pal').addEventListener('mousedown', function(e){
    if (e.target === $('pal')) palette(false);
  });
  $('pal').addEventListener('click', function(e){
    var k = e.target.closest('[data-pk]');
    if (k){ pal.kind = pal.kind === k.dataset.pk ? '' : k.dataset.pk; palDraw(); $('pal-i').focus(); return; }
    var r = e.target.closest('[data-r]');
    if (r){ pal.sel = +r.dataset.r; return palRun(e.metaKey || e.ctrlKey); }
  });
  $('pal-i').addEventListener('input', function(){ pal.q = $('pal-i').value; palDraw(); });
  $('pal-i').addEventListener('keydown', function(e){
    if (e.key === 'ArrowDown'){ e.preventDefault(); return palSel(pal.sel + 1); }
    if (e.key === 'ArrowUp'){ e.preventDefault(); return palSel(pal.sel - 1); }
    if (e.key === 'Enter'){ e.preventDefault(); return palRun(e.metaKey || e.ctrlKey); }
    if (e.key === 'Escape'){ e.preventDefault(); return palette(false); }
    if (e.key === 'Tab'){
      e.preventDefault();
      var ks = [].map.call($('pal-kinds').children, function(b){ return b.dataset.pk; });
      ks.push('');
      var i = ks.indexOf(pal.kind);
      pal.kind = ks[(i + 1) % ks.length];
      return palDraw();
    }
  });

  document.addEventListener('click', function(e){
    var m = $('more');
    if (!m) return;
    var mi = e.target.closest('[data-m]');
    if (mi){
      var it = (m._items || [])[+mi.dataset.m];
      m.remove();
      if (it && it.run) it.run();
      return;
    }
    if (!e.target.closest('#more') && !e.target.closest('#morebtn')) m.remove();
  });
  $('morebtn').addEventListener('click', function(e){ e.stopPropagation(); menu(); });
  $('findbtn').addEventListener('click', function(){ palette(true); });
  $('navbtn').addEventListener('click', toggleNav);

  document.addEventListener('keydown', function(e){
    var meta = e.metaKey || e.ctrlKey;
    if (pal.on){ if (e.key === 'Escape'){ e.preventDefault(); palette(false); } return; }
    if (meta && !e.altKey && (e.key === 'k' || e.key === 'K')){ e.preventDefault(); return palette(true); }
    if (!meta) return;
    if (e.altKey){
      if (e.code === 'BracketLeft'){ e.preventDefault(); return step(-1); }
      if (e.code === 'BracketRight'){ e.preventDefault(); return step(1); }
      return;
    }
    if (e.key === 'b' || e.key === 'B'){ e.preventDefault(); return toggleNav(); }
    if (e.key === 'e' || e.key === 'E'){
      e.preventDefault();
      var ids = NAVMODES.map(function(m){ return m.id; });
      return setNavMode(ids[(ids.indexOf(navMode) + 1) % ids.length]);
    }
    if (e.key === '\\'){ e.preventDefault(); return split(); }
    if (e.key === 'w' || e.key === 'W'){
      e.preventDefault();
      if (active()) return closeTab(focus, pane().active);
      if (panes.length > 1){                      /* an empty pane closes itself */
        panes.splice(focus, 1);
        if (focus >= panes.length) focus = panes.length - 1;
        layoutPanes(); paint(); focused(); save();
      }
      return;
    }
    if (/^[1-9]$/.test(e.key)){
      var n = +e.key - 1;
      if (n < panes.length){ e.preventDefault(); focusPane(n); }
    }
  }, true);
}
function step(d){
  var p = pane();
  if (p.tabs.length < 2) return;
  p.active = (p.active + d + p.tabs.length) % p.tabs.length;
  paint(); focused(); save();
}
function split(){
  if (panes.length >= MAXP || !active()) return null;
  newPane(focus + 1);
  focus = focus + 1;
  paint(); focused(); save();
  return panes[focus];
}

window.Shell = {
  init: function(cfg){
    APP = cfg || {};
    KEY = cfg.storeKey || '';
    var L = cfg.noRestore ? null : stored();
    if (L && L.nav){
      navMode = L.nav.mode || navMode;
      navRail = !!L.nav.rail;
      navW = L.nav.w || navW;
    }
    wire();
    var opened = 0;
    if (L && L.panes && L.panes.length){
      L.panes.slice(0, MAXP).forEach(function(sp){
        var p = newPane();
        p.grow = sp.grow || 1;
        focus = panes.length - 1;
        (sp.tabs || []).forEach(function(t){
          var spec = APP.spec ? APP.spec(t.kind, t.id) : null;
          if (spec && open(spec, 'here')) opened++;
        });
      });
      /* a pane whose tabs all failed to come back is not worth keeping */
      panes = panes.filter(function(p){ return p.tabs.length; });
      if (!panes.length){ panes = []; newPane(); }
      layoutPanes();
      focus = Math.min(L.focus || 0, panes.length - 1);
      panes.forEach(function(p, i){
        var a = (L.panes[i] || {}).active;
        if (a != null && a < p.tabs.length) p.active = a;
      });
    } else {
      newPane();
    }
    nav(); paint(); focused();
    return opened;
  },
  open: open, close: closeTab, split: split, refresh: refresh, paint: paint,
  nav: nav, navMode: function(){ return navMode; }, setNavMode: setNavMode,
  status: status, palette: palette, focused: focused,
  active: active, panes: function(){ return panes; }, focusIndex: function(){ return focus; },
  each: function(fn){
    panes.forEach(function(p, i){
      p.tabs.forEach(function(t, j){ fn(t, i === focus && j === p.active, p, i); });
    });
  },
  save: save
};
})();
