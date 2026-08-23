/* rubricator workspace — search a repo's markdown, its git activity and your own sessions. */
(function(){
"use strict";
var D = JSON.parse(document.getElementById('wsdata').textContent);
var $ = function(id){ return document.getElementById(id); };
var DAY = 86400;
var now = Math.floor(Date.now() / 1000);

/* ── the live tier ─────────────────────────────────────────────────────────
   Served from 127.0.0.1, the page can fetch what it needs instead of carrying
   it. Everything below degrades to the static behaviour when there is no
   server, so one code path covers both. */
var CAPS = D.caps || {}, BASE = D.base || '';
function can(c){ return !!CAPS[c]; }
function api(path, body, cb, fail){
  if (!BASE) return fail && fail();
  var o = { method: body === undefined ? 'GET' : 'POST', headers: {'Content-Type':'application/json'} };
  if (body !== undefined) o.body = JSON.stringify(body);
  fetch(BASE + '/' + path, o)
    .then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); })
    /* two-argument then, not .catch: a bug thrown inside cb must not be
       reported back as "the server failed" and run the failure path too */
    .then(function(j){ try { cb && cb(j); } catch(e){ console.error('rubricator:', e); } },
          function(){ try { fail && fail(); } catch(e){} });
}

/* document bodies are left on disk in the live tier and pulled in when a
   document is actually opened — or all at once, the first time you search */
var textAll = false;
function ensureText(rels, cb){
  var need = rels.filter(function(r){
    var d = docBy(r);
    return d && d.text == null;
  });
  if (!can('text') || !need.length) return cb();
  api('text', { rels: need }, function(j){
    absorb(j); cb();
  }, cb);
}
function ensureAllText(cb){
  if (textAll || !can('text')) { textAll = true; return cb(); }
  api('text', { rels: [] }, function(j){
    absorb(j);
    textAll = true; cb();
  }, cb);
}
function docBy(rel){ return D.docs.filter(function(x){ return x.rel === rel; })[0]; }
/* the server answers with the text and, for anything it had to extract, what it
   learned on the way — a page count, a word count, or why there was nothing */
function absorb(j){
  var text = (j && j.text) || j || {}, meta = (j && j.meta) || {};
  for (var rel in text){ var d = docBy(rel); if (d) d.text = text[rel]; }
  for (var r2 in meta){
    var e = docBy(r2); if (!e) continue;
    for (var k in meta[r2]) e[k] = meta[r2][k];
  }
}

/* A verb and an id — never a path, never a command. The server resolves the
   rest against the index it already holds. */
function act(verb, id, text, ok){
  if (!can('launch')) return toast('actions are off — start with md --allow-launch');
  api('act', { verb: verb, id: id, text: text || '' }, function(j){
    if (j && j.error) return toast(j.error);
    toast((ok || 'done') + (j && j.terminal ? ' — ' + j.terminal : ''));
  }, function(){ toast(verb + ' failed'); });
}

/* notes: the server owns them when there is one, and the browser's copy is
   kept in step so the same notes show up if you open the file on its own */
var DISK = D.notes || {};
if (can('notes') && window.MDReview){
  window.MDReview.storage.get = function(key, path){
    var mine = null, theirs = DISK[path] || null;
    try { mine = JSON.parse(localStorage.getItem(key) || 'null'); } catch(e){}
    if (!theirs) { if (mine) pushUp(path, mine); return mine; }
    if (!mine) return theirs;
    if ((mine.saved || 0) > (theirs.saved || 0)){ pushUp(path, mine); return mine; }
    return theirs;
  };
  /* notes taken in the standalone reader only reach the browser; the first time
     the workspace sees a newer local copy it carries it up to the repo */
  function pushUp(path, store){
    if (!store || !store.items || !store.items.length) return;
    DISK[path] = store;
    api('notes', { path: path, store: store });
  }
  window.MDReview.storage.set = function(key, val, path){
    try { localStorage.setItem(key, JSON.stringify(val)); } catch(e){}
    DISK[path] = val;
    clearTimeout(window.__noteT);
    window.__noteT = setTimeout(function(){
      api('notes', { path: path, store: val }, null, function(){ toast('note not saved to disk'); });
    }, 400);
  };
}

/* every note changes two things outside the tray: the count on the tab it was
   written on, and the navigator. Whoever stores it, the window is told. */
if (window.MDReview){
  var _set = window.MDReview.storage.set;
  window.MDReview.storage.set = function(key, val, path){
    _set.call(this, key, val, path);
    clearTimeout(window.__markT);
    window.__markT = setTimeout(function(){
      if (window.Shell){ Shell.paint(); Shell.nav(); }
    }, 60);
  };
}

/* annotations live in the reader's local storage, keyed by a hash of the abs path */
function hash(s){ var h=5381,i=s.length; while(i) h=(h*33^s.charCodeAt(--i))>>>0; return h.toString(36); }
function annosFor(doc){
  try {
    var raw = localStorage.getItem('md-review:' + hash(doc.abs));
    if (!raw) return [];
    var st = JSON.parse(raw);
    return (st.items || []).map(function(i){ i._doc = doc; return i; });
  } catch(e){ return []; }
}
function allAnnos(){
  return D.docs.reduce(function(acc, d){ return acc.concat(annosFor(d)); }, []);
}

/* ── helpers ──────────────────────────────────────────────────────────── */
function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g,function(c){
  return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }
function ago(ts){
  if (!ts) return '—';
  var d = Math.round((now - ts) / DAY);
  if (d < 1) return 'today';
  if (d < 30) return d + 'd';
  if (d < 365) return Math.round(d/30) + 'mo';
  return (d/365).toFixed(1) + 'y';
}
function toast(m){ var t=$('toast'); t.textContent=m; t.classList.add('show');
  clearTimeout(t._x); t._x=setTimeout(function(){ t.classList.remove('show'); },1900); }
function copy(text){
  if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).catch(fb);
  else fb();
  function fb(){ var a=document.createElement('textarea'); a.value=text; a.style.position='fixed';
    a.style.top='-1000px'; document.body.appendChild(a); a.select();
    try{ document.execCommand('copy'); }catch(e){} a.remove(); }
}
function snippet(text, q, len){
  text = text || '';
  if (!q) return esc(text.slice(0, len || 150).trim());
  var i = text.toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return esc(text.slice(0, len || 150).trim());
  var a = Math.max(0, i - 60), b = Math.min(text.length, i + q.length + (len || 110));
  return (a ? '…' : '') + esc(text.slice(a, i)) + '<mark>' + esc(text.slice(i, i+q.length)) +
         '</mark>' + esc(text.slice(i+q.length, b)) + (b < text.length ? '…' : '');
}
function count(text, q){
  if (!q || !text) return 0;
  var n = 0, i = 0, t = text.toLowerCase(), s = q.toLowerCase();
  while ((i = t.indexOf(s, i)) >= 0){ n++; i += s.length; }
  return n;
}

/* ── the topic join ───────────────────────────────────────────────────── */
function promptHits(q){
  if (!D.withSessions || !q) return [];
  return D.prompts.filter(function(p){ return count(p.text, q) > 0; })
                  .sort(function(a,b){ return b.t - a.t; });
}
/* rank files by how *concentrated* they are in the matching sessions —
   presence alone returns everything a session happened to touch */
function fileRank(sids, weights, q){
  /* hits²/df, not Σ1/df: the plain ratio saturates — one hit in one session ties
     with three in three, and the tie then breaks arbitrarily. Squaring the
     numerator rewards files that keep coming back across the matching sessions
     while still punishing files every session happens to touch. */
  var set = {}, out = [], ql = (q || '').toLowerCase();
  sids.forEach(function(s){ set[s] = 1; });
  for (var k in D.touches){
    var df = D.touches[k].length, hits = 0, weight = 0;
    D.touches[k].forEach(function(s){
      if (!set[s]) return;
      hits++;
      weight += (weights && weights[s]) || 1;   // a session that asked 12 times counts more than one that asked once
    });
    if (!hits) continue;
    var score = (weight * hits) / df;
    if (ql && k.toLowerCase().indexOf(ql) >= 0) score *= 4;   // the name itself is evidence
    out.push({ file: k, hits: hits, df: df, s: score, here: k.indexOf(D.root + '/') === 0 });
  }
  out.sort(function(a,b){ return b.s - a.s || b.hits - a.hits; });
  return out;
}
function baseName(rel){ return rel.split('/').pop(); }
function docScore(d, q){
  /* the name counts, and counts most: someone typing "workspace-plan" is naming
     a file, not describing a topic. It is also known before the body arrives. */
  return count(baseName(d.rel), q) * 14
       + count(d.rel, q) * 6
       + count(d.title, q) * 8
       + d.headings.reduce(function(a,h){ return a + count(h.text, q) * 4; }, 0)
       + count(d.text, q);
}
function nameHit(d, q){ return !!q && count(d.rel, q) > 0; }
/* headings and titles are in the page from the start, so a search answers
   immediately and deepens once the bodies land */
function searching(){ return can('text') && !textAll && !!query; }

/* ── views ────────────────────────────────────────────────────────────── */
var query = '', navQ = '', navOpts = false;
var libSort = 'recent', libFlat = false, libFacet = {}, libOpen = {};
var sesScope = 'here', sesLive = false, sesQuery = '';
/* which document a row is: the one you are reading is marked, the ones
   sitting in other tabs are marked more quietly, so a split never loses
   track of itself. Both are recomputed once per navigator render. */
var OPENSET = {}, CURREL = '';
function marks(){ OPENSET = openRels(); CURREL = curRel(); }
function shortRepo(p){ return (p || '?').split('/').pop() || '?'; }

var ROOTS = D.roots || [D.root];
function shortPath(p){
  for (var i = 0; i < ROOTS.length; i++){
    if (p.indexOf(ROOTS[i] + '/') === 0) return p.slice(ROOTS[i].length + 1);
  }
  return p.replace(/^\/Users\/[^/]+/, '~');
}

function viewSearch(){
  var q = query.trim(), out = [];
  out.push('<div class="qbox"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.6-3.6"/></svg>' +
    '<input id="q" placeholder="Search ' + D.docs.length + ' documents' +
    (D.withSessions ? ' and ' + D.prompts.length + ' prompts' : '') + '…" value="' + esc(query) + '" autocomplete="off" spellcheck="false">' +
    '<span class="hint">/ to focus</span></div>');
  if (!q){
    out.push('<div class="empty">Type to search across every markdown file in this repo' +
      (D.withSessions ? ', and across every prompt you have ever written' : '') + '.<br><br>' +
      'A topic resolves to <b>documents</b>, the <b>sessions</b> that discussed it, and the <b>files</b> those sessions changed.</div>');
    return out.join('');
  }
  var docs = D.docs.map(function(d){ return { d: d, s: docScore(d, q) }; })
                   .filter(function(x){ return x.s > 0; })
                   .sort(function(a,b){ return b.s - a.s; });
  var prompts = promptHits(q);
  var sids = {}; prompts.forEach(function(p){ if (p.sid) sids[p.sid] = (sids[p.sid] || 0) + 1; });
  var ranked = D.withSessions ? fileRank(Object.keys(sids), sids, q) : [];
  var files = ranked.filter(function(f){ return f.here; }).slice(0, 10);
  var elsewhere = ranked.filter(function(f){ return !f.here; }).slice(0, 6);
  var projects = {}; prompts.forEach(function(p){ projects[p.project.split('/').pop() || '?'] = 1; });

  if (searching()) out.push('<div class="qnote">Searching titles and headings — ' +
    'fetching the full text…</div>');
  out.push('<div class="qnote">' + docs.length + ' documents · ' + prompts.length + ' prompts · ' +
    Object.keys(sids).length + ' sessions' +
    (Object.keys(projects).length > 1 ? ' · <b>' + Object.keys(projects).length + ' repos</b>' : '') + '</div>');

  if (docs.length){
    out.push('<div class="grp">Documents <span class="c">' + docs.length + '</span></div>');
    docs.slice(0, 25).forEach(function(x){
      var an = annosFor(x.d).filter(function(i){ return i.state !== 'stale'; }).length;
      out.push('<div class="row" data-doc="' + esc(x.d.rel) + '" data-q="' + esc(q) + '">' +
        '<div class="t">' + esc(x.d.title) + '<span class="p">' + esc(x.d.rel) + '</span></div>' +
        '<div class="snip">' + snippet(x.d.text, q) + '</div>' +
        '<div class="meta">' +
        (nameHit(x.d, q) ? '<span class="pill">name</span>' : '') +
        '<span>' + count(x.d.text, q) + ' in the text</span><span>' + x.d.words + ' words</span>' +
        '<span>touched ' + ago(x.d.mtime) + ' ago</span>' +
        (an ? '<span class="pill ok">' + an + ' note' + (an>1?'s':'') + '</span>' : '') + '</div></div>');
    });
  }
  if (prompts.length){
    out.push('<div class="grp">You asked about this <span class="c">' + prompts.length + ' prompts</span></div>');
    prompts.slice(0, 12).forEach(function(p){
      var known = p.sid && D.sessions[p.sid];
      out.push('<div class="row"' + (known ? ' data-ses="' + esc(p.sid) + '" data-q="' + esc(q) + '"' : ' style="cursor:default"') + '>' +
        '<div class="snip">' + snippet(p.text, q, 240) + '</div>' +
        '<div class="meta"><span>' + esc((p.project||'').split('/').pop()) + '</span><span>' + ago(p.t) + ' ago</span>' +
        (known ? '<span class="pill ok">open the session</span>' : '') + '</div></div>');
    });
  }
  function fileTable(list, title, note){
    if (!list.length) return;
    out.push('<div class="grp">' + title + ' <span class="c">' + note + '</span></div>');
    out.push('<table class="ws"><thead><tr><th>File</th><th class="num">in these</th><th class="num">overall</th></tr></thead><tbody>');
    list.forEach(function(f){
      out.push('<tr><td class="f">' + esc(shortPath(f.file)) + '</td><td class="num">' + f.hits +
               '</td><td class="num" style="color:var(--fg-dim)">' + f.df + '</td></tr>');
    });
    out.push('</tbody></table>');
  }
  fileTable(files, 'Code those sessions changed', 'in this repo · ranked by how specific it is to this topic');
  fileTable(elsewhere, 'Solved elsewhere before', 'other repos · same topic');
  if (!docs.length && !prompts.length) out.push('<div class="empty">Nothing matched.</div>');
  else out.push('<div class="act"><button id="dossier">Copy dossier for your agent</button>' +
    '<button class="ghost" id="dossier-what">what goes in it?</button></div>');
  return out.join('');
}

function noteCount(d){
  return annosFor(d).filter(function(i){ return i.state !== 'stale'; }).length;
}
function isStale(d){
  if (d.kind && d.kind !== 'md') return false;   // a contract does not go stale
  var s = D.stale[d.rel];
  return !!(s && s.targetChurn > 0);
}
var LIBSORT = {
  recent: function(a,b){ return b.mtime - a.mtime; },
  stale:  function(a,b){ return ((D.stale[b.rel]||{}).targetChurn||0) - ((D.stale[a.rel]||{}).targetChurn||0); },
  notes:  function(a,b){ return noteCount(b) - noteCount(a); },
  size:   function(a,b){ return b.words - a.words; },
  title:  function(a,b){ return a.rel.localeCompare(b.rel); }
};
function libDocs(){
  var out = D.docs.slice();
  if (libFacet.notes) out = out.filter(function(d){ return noteCount(d) > 0; });
  if (libFacet.stale) out = out.filter(isStale);
  if (libFacet.recent) out = out.filter(function(d){ return now - d.mtime < 14 * DAY; });
  return out.sort(LIBSORT[libSort] || LIBSORT.recent);
}
function fileRow(d){
  var n = noteCount(d), st = D.stale[d.rel] || {};
  var mark = d.kind === 'pdf' ? 'PDF' : (d.kind === 'word' ? 'DOC' : '');
  return '<div class="tfile' + (CURREL === d.rel ? ' on' : (OPENSET[d.rel] ? ' open' : '')) +
    '" data-doc="' + esc(d.rel) + '">' +
    '<span class="nm">' + esc(d.rel.split('/').pop()) + '</span>' +
    (mark ? '<span class="kind">' + mark + '</span>' : '') +
    (n ? '<span class="n">' + n + '</span>' : '') +
    (isStale(d) ? '<span class="sub w" title="code it describes moved on">⚠</span>' : '') +
    (d.pages ? '<span class="sub">' + d.pages + 'p</span>' : '') +
    (libSort === 'size' && d.words ? '<span class="sub">' + d.words + 'w</span>' : '') +
    '<span class="sub">' + ago(d.mtime) + '</span></div>';
}
function libTree(docs){
  var root = { dirs:{}, files:[] };
  docs.forEach(function(d){
    var parts = d.rel.split('/'), node = root;
    for (var i = 0; i < parts.length - 1; i++){
      var key = parts.slice(0, i + 1).join('/');
      node = node.dirs[parts[i]] || (node.dirs[parts[i]] = { dirs:{}, files:[], path:key });
      node.n = (node.n || 0) + 1;
    }
    node.files.push(d);
  });
  function walk(node){
    var out = [];
    Object.keys(node.dirs).sort().forEach(function(name){
      var dir = node.dirs[name], shut = libOpen[dir.path] === false;
      out.push('<div class="tdir' + (shut ? ' closed' : '') + '" data-dir="' + esc(dir.path) + '">' +
        '<span class="caret">▼</span>' + esc(name) + '<span class="c">' + dir.n + '</span></div>');
      if (!shut) out.push('<div class="tkids">' + walk(dir) + '</div>');
    });
    node.files.forEach(function(d){ out.push(fileRow(d)); });
    return out.join('');
  }
  return walk(root);
}
function viewStale(){
  if (!D.hasGit) return '<div class="empty">No git history here, so there is nothing to compare documents against.</div>';
  var rows = D.docs.map(function(d){ return { d: d, s: D.stale[d.rel] || {} }; })
    .filter(function(x){ return (x.s.targetChurn || 0) > 0 && (now - (x.s.last||0)) > 30*DAY; })
    .sort(function(a,b){ return b.s.targetChurn - a.s.targetChurn; });
  if (!rows.length) return '<div class="empty">Nothing looks stale — every document that names code has been touched since that code last changed.</div>';
  var out = ['<div class="qnote">Documents whose named files kept changing after the document stopped. ' +
    'Churn is counted only in the files each document actually mentions or links.</div>',
    '<table class="ws"><thead><tr><th>Document</th><th class="num">untouched</th>' +
    '<th class="num">commits since</th><th class="num">files named</th></tr></thead><tbody>'];
  rows.slice(0, 40).forEach(function(x){
    var hot = x.s.targetChurn > 150 ? 'hot' : 'warn';
    out.push('<tr data-doc="' + esc(x.d.rel) + '"><td><b>' + esc(x.d.title) + '</b><br>' +
      '<span class="f" style="color:var(--fg-dim)">' + esc(x.d.rel) + '</span></td>' +
      '<td class="num"><span class="pill ' + hot + '">' + ago(x.s.last) + '</span></td>' +
      '<td class="num">' + x.s.targetChurn + '</td><td class="num" style="color:var(--fg-dim)">' +
      (x.s.targets||[]).length + '</td></tr>');
  });
  return out.join('') + '</tbody></table>';
}

function viewNotes(){
  var items = allAnnos();
  if (!items.length) return '<div class="empty">No annotations yet.<br><br>' +
    'Open a document with <span class="f">md &lt;file&gt;</span>, mark it up, and your notes show up here — ' +
    'across every document in the repo.</div>';
  var open = items.filter(function(i){ return i.state !== 'stale'; });
  var out = ['<div class="qnote">' + open.length + ' open · ' + (items.length - open.length) + ' resolved</div>'];
  var byVerb = {};
  open.forEach(function(i){ (byVerb[i.verb] = byVerb[i.verb] || []).push(i); });
  ['change','question','cut','expand','note','approve'].forEach(function(v){
    var list = byVerb[v]; if (!list) return;
    out.push('<div class="grp">' + v + ' <span class="c">' + list.length + '</span></div>');
    list.forEach(function(i){
      out.push('<div class="row" data-doc="' + esc(i._doc.rel) + '" data-line="' +
        (i.lineStart || 0) + '">' +
        '<div class="t">' + esc(i.heading || i._doc.title) + '<span class="p">' + esc(i._doc.rel) +
        ':' + i.lineStart + '</span></div>' +
        (i.note ? '<div class="snip">' + esc(i.note) + '</div>' : '') + '</div>');
    });
  });
  return out.join('');
}

function inRepo(path){
  for (var i = 0; i < ROOTS.length; i++){
    if (path === ROOTS[i] || (path || '').indexOf(ROOTS[i] + '/') === 0) return true;
  }
  return false;
}
/* every prompt of a session, so a conversation can be found by anything said in it */
var byS = null;
function promptsOf(sid){
  if (!byS){
    byS = {};
    D.prompts.forEach(function(p){ if (p.sid) (byS[p.sid] = byS[p.sid] || []).push(p); });
  }
  return byS[sid] || [];
}
function sessionScore(sid, m, q){
  var n = count(m.t || '', q) * 6 + count(shortPath(m.p || ''), q) * 3, best = null, hits = 0;
  promptsOf(sid).forEach(function(p){
    var c = count(p.text, q);
    if (!c) return;
    hits += c;
    if (!best || c > best.c) best = { p: p, c: c };
  });
  return { s: n + hits, hits: hits, best: best };
}
function sessionList(scope){
  scope = scope || sesScope;
  var q = sesQuery.trim(), out = [];
  for (var sid in D.sessions){
    var m = D.sessions[sid];
    if (sesLive && !m.live) continue;
    if (scope === 'here' && !inRepo(m.p)) continue;
    if (q){
      var r = sessionScore(sid, m, q);
      if (!r.s) continue;
      out.push({ sid: sid, m: m, s: r.s, hits: r.hits, best: r.best });
    } else {
      out.push({ sid: sid, m: m, s: 0 });
    }
  }
  return out.sort(q ? function(a, b){ return b.s - a.s || b.m.b - a.m.b; }
                    : function(a, b){ return b.m.b - a.m.b; });
}
function dayLabel(ts){
  var d = Math.floor((now - ts) / DAY);
  if (d < 1) return 'Today';
  if (d < 2) return 'Yesterday';
  if (d < 8) return 'This week';
  if (d < 31) return 'This month';
  if (d < 366) return Math.round(d / 30) + ' months ago';
  return 'Older';
}
function span(m){
  if (!m.a || !m.b || m.b - m.a < 3600) return ago(m.b) + ' ago';
  var days = Math.round((m.b - m.a) / DAY);
  return days >= 1 ? days + 'd span' : Math.round((m.b - m.a) / 3600) + 'h span';
}
/* B6 — the correlation run backwards: a session touched files, and documents
   name the files they describe, so the overlap says which docs it bears on */
function relatedDocs(sid){
  var m = D.sessions[sid];
  if (!m || !m.files || !m.files.length) return [];
  var here = {}, pre = D.root + '/';
  m.files.forEach(function(f){ if (f.indexOf(pre) === 0) here[f.slice(pre.length)] = 1; });
  var out = [];
  D.docs.forEach(function(d){
    var t = (D.stale[d.rel] || {}).targets || [], hit = 0;
    t.forEach(function(x){ if (here[x]) hit++; });
    var own = here[d.rel] ? 3 : 0;              // the session edited the document itself
    if (hit || own) out.push({ d: d, hit: hit, own: !!own, s: hit + own });
  });
  return out.sort(function(a, b){ return b.s - a.s; }).slice(0, 8);
}

/* the body of a session surface: what it was, how to pick it up, what it
   touched, and everything you said in it */
function sessionHTML(sid, q){
  var m = D.sessions[sid];
  if (!m) return '<div class="empty">That session is not in the index.</div>';
  q = q || '';
  var mine = D.prompts.filter(function(p){ return p.sid === sid; })
                      .sort(function(a, b){ return a.t - b.t; });
  var docs = relatedDocs(sid);
  var pre = D.root + '/';
  var here = (m.files || []).filter(function(f){ return f.indexOf(pre) === 0; });
  var away = (m.files || []).filter(function(f){ return f.indexOf(pre) !== 0; });

  var out = ['<h3>' + esc(m.t || '(no prompt recorded)') + '</h3>',
    '<div class="who">' +
      '<span><span class="dot ' + (m.live ? 'live' : 'arch') + '"></span> ' +
        (m.live ? 'resumable' : 'archived — transcript gone') + '</span>' +
      '<span>' + esc((m.p || 'unknown project').replace(/^\/Users\/[^/]+/, '~')) + '</span>' +
      '<span>' + m.n + ' prompts</span><span>' + span(m) + '</span>' +
      '<span>last active ' + ago(m.b) + ' ago</span></div>'];

  if (m.live && can('launch')){
    out.push('<div class="grp">Pick it up</div>',
      '<div class="act"><button data-act="resume" data-id="' + esc(sid) + '">Resume this session</button>' +
      '<button class="ghost" data-act="fork" data-id="' + esc(sid) + '">Fork it</button></div>',
      '<div class="qnote" style="margin-top:9px">Resume continues the conversation where it ' +
      'stopped. Fork branches off without disturbing the original.</div>',
      '<div class="grp">or by hand</div>',
      '<div class="cmd" data-copy="cd ' + esc(m.p || D.root) + ' && claude -r ' + esc(sid) + '">' +
        'cd ' + esc((m.p || D.root).replace(/^\/Users\/[^/]+/, '~')) + ' &amp;&amp; claude -r ' + esc(sid.slice(0, 8)) + '…' +
        '<span style="color:var(--fg-dim)">  click to copy</span></div>');
  } else if (m.live){
    out.push('<div class="grp">Pick it up</div>',
      '<div class="cmd" data-copy="cd ' + esc(m.p || D.root) + ' && claude -r ' + esc(sid) + '">' +
        'cd ' + esc((m.p || D.root).replace(/^\/Users\/[^/]+/, '~')) + ' &amp;&amp; claude -r ' + esc(sid.slice(0, 8)) + '…' +
        '<span style="color:var(--fg-dim)">  ⌘ click to copy</span></div>',
      '<div class="qnote" style="margin-top:8px">Add <span class="f">--fork-session</span> to branch off it ' +
        'without disturbing the original.</div>');
  } else {
    out.push('<div class="grp">Pick it up</div>',
      '<div class="qnote">The transcript for this session is no longer on disk, so it cannot be resumed. ' +
      'What survives is below — copy it into a new session instead.</div>');
  }

  if (docs.length){
    out.push('<div class="grp">Documents it bears on <span class="c">by the files they describe</span></div>');
    docs.forEach(function(x){
      out.push('<div class="tfile" data-doc="' + esc(x.d.rel) + '">' +
        '<span class="nm">' + esc(x.d.title) + '</span>' +
        '<span class="sub">' + esc(x.d.rel) + '</span>' +
        '<span class="sub">' + (x.own ? 'edited here' : x.hit + ' file' + (x.hit > 1 ? 's' : '')) + '</span></div>');
    });
  }
  if (here.length){
    out.push('<div class="grp">Files it changed here <span class="c">' + here.length + '</span></div>',
      '<div class="flist">' + here.slice(0, 40).map(function(f){
        return '<div>' + esc(f.slice(pre.length)) + '</div>'; }).join('') +
      (here.length > 40 ? '<div style="color:var(--fg-dim)">…and ' + (here.length - 40) + ' more</div>' : '') +
      '</div>');
  }
  if (away.length){
    out.push('<div class="grp">Elsewhere <span class="c">' + away.length + '</span></div>',
      '<div class="flist">' + away.slice(0, 12).map(function(f){
        return '<div>' + esc(shortPath(f)) + '</div>'; }).join('') +
      (away.length > 12 ? '<div style="color:var(--fg-dim)">…and ' + (away.length - 12) + ' more</div>' : '') +
      '</div>');
  }
  if (mine.length){
    out.push('<div class="grp">What you asked <span class="c">' + mine.length + '</span></div>',
      '<div class="plist">' + mine.map(function(p){
        var hit = q && count(p.text, q) > 0;
        return '<div class="pitem' + (hit ? ' hit' : '') + '"><span class="when">' + ago(p.t) +
               ' ago</span>' + (hit ? snippet(p.text, q, 4000) : esc(p.text)) + '</div>';
      }).join('') + '</div>');
  }
  return out.join('');
}

/* ── E3 · the graph: which documents belong together ─────────────────────── */
var graphOn = false;
function graphEdges(){
  /* two documents are related when they describe the same files, or when one
     session touched both — the two signals the index already holds */
  var docs = D.docs, idx = {}, edges = {};
  docs.forEach(function(d, i){ idx[d.rel] = i; });
  function link(a, b, w){
    if (a === b) return;
    var k = a < b ? a + '\u0000' + b : b + '\u0000' + a;
    edges[k] = (edges[k] || 0) + w;
  }
  var byTarget = {};
  docs.forEach(function(d){
    ((D.stale[d.rel] || {}).targets || []).forEach(function(t){
      (byTarget[t] = byTarget[t] || []).push(d.rel);
    });
  });
  for (var t in byTarget){
    var g = byTarget[t];
    if (g.length > 12) continue;            // a file everything mentions says nothing
    for (var i = 0; i < g.length; i++) for (var j = i + 1; j < g.length; j++) link(g[i], g[j], 1);
  }
  if (D.withSessions){
    for (var sid in D.sessions){
      var files = D.sessions[sid].files || [];
      if (!files.length || files.length > 400) continue;
      var hit = [];
      docs.forEach(function(d){ if (files.indexOf(d.abs) >= 0) hit.push(d.rel); });
      if (hit.length > 1 && hit.length <= 15){
        for (var a = 0; a < hit.length; a++) for (var b = a + 1; b < hit.length; b++) link(hit[a], hit[b], 2);
      }
    }
  }
  return Object.keys(edges).map(function(k){
    var p = k.split('\u0000');
    return { a: idx[p[0]], b: idx[p[1]], w: edges[k] };
  }).filter(function(e){ return e.a != null && e.b != null; });
}
function viewGraph(){
  var n = D.docs.length;
  if (!graphOn){
    return '<div class="empty">A map of which documents belong together, drawn from the ' +
      'files they describe and the sessions that touched them.<br><br>' +
      n + ' documents' + (n > 120 ? ' — that is a lot to lay out' : '') + '.<br><br>' +
      '<div class="act"><button data-graph="1">Draw it</button></div></div>';
  }
  var edges = graphEdges();
  if (!edges.length) return '<div class="act"><button class="ghost" data-graph="0">back</button></div>' +
    '<div class="empty">Nothing connects yet: no two documents describe the same files, and ' +
    'no session touched more than one of them.</div>';

  /* a plain spring layout — at this size it converges in well under a second */
  var deg = {}; edges.forEach(function(e){ deg[e.a] = (deg[e.a]||0)+1; deg[e.b] = (deg[e.b]||0)+1; });
  var ids = Object.keys(deg).map(Number);
  var W = 900, H = 560, P = [];
  ids.forEach(function(id, i){
    var a = 2 * Math.PI * i / ids.length;
    P.push({ id: id, x: W/2 + Math.cos(a) * 220, y: H/2 + Math.sin(a) * 200, vx: 0, vy: 0 });
  });
  var pos = {}; P.forEach(function(p){ pos[p.id] = p; });
  for (var step = 0; step < 220; step++){
    for (var i = 0; i < P.length; i++) for (var j = i+1; j < P.length; j++){
      var dx = P[i].x - P[j].x, dy = P[i].y - P[j].y, d2 = dx*dx + dy*dy || 1;
      var f = 5200 / d2;
      var dx2 = dx * f, dy2 = dy * f;
      P[i].vx += dx2; P[i].vy += dy2; P[j].vx -= dx2; P[j].vy -= dy2;
    }
    edges.forEach(function(e){
      var A = pos[e.a], B = pos[e.b]; if (!A || !B) return;
      var dx = B.x - A.x, dy = B.y - A.y, d = Math.sqrt(dx*dx + dy*dy) || 1;
      var f = (d - 130) * 0.012 * Math.min(3, e.w);
      A.vx += dx/d*f; A.vy += dy/d*f; B.vx -= dx/d*f; B.vy -= dy/d*f;
    });
    P.forEach(function(p){
      p.x += Math.max(-12, Math.min(12, p.vx)); p.y += Math.max(-12, Math.min(12, p.vy));
      p.vx *= 0.55; p.vy *= 0.55;
      p.x = Math.max(60, Math.min(W-60, p.x)); p.y = Math.max(30, Math.min(H-30, p.y));
    });
  }
  var out = ['<div class="ctl"><button class="chip on" data-graph="0">back to the list</button>' +
    '<span class="sp">' + ids.length + ' connected documents · ' + edges.length + ' links</span></div>',
    '<div class="graph"><svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="xMidYMid meet">'];
  edges.forEach(function(e){
    var A = pos[e.a], B = pos[e.b]; if (!A || !B) return;
    out.push('<line x1="'+A.x.toFixed(1)+'" y1="'+A.y.toFixed(1)+'" x2="'+B.x.toFixed(1)+
             '" y2="'+B.y.toFixed(1)+'" stroke-width="'+Math.min(3, e.w)+'"/>');
  });
  P.forEach(function(p){
    var d = D.docs[p.id], r = 5 + Math.min(9, deg[p.id]);
    out.push('<g class="n" data-doc="'+esc(d.rel)+'"><circle cx="'+p.x.toFixed(1)+'" cy="'+p.y.toFixed(1)+
      '" r="'+r+'"/><text x="'+p.x.toFixed(1)+'" y="'+(p.y - r - 5).toFixed(1)+'">'+
      esc(d.title.slice(0, 26))+'</text></g>');
  });
  out.push('</svg></div>');
  return out.join('');
}

/* ── settings ────────────────────────────────────────────────────────────── */
var SET = D.settings || null;
function setOne(key, value, note){
  var o = {}; o[key] = value;
  api('settings', { set: o }, function(j){
    if (j.error) return toast(j.error);
    SET = j.settings;
    if (j.caps){ for (var k in j.caps) CAPS[k] = j.caps[k]; }
    refreshAll();
    toast(note || 'saved');
  }, function(){ toast('could not save that'); });
}
function viewSettings(){
  if (!can('settings') || !SET) return '<div class="empty">Settings live with the local ' +
    'server. This page was built as a static file, so there is nothing here to change.<br><br>' +
    'Open the workspace with <span class="f">md</span> instead of <span class="f">md --static</span>.</div>';
  var v = SET.values, forced = SET.forced || {};
  var out = [];

  out.push('<div class="grp">Theme</div>');
  var SWATCH = {
    rubric: ['#101013','#17171b','#e8e6e3','#cf4b26', 'warm graphite · red is reserved for your marks'],
    slate:  ['#0e1013','#151a20','#e4e9ee','#8fa7bd', 'near-monochrome · status by lightness, not hue'],
    bone:   ['#f4f1ea','#e9e4d9','#22201c','#a8341c', 'paper and iron gall · the light one, done properly']
  };
  var now_ = MD.theme();
  out.push('<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin-bottom:6px">');
  ['rubric','slate','bone'].forEach(function(name){
    var sw = SWATCH[name], on = now_ === name;
    out.push('<div class="thc' + (on ? ' on' : '') + '" data-theme-pick="' + name + '">' +
      '<div class="sws">' + sw.slice(0,4).map(function(c){
        return '<i style="background:' + c + '"></i>'; }).join('') + '</div>' +
      '<div class="thn">' + name + (on ? '<span>in use</span>' : '') + '</div>' +
      '<div class="thd">' + sw[4] + '</div></div>');
  });
  out.push('</div>');
  out.push('<div class="qnote">Kept in the settings file and in this browser, so a document you ' +
    'open on its own matches. <span class="f">t</span> cycles them.</div>');

  out.push('<div class="grp">Where a session opens</div>');
  var terms = [['', 'whatever ran md']].concat(SET.terminals.map(function(t){
    return [t === 'iTerm' ? 'iTerm.app' : t + '.app', t];
  }));
  out.push('<div class="ctl"><div class="seg">' + terms.map(function(t){
    return '<button data-set="terminal" data-val="' + esc(t[0]) + '" class="' +
      (v.terminal === t[0] ? 'on' : '') + '">' + esc(t[1]) + '</button>';
  }).join('') + '</div><span class="sp">now: ' + esc(SET.terminal_effective) + '</span></div>');
  out.push('<div class="qnote">Launchers are handed to your terminal through LaunchServices, ' +
    'so this needs no permission from macOS and no dialog appears.</div>');

  out.push('<div class="grp">What the page may start</div>');
  out.push('<div class="ctl"><button class="chip' + (v.allow_launch ? ' on' : '') +
    '" data-set="allow_launch" data-val="' + (v.allow_launch ? '0' : '1') + '">' +
    (v.allow_launch ? 'launching is on' : 'launching is off') + '</button>' +
    (forced.allow_launch ? '<span class="sp">' + esc(forced.allow_launch) + '</span>' : '') + '</div>');
  out.push('<div class="qnote">With this on, the workspace can open a Claude session on a ' +
    'document with your notes as its first prompt, resume or fork a past session, reveal a ' +
    'file, or open your editor. It sends a verb and an id — never a path and never a command. ' +
    'Off is the default, and off means nothing here can start a process.</div>');

  out.push('<div class="grp">Editor</div>');
  out.push('<div class="ctl"><input class="fld" id="s-editor" value="' + esc(v.editor) +
    '" placeholder="left empty: whatever macOS opens .md with" spellcheck="false">' +
    '<button class="chip" data-seteditor="1">save</button></div>');
  out.push('<div class="qnote">A command on your PATH, or an absolute path. It is checked ' +
    'before it is stored, and it is passed as an argument — never through a shell.</div>');

  out.push('<div class="grp">Indexing</div>');
  out.push('<div class="ctl"><button class="chip' + (v.deep ? ' on' : '') +
    '" data-set="deep" data-val="' + (v.deep ? '0' : '1') + '">count subagent work</button>' +
    '<span class="sp">applies the next time you open a workspace</span></div>');
  out.push('<div class="qnote">Work you delegate is written to separate transcripts. Without ' +
    'this, a session that edited through subagents looks like it touched nothing.</div>');

  out.push('<div class="grp">Where this is kept</div>');
  out.push('<div class="cmd" data-copy="' + esc(SET.path) + '">' + esc(SET.path.replace(/^\/Users\/[^/]+/, '~')) +
    '<span style="color:var(--fg-dim)">  click to copy</span></div>');
  out.push('<div class="qnote">Your own config directory, readable only by you (0600). ' +
    'Nothing is written into the repositories you index, and nothing leaves the machine.</div>');
  return out.join('');
}

/* ── E7 · views you wrote yourself ───────────────────────────────────────── */
var USER_VIEWS = [];
window.RB = {
  view: function(v){ if (v && v.id && v.render) USER_VIEWS.push(v); },
  data: D, esc: esc, ago: ago, shortPath: shortPath, toast: toast, copy: copy,
  open: function(rel){ openDoc(rel, {}); }
};
(D.views || []).forEach(function(v){
  try { (new Function(v.src)).call(window); }
  catch(e){ console.error('rubricator: view ' + v.name + ' failed:', e); }
});

/* ── dossier ──────────────────────────────────────────────────────────── */
function buildDossier(){
  var q = query.trim(), L = [];
  var docs = D.docs.map(function(d){ return { d:d, s:docScore(d,q) }; })
                   .filter(function(x){ return x.s>0; }).sort(function(a,b){ return b.s-a.s; }).slice(0,8);
  var prompts = promptHits(q).slice(0, 10);
  var sids = {}; promptHits(q).forEach(function(p){ if (p.sid) sids[p.sid] = (sids[p.sid]||0)+1; });
  var files = D.withSessions ? fileRank(Object.keys(sids), sids, q).filter(function(f){ return f.here; }).slice(0,10) : [];
  L.push('Context on "' + q + '" from ' + D.name + '.');
  L.push('');
  if (docs.length){
    L.push('Documents that cover it:');
    docs.forEach(function(x){
      L.push('  ' + x.d.rel + '  — "' + x.d.title + '" (' + count(x.d.text,q) + ' mentions)');
    });
    L.push('');
  }
  var an = [];
  docs.forEach(function(x){ annosFor(x.d).filter(function(i){ return i.state!=='stale'; })
    .forEach(function(i){ an.push('  ' + x.d.rel + ':' + i.lineStart + ' [' + i.verb + '] ' + (i.note||'')); }); });
  if (an.length){ L.push('My open notes on those documents:'); L.push.apply(L, an); L.push(''); }
  if (prompts.length){
    L.push('What I asked about it before:');
    var seen = {};
    prompts.forEach(function(p){
      var line = p.text.replace(/\s+/g, ' ').slice(0, 180);
      var k = line.slice(0, 60);            // the same question re-asked adds nothing
      if (seen[k]) return;
      seen[k] = 1;
      L.push('  · ' + line);
    });
    L.push('');
  }
  if (files.length){
    L.push('Code most specific to those sessions:');
    files.forEach(function(f){ L.push('  ' + shortPath(f.file)); });
    L.push('');
  }
  return L.join('\n');
}

/* ── E2 · one document's history on one axis ─────────────────────────────── */
function docTimeline(d){
  var st = D.stale[d.rel] || {}, commits = (st.ts || []).filter(Boolean);
  var sess = [];
  if (D.withSessions){
    (D.touches[d.abs] || []).forEach(function(sid){
      var m = D.sessions[sid];
      if (m) sess.push({ sid: sid, t: m.b, title: m.t });
    });
  }
  if (!commits.length && !sess.length) return '';
  var all = commits.concat(sess.map(function(x){ return x.t; })).concat([d.mtime]);
  var lo = Math.min.apply(null, all), hi = Math.max(Math.max.apply(null, all), now);
  var span = Math.max(1, hi - lo);
  function x(t){ return (6 + 88 * (t - lo) / span).toFixed(2) + '%'; }
  var out = ['<div class="tl" title="' + commits.length + ' commits · ' + sess.length + ' sessions">'];
  out.push('<div class="axis"></div>');
  commits.forEach(function(t){ out.push('<i class="c" style="left:' + x(t) + '"></i>'); });
  sess.forEach(function(sv){
    out.push('<i class="s" data-ses="' + esc(sv.sid) + '" style="left:' + x(sv.t) +
             '" title="' + esc((sv.title || '').slice(0, 70)) + '"></i>');
  });
  out.push('<i class="m" style="left:' + x(d.mtime) + '" title="last edited"></i>');
  out.push('<span class="lo">' + ago(lo) + ' ago</span><span class="hi">now</span></div>');
  return out.join('');
}

function markHits(root, q){
  var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), nodes = [], n;
  while ((n = w.nextNode())) nodes.push(n);
  var s = q.toLowerCase();
  nodes.forEach(function(node){
    var t = node.nodeValue, i = t.toLowerCase().indexOf(s);
    if (i < 0 || !node.parentNode) return;
    var frag = document.createDocumentFragment(), last = 0;
    while (i >= 0){
      frag.appendChild(document.createTextNode(t.slice(last, i)));
      var m = document.createElement('mark'); m.className = 'hit'; m.textContent = t.slice(i, i+q.length);
      frag.appendChild(m);
      last = i + q.length;
      i = t.toLowerCase().indexOf(s, last);
    }
    frag.appendChild(document.createTextNode(t.slice(last)));
    node.parentNode.replaceChild(frag, node);
  });
}

/* ── surfaces ──────────────────────────────────────────────────────────────
   A surface is whatever a pane can hold. The shell knows only that it can
   render itself into a div and say what to call it; everything that is
   specific to a document, a session or a list lives down here. */
var TITLES = { search:'Search', stale:'Stale', notes:'Notes', graph:'Graph', settings:'Settings' };

function clip(s, n){ s = String(s || ''); return s.length > n ? s.slice(0, n - 1) + '…' : s; }
function grabCaret(host){
  var a = document.activeElement;
  if (a && host.contains(a) && /^(INPUT|TEXTAREA)$/.test(a.tagName) && a.id)
    return { id:a.id, sel:[a.selectionStart, a.selectionEnd] };
  return null;
}
function putCaret(c){
  if (!c) return;
  var el = $(c.id);
  if (!el) return;
  el.focus({ preventScroll:true });
  try { el.setSelectionRange(c.sel[0], c.sel[1]); } catch(e){}
}

/* a list, a table, a form — anything that is rebuilt wholesale from data */
function listSurface(kind){
  var mine = USER_VIEWS.filter(function(v){ return v.id === kind; })[0];
  var builtin = { search:viewSearch, stale:viewStale, notes:viewNotes,
                  graph:viewGraph, settings:viewSettings };
  var S = {};
  S.render = function(host){ S.refresh(host); };
  S.refresh = function(host){
    var c = grabCaret(host);
    host.innerHTML = '<div class="inner">' +
      (mine ? mine.render(D, RB) : (builtin[kind] || viewSearch)()) + '</div>';
    var q = host.querySelector('#q');
    if (q) q.addEventListener('input', function(){ query = q.value; S.refresh(host); });
    var dz = host.querySelector('#dossier');
    if (dz) dz.onclick = function(){ copy(buildDossier()); toast('dossier copied — paste it to your agent'); };
    var dw = host.querySelector('#dossier-what');
    if (dw) dw.onclick = function(){ toast('documents, your open notes, past prompts (scrubbed) and the code most specific to them'); };
    putCaret(c);
    if (kind === 'search') needText();
  };
  S.label = function(){ return { title: mine ? (mine.label || mine.id) : (TITLES[kind] || kind) }; };
  S.hint = function(){
    if (kind === 'search') return 'the whole corpus · ⌘K jumps instead';
    if (kind === 'settings') return 'saved to ~/.config/rubricator/config.json';
    return '';
  };
  return S;
}

/* ── a document in a pane ────────────────────────────────────────────────
   The reader, the review layer and the outline all came for free the moment
   this stopped being a full-screen overlay and became one surface among
   others: it renders into its own div and keeps it. */
function docSurface(rel, q, jump){
  var S = { rel:rel, q:q || '', jump:jump || 0, out:null, premapped:false, host:null };

  S.render = function(host){
    S.host = host;
    host.innerHTML =
      '<div class="dochead"><span class="p"></span></div>' +
      '<div class="body"><div class="tlh"></div><div class="fm"></div>' +
      '<article class="md"></article></div>';
    S.headEl = host.querySelector('.dochead .p');
    S.timeEl = host.querySelector('.tlh');
    S.fmEl   = host.querySelector('.fm');
    S.docEl  = host.querySelector('article.md');
    S.paint();
  };

  S.paint = function(){
    var d = docBy(rel);
    if (!d){
      S.host.innerHTML = '<div class="void">' + esc(rel) + ' is no longer in the index.</div>';
      return;
    }
    if (d.text == null){
      S.docEl.innerHTML = '<p style="color:var(--fg-dim)">Reading ' + esc(rel) + '…</p>';
      return ensureText([rel], function(){
        var f = docBy(rel);
        if (f && f.text != null && S.docEl.isConnected) S.paint();
      });
    }
    S.headEl.textContent = d.rel;
    S.timeEl.innerHTML = docTimeline(d);

    /* the same renderer the single-file reader uses, so a document behaves the
       same here: anchors, alerts, code copy, mermaid — and the same
       block-to-line mapping the review layer needs */
    if (d.kind === 'pdf' || d.kind === 'word'){
      S.fmEl.innerHTML = d.note ? '<div class="docnote">' + esc(d.note) + '</div>' : '';
      S.out = MD.renderExtracted({ doc: S.docEl, text: d.text });
      S.premapped = true;
    } else {
      S.fmEl.innerHTML = '';
      S.out = MD.render({ doc: S.docEl, fm: S.fmEl, raw: d.text,
                          base: 'file://' + d.abs.replace(/[^/]*$/, '') });
      S.premapped = false;
    }
    if (can('asset')){
      var pre = 'file://' + D.root + '/';
      S.docEl.querySelectorAll('img[src],video[src],source[src]').forEach(function(el){
        var v = el.getAttribute('src') || '';
        if (v.indexOf(pre) === 0) el.setAttribute('src', BASE + '/asset?p=' + encodeURIComponent(v.slice(pre.length)));
      });
    }
    if (S.q) markHits(S.docEl, S.q);
    mountReview(S);
    setTimeout(Shell.paint, 0);            // the tab shows the note count

    var target = S.q ? S.docEl.querySelector('mark.hit')
                     : (S.jump ? blockAtLine(S.docEl, S.jump) : null);
    if (target) setTimeout(function(){ target.scrollIntoView({ block:'center' }); }, 60);
    S.jump = 0;
  };

  /* the tray follows focus: whichever document you are looking at is the one
     the review layer is bound to, and the tray says which */
  S.focus = function(){ mountReview(S); };
  S.refresh = function(){ if (S.headEl){ var d = docBy(rel); if (d) S.headEl.textContent = d.rel; } };
  S.reload = function(){ if (S.host) S.paint(); };
  S.goto = function(line, q){
    S.q = q || '';
    if (q && S.docEl){ markHits(S.docEl, q); }
    var t = line ? blockAtLine(S.docEl, line) : (q ? S.docEl.querySelector('mark.hit') : null);
    if (t) t.scrollIntoView({ block:'center' });
  };
  S.label = function(){
    var d = docBy(rel), n = d ? noteCount(d) : 0;
    return { title: rel.split('/').pop(), tip: rel, badge: n || '',
             kd: d && d.kind === 'pdf' ? 'PDF' : (d && d.kind === 'word' ? 'DOC' : '') };
  };
  S.actions = function(){
    var d = docBy(rel), a = [];
    if (!d) return a;
    if (can('launch')) a.push({ label:'Send to Claude', cls:'go', fn:function(){
      mountReview(S);                       /* build from *this* document */
      var text = window.__mdReview ? window.__mdReview.build() : '';
      if (!text) text = 'Read ' + d.rel + ' and tell me what you make of it.';
      act('launch', d.rel, text, 'session opening in a new terminal window');
    }});
    if (can('reveal')) a.push({ label:'reveal', fn:function(){ act('reveal', d.rel, '', 'revealed in Finder'); }});
    a.push({ label:'copy path', fn:function(){ copy(d.abs); toast('path copied'); }});
    return a;
  };
  S.hint = function(){ return 'c ? x e a mark up · f notes · j k move'; };
  return S;
}

function blockAtLine(root, line){
  var out = null;
  [].forEach.call(root.children, function(el){
    if (out || !el.dataset.lineStart) return;
    if (+el.dataset.lineStart <= line && line <= +(el.dataset.lineEnd || el.dataset.lineStart)) out = el;
  });
  return out;
}

/* the review layer is one chrome for many documents — it is re-pointed, never
   rebuilt, and the tray header says which document it is showing */
function mountReview(S){
  if (!window.MDReview || !S.out) return;
  var d = docBy(S.rel);
  if (!d || d.text == null) return;
  window.MDReview.open({
    doc: S.docEl, premapped: S.premapped,
    raw:  S.premapped ? S.out.raw : d.text,
    body: S.premapped ? S.out.raw : S.out.body,
    fmLines: S.out.fmLines,
    META: { path: d.abs, rel: d.rel, name: d.rel.split('/').pop(),
            dir: d.abs.replace(/[^/]*$/, ''), base: 'file://' + d.abs }
  });
  var th = document.querySelector('#tray .th .t');
  if (th) th.textContent = d.rel.split('/').pop();
}

function sessionSurface(sid, q){
  var S = { q: q || '' };
  S.render = function(host){ S.refresh(host); };
  S.refresh = function(host){
    host.innerHTML = '<div class="inner sdet">' + sessionHTML(sid, S.q) + '</div>';
    if (S.q){
      var f = host.querySelector('.pitem.hit');
      if (f) setTimeout(function(){ f.scrollIntoView({ block:'center' }); }, 60);
    }
  };
  S.label = function(){
    var m = D.sessions[sid] || {};
    return { title: clip(m.t || sid.slice(0, 8), 30), tip: m.t || sid, kd:'SES' };
  };
  S.hint = function(){
    var m = D.sessions[sid] || {};
    return m.live ? 'resumable · claude -r ' + sid.slice(0, 8) : 'archived — the transcript is gone';
  };
  return S;
}

/* ── the navigator's three modes ─────────────────────────────────────────── */
function navDocs(){
  marks();
  var docs = libDocs(), all = docs.length;
  if (navQ){
    var s = navQ.toLowerCase();
    docs = docs.filter(function(d){
      return d.rel.toLowerCase().indexOf(s) >= 0 || (d.title || '').toLowerCase().indexOf(s) >= 0;
    });
  }
  var sorts = [['recent','recent'],['stale','stale'],['notes','notes'],['size','size'],['title','name']];
  var facets = [['notes','has notes'],['stale','stale'],['recent','14 days']];
  var narrowed = docs.length !== D.docs.length;
  var h = ['<div class="nvctl"><div class="r">' +
    '<div class="seg">' +
      '<button data-lmode="tree" class="' + (libFlat ? '' : 'on') + '">tree</button>' +
      '<button data-lmode="flat" class="' + (libFlat ? 'on' : '') + '">flat</button>' +
    '</div>' +
    '<button class="opt' + (navOpts ? ' on' : '') + '" data-navopts="1" title="Sorting and filters">' +
      'sort &amp; filter</button>' +
    '<span class="sp">' + (narrowed ? docs.length + ' of ' + D.docs.length : docs.length) + '</span>' +
    '</div>'];
  if (navOpts){
    h.push('<div class="r"><div class="seg">' +
      sorts.map(function(x){ return '<button data-lsort="' + x[0] + '" class="' +
        (libSort === x[0] ? 'on' : '') + '">' + x[1] + '</button>'; }).join('') + '</div></div>');
    h.push('<div class="r">' + facets.map(function(f){
      return '<button class="chip' + (libFacet[f[0]] ? ' on' : '') + '" data-lfacet="' + f[0] + '">' +
             f[1] + '</button>'; }).join('') + '</div>');
  }
  h.push('</div>');
  h.push(docs.length
    ? '<div class="tree">' + ((libFlat || navQ) ? docs.map(fileRow).join('') : libTree(docs)) + '</div>'
    : '<div class="empty">Nothing matches those filters.</div>');
  var kinds = { pdf:0, word:0 };
  D.docs.forEach(function(d){ if (kinds[d.kind] != null) kinds[d.kind]++; });
  var foot = [D.docs.length + ' documents'];
  if (kinds.pdf || kinds.word) foot.push((kinds.pdf + kinds.word) + ' not markdown');
  return { html: h.join(''), filter: navQ, placeholder: 'Filter by name',
           onFilter: function(v){ navQ = v; Shell.nav(); },
           foot: foot.join(' · ') };
}

function navSessions(){
  marks();
  if (!D.withSessions) return { html:'<div class="empty">Session data was not indexed.<br><br>' +
    'Re-run with <span class="f">md --sessions</span> to include your own history.</div>', foot:'' };
  var q = sesQuery.trim(), all = sessionList(), live = 0, sel = curSid();
  all.forEach(function(x){ if (x.m.live) live++; });
  var h = ['<div class="ctl">' +
    '<div class="seg">' +
      '<button data-sscope="here" class="' + (sesScope === 'here' ? 'on' : '') + '">this repo</button>' +
      '<button data-sscope="all" class="' + (sesScope === 'all' ? 'on' : '') + '">everywhere</button>' +
    '</div>' +
    '<button class="chip' + (sesLive ? ' on' : '') + '" data-slive="1">resumable</button>' +
    '<span class="sp">' + all.length + (q ? ' matching' : '') + ' · ' + live + ' resumable</span></div>'];

  /* the whole point of this search is not knowing which repo it was in */
  if (q && sesScope === 'here'){
    var everywhere = sessionList('all').length;
    if (everywhere > all.length)
      h.push('<div class="nvnote">' + (everywhere - all.length) + ' more elsewhere — ' +
             '<button data-sscope="all">search everywhere</button></div>');
  }
  if (!all.length){
    h.push('<div class="empty">' + (q ? 'Nothing you said matches that.'
      : 'No sessions recorded for this directory. Switch to <b>everywhere</b>.') + '</div>');
    return { html:h.join(''), filter:sesQuery, placeholder:'Something you said',
             onFilter:function(v){ sesQuery = v; Shell.nav(); }, foot:'' };
  }
  var group = '';
  all.slice(0, 300).forEach(function(x){
    var g = q ? '' : dayLabel(x.m.b);
    if (g && g !== group){ group = g; h.push('<div class="grp">' + g + '</div>'); }
    h.push('<div class="srow' + (sel === x.sid ? ' on' : '') + '" data-ses="' + esc(x.sid) +
      '" data-q="' + esc(q) + '" title="' + esc(x.m.t || '') + '">' +
      '<span class="dot ' + (x.m.live ? 'live' : 'arch') + '"></span>' +
      '<span class="ttl">' + esc(x.m.t || '(no prompt recorded)') + '</span>' +
      ((sesScope === 'all' || q) ? '<span class="sub">' + esc(shortRepo(x.m.p)) + '</span>' : '') +
      '<span class="sub">' + x.m.n + 'p</span></div>');
  });
  return { html: h.join(''), filter: sesQuery, placeholder: 'Something you said',
           onFilter: function(v){ sesQuery = v; Shell.nav(); },
           foot: Object.keys(D.sessions).length + ' sessions · ' + D.prompts.length + ' prompts' };
}

function navNotes(){
  marks();
  var items = allAnnos().filter(function(i){ return i.state !== 'stale'; });
  if (!items.length) return { html:'<div class="empty">Nothing marked up yet.<br><br>' +
    'Open a document, select a line and press <b>c</b>, <b>?</b>, <b>x</b>, <b>e</b> or <b>a</b>.</div>',
    foot:'' };
  var by = {}, order = [];
  items.forEach(function(i){
    var k = i._doc.rel;
    if (!by[k]){ by[k] = []; order.push(k); }
    by[k].push(i);
  });
  var cur = curRel(), h = [];
  order.forEach(function(rel){
    h.push('<div class="grp">' + esc(rel.split('/').pop()) + ' <span class="c">' + by[rel].length + '</span></div>');
    by[rel].forEach(function(i){
      h.push('<div class="tfile' + (cur === rel ? ' open' : '') + '" data-doc="' + esc(rel) +
        '" data-line="' + (i.lineStart || 0) + '" title="' + esc(i.note || i.quote || '') + '">' +
        '<span class="kind">' + esc((i.verb || '').slice(0, 4)) + '</span>' +
        '<span class="nm">' + esc(clip(i.note || i.quote || i.heading || '—', 46)) + '</span></div>');
    });
  });
  return { html: h.join(''), foot: items.length + ' open · across ' + order.length + ' documents' };
}

function navFor(mode){
  if (mode === 'sessions') return navSessions();
  if (mode === 'notes') return navNotes();
  return navDocs();
}

/* ── find anything ───────────────────────────────────────────────────────
   Four kinds in one list, because when you are looking for something you
   rarely know which of them it is. */
function palSearch(q, kind){
  q = (q || '').trim();
  var lq = q.toLowerCase(), groups = [], total = 0;
  function want(k){ return !kind || kind === k; }
  function hit(s){ return s && s.toLowerCase().indexOf(lq) >= 0; }

  if (want('doc')){
    var docs = D.docs.filter(function(d){ return !q || hit(d.rel) || hit(d.title) || hit(d.text); });
    docs.sort(function(a, b){
      if (q){
        var an = hit(a.rel.split('/').pop()) ? 1 : 0, bn = hit(b.rel.split('/').pop()) ? 1 : 0;
        if (an !== bn) return bn - an;
      }
      return b.mtime - a.mtime;
    });
    total += docs.length;
    groups.push({ label: q ? 'Documents' : 'Recent documents', rows: docs.slice(0, 8).map(function(d){
      var n = noteCount(d);
      return { kind: d.kind === 'md' ? 'doc' : d.kind, title: d.rel.split('/').pop(),
               sub: d.rel.indexOf('/') > 0 ? d.rel.replace(/\/[^/]*$/, '') : (n ? n + ' notes' : ''),
               open: { kind:'doc', id:d.rel, q:q, title:d.rel.split('/').pop(), tip:d.rel } };
    }) });
  }

  if (want('session') && D.withSessions){
    var ss = [];
    for (var sid in D.sessions){
      var m = D.sessions[sid];
      if (!q){ ss.push({ sid:sid, m:m, s:0 }); continue; }
      var r = sessionScore(sid, m, q);
      if (r.s) ss.push({ sid:sid, m:m, s:r.s, best:r.best });
    }
    ss.sort(q ? function(a, b){ return b.s - a.s || b.m.b - a.m.b; }
               : function(a, b){ return b.m.b - a.m.b; });
    total += ss.length;
    groups.push({ label: q ? 'Sessions' : 'Recent sessions', rows: ss.slice(0, 6).map(function(x){
      return { kind:'session', title: clip(x.m.t || '(no prompt recorded)', 64),
               sub: shortRepo(x.m.p) + ' · ' + x.m.n + 'p',
               open: { kind:'session', id:x.sid, q:q, title:clip(x.m.t || x.sid, 30) } };
    }) });
  }

  if (want('note') && q){
    var notes = allAnnos().filter(function(i){
      return i.state !== 'stale' && (hit(i.note) || hit(i.quote) || hit(i.heading));
    });
    total += notes.length;
    groups.push({ label:'Notes', rows: notes.slice(0, 5).map(function(i){
      return { kind:'note', title: clip(i.note || i.quote, 60), sub: i._doc.rel.split('/').pop(),
               open: { kind:'doc', id:i._doc.rel, jump:i.lineStart,
                       title:i._doc.rel.split('/').pop(), tip:i._doc.rel } };
    }) });
  }

  if (want('surface')){
    var rows = [];
    Object.keys(TITLES).forEach(function(k){
      if (q && !hit(TITLES[k])) return;
      rows.push({ kind:'surface', title:TITLES[k], sub:'a surface',
                  open:{ kind:k, id:'', title:TITLES[k] } });
    });
    USER_VIEWS.forEach(function(v){
      if (q && !hit(v.label || v.id)) return;
      rows.push({ kind:'surface', title:v.label || v.id, sub:'yours',
                  open:{ kind:v.id, id:'', title:v.label || v.id } });
    });
    if (q) rows.unshift({ kind:'search', title:'Search everything for “' + q + '”', sub:'the whole corpus',
                          run:function(split){ query = q; Shell.open({ kind:'search', id:'', title:'Search' },
                                                                     split ? 'split' : 'here'); } });
    if (can('reindex') && (!q || hit('reindex')))
      rows.push({ kind:'do', title:'Reindex', sub:'r', run:function(){ reindex(); } });
    if (can('act') && (!q || hit('open project')))
      rows.push({ kind:'do', title:'Open a project…', sub:'a folder', run:function(){ openProject(''); } });
    if (!q || hit('theme'))
      rows.push({ kind:'do', title:'Next theme', sub:'t', run:function(){ pickTheme(MD.nextTheme()); } });
    groups.push({ label:'Go to', rows: rows });
  }

  var kinds = ['doc'];
  if (D.withSessions) kinds.push('session');
  kinds.push('note', 'surface');
  return { groups: groups, kinds: kinds,
           count: q ? total + (total === 1 ? ' hit' : ' hits') : '' };
}

function menuItems(){
  var out = [];
  Object.keys(TITLES).forEach(function(k){
    if (k === 'settings') out.push({ sep:true });
    out.push({ label: TITLES[k], run: function(){ Shell.open({ kind:k, id:'', title:TITLES[k] }); } });
  });
  if (USER_VIEWS.length){
    out.push({ sep:true });
    USER_VIEWS.forEach(function(v){
      out.push({ label: v.label || v.id, run: function(){
        Shell.open({ kind:v.id, id:'', title:v.label || v.id }); } });
    });
  }
  out.push({ sep:true });
  out.push({ label:'Split the pane', key:'⌘\\', run: function(){ Shell.split(); } });
  if (can('reindex')) out.push({ label:'Reindex', key:'r', run: function(){ reindex(); } });
  return out;
}

/* ── opening things ─────────────────────────────────────────────────────── */
function openDoc(rel, opts){
  opts = opts || {};
  var d = docBy(rel);
  if (!d) return null;
  var t = Shell.open({ kind:'doc', id:rel, title:rel.split('/').pop(), tip:rel,
                       q:opts.q || '', jump:opts.jump || 0 },
                     opts.where || 'here');
  /* already open: re-point it at what you asked for rather than opening a copy */
  if (t && t.surf.goto && (opts.q || opts.jump) && t.surf.out) t.surf.goto(opts.jump, opts.q);
  return t;
}
function openSession(sid, opts){
  opts = opts || {};
  if (!D.sessions || !D.sessions[sid]) return null;
  var m = D.sessions[sid];
  return Shell.open({ kind:'session', id:sid, title:clip(m.t || sid.slice(0, 8), 30),
                      tip:m.t || sid, q:opts.q || '' }, opts.where || 'here');
}
function curRel(){ var t = Shell.active(); return t && t.kind === 'doc' ? t.id : ''; }
function curSid(){ var t = Shell.active(); return t && t.kind === 'session' ? t.id : ''; }
function openRels(){
  var m = {};
  Shell.each(function(t){ if (t.kind === 'doc') m[t.id] = 1; });
  return m;
}

function specFor(kind, id){
  if (kind === 'doc') return docBy(id) ? { kind:'doc', id:id, title:id.split('/').pop(), tip:id } : null;
  if (kind === 'session') return (D.sessions && D.sessions[id])
    ? { kind:'session', id:id, title:clip(D.sessions[id].t || id.slice(0, 8), 30) } : null;
  if (TITLES[kind]) return { kind:kind, id:'', title:TITLES[kind] };
  if (USER_VIEWS.some(function(v){ return v.id === kind; })) return { kind:kind, id:'', title:kind };
  return null;
}
function makeSurface(spec){
  if (spec.kind === 'doc') return docSurface(spec.id, spec.q, spec.jump);
  if (spec.kind === 'session') return sessionSurface(spec.id, spec.q);
  return listSurface(spec.kind);
}

/* ── the sweep: new data, same window ───────────────────────────────────── */
function refreshAll(){ stat(); Shell.refresh(); }
function needText(){
  if (!query || textAll || !can('text')) return;
  ensureAllText(function(){ Shell.refresh(); });
}
/* the strip says what the server is doing; how many documents there are is the
   navigator's business, and saying it twice made the window look duplicated */
function stat(){
  var bits = [can('watch') ? 'watching for changes' : (can('live') ? 'served locally' : 'a static page')];
  bits.push('indexed in ' + D.took + 's');
  if (D.withSessions) bits.push(Object.keys(D.sessions).length + ' sessions');
  Shell.status(bits.join(' · '));
}

/* ── reindex, and the heartbeat that decides how long the server lives ───── */
function reindex(done){
  if (!can('reindex')) return done && done();
  var b = $('reidx'); if (b) b.classList.add('busy');
  api('reindex', {}, function(j){
    ['docs','stale','prompts','sessions','touches','hasGit','took','notes'].forEach(function(k){
      if (j[k] !== undefined) D[k] = j[k];
    });
    textAll = false; byS = null;
    if (D.notes && window.MDReview) DISK = D.notes;
    if (b) b.classList.remove('busy');
    /* every open document is re-read where you were reading it */
    Shell.each(function(t){
      if (t.kind !== 'doc' || !t.el) return;
      var d = docBy(t.id);
      if (d) d.text = null;
      var y = t.el.scrollTop;
      t.surf.reload();
      setTimeout(function(){ t.el.scrollTop = y; }, 60);
    });
    refreshAll();
    toast('reindexed — ' + D.docs.length + ' documents');
    done && done();
  }, function(){ if (b) b.classList.remove('busy'); toast('reindex failed'); done && done(); });
}

if (can('live')){
  var rb = document.createElement('button');
  rb.id = 'reidx'; rb.className = 'btn'; rb.title = 'Reindex (r)';
  rb.setAttribute('aria-label', 'Reindex');
  rb.innerHTML = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" ' +
    'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 3v6h-6"/></svg>';
  document.querySelector('.bar').insertBefore(rb, $('navbtn'));
  rb.addEventListener('click', function(){ reindex(); });

  /* the server exits when this stops, so closing the window cleans up after
     itself and a crashed page cannot leave a process behind */
  setInterval(function(){ api('ping', {}); }, 30000);
  addEventListener('pagehide', function(){
    try { navigator.sendBeacon(BASE + '/bye', new Blob(['{}'], {type:'application/json'})); } catch(e){}
  });
}

/* ── E1 · watch: the server tells us when a document changed on disk ─────── */
if (can('watch') && window.EventSource){
  try {
    var es = new EventSource(BASE + '/events');
    es.onmessage = function(ev){
      var j = {};
      try { j = JSON.parse(ev.data); } catch(e){ return; }
      var changed = j.changed || [];
      changed.forEach(function(rel){ var d = docBy(rel); if (d) d.text = null; });
      if ((j.added || []).length || (j.gone || []).length) return reindex();
      if (!changed.length) return;
      var reloaded = 0;
      Shell.each(function(t){
        if (t.kind !== 'doc' || !t.el || changed.indexOf(t.id) < 0) return;
        /* reload the open document where you were reading it, not at the top */
        var y = t.el.scrollTop;
        t.surf.reload();
        setTimeout(function(){ t.el.scrollTop = y; }, 60);
        reloaded++;
      });
      toast(reloaded
        ? changed[0] + ' changed on disk — reloaded'
        : changed.length + (changed.length > 1 ? ' documents' : ' document') + ' changed on disk');
      refreshAll();
    };
  } catch(e){}
}

/* ── the project switcher ─────────────────────────────────────────────────
   Rubricator is started on a directory, and until now that was the only way to
   change it. A second project opens as a second window, the way an editor does
   — the running one keeps its panes, its notes and its watch. */
function projectMenu(){
  var m = $('projmenu');
  if (m){ m.remove(); return; }
  m = document.createElement('div');
  m.id = 'projmenu';
  var out = [];
  (D.recents || []).forEach(function(p){
    out.push('<button data-recent="' + esc(p) + '"><span class="nm">' + esc(p.split('/').pop()) +
      '</span><span class="pp">' + esc(p.replace(/^\/Users\/[^/]+/, '~')) + '</span></button>');
  });
  if (!(D.recents || []).length){
    out.push('<div class="none">No other projects yet — the ones you open show up here.</div>');
  }
  out.push('<div class="sep"></div>');
  out.push('<button data-openproj="1"><span class="nm">Open a project…</span>' +
           '<span class="pp">choose a folder</span></button>');
  m.innerHTML = out.join('');
  $('wname').parentNode.appendChild(m);
  setTimeout(function(){
    document.addEventListener('mousedown', function away(e){
      if (!m.contains(e.target)){ m.remove(); document.removeEventListener('mousedown', away); }
    });
  }, 0);
}
function openProject(id){
  var m = $('projmenu'); if (m) m.remove();
  toast(id ? 'opening ' + id.split('/').pop() + '…' : 'choose a folder…');
  api('act', { verb: id ? 'open-recent' : 'open-project', id: id || '' }, function(j){
    if (j.error) return toast(j.error);
    if (j.cancelled) return;
    toast('opened ' + (j.opened || '').split('/').pop() + ' in its own window');
  }, function(){ toast('could not open that project'); });
}

$('wname').textContent = D.name;
$('wpath').textContent = D.root.replace(/^\/Users\/[^/]+/, '~');

/* ── everything you can click ───────────────────────────────────────────── */
document.addEventListener('click', function(e){
  var seg = e.target.closest('[data-lmode],[data-lsort],[data-lfacet],[data-sscope],[data-slive]');
  if (seg){
    var d = seg.dataset;
    if (d.lmode)  libFlat = d.lmode === 'flat';
    if (d.lsort)  libSort = d.lsort;
    if (d.lfacet) libFacet[d.lfacet] = !libFacet[d.lfacet];
    if (d.sscope) sesScope = d.sscope;
    if (d.slive)  sesLive = !sesLive;
    return Shell.nav();
  }
  if (e.target.closest('#wname')) return projectMenu();
  var rp = e.target.closest('[data-recent]');
  if (rp) return openProject(rp.dataset.recent);
  if (e.target.closest('[data-openproj]')) return openProject('');
  var tp = e.target.closest('[data-theme-pick]');
  if (tp) return pickTheme(tp.dataset.themePick);
  var sb = e.target.closest('[data-set]');
  if (sb){
    var key = sb.dataset.set, raw = sb.dataset.val;
    var val = (key === 'terminal') ? raw : raw === '1';
    return setOne(key, val, key === 'terminal'
      ? 'sessions will open in ' + (raw ? raw.replace('.app','') : 'whatever ran md')
      : null);
  }
  if (e.target.closest('[data-seteditor]')){
    var f = $('s-editor');
    return setOne('editor', f ? f.value.trim() : '', 'editor saved');
  }
  if (e.target.closest('[data-navopts]')){ navOpts = !navOpts; return Shell.nav(); }
  var gb = e.target.closest('[data-graph]');
  if (gb){ graphOn = gb.dataset.graph === '1'; return Shell.refresh(); }
  var dir = e.target.closest('[data-dir]');
  if (dir){
    libOpen[dir.dataset.dir] = libOpen[dir.dataset.dir] === false;
    return Shell.nav();
  }
  var ab = e.target.closest('[data-act]');
  if (ab) return act(ab.dataset.act, ab.dataset.id, '',
                     ab.dataset.act === 'fork' ? 'forking in a new terminal window'
                                               : 'resuming in a new terminal window');
  var cmd = e.target.closest('[data-copy]');
  if (cmd){ copy(cmd.dataset.copy); return toast('copied — paste it into a terminal'); }

  var where = (e.metaKey || e.ctrlKey) ? 'split' : 'here';
  var ses = e.target.closest('[data-ses]');
  if (ses) return openSession(ses.dataset.ses, { q: ses.dataset.q || '', where: where });

  var row = e.target.closest('[data-doc]');
  if (row && !e.target.closest('article.md')){
    return openDoc(row.dataset.doc, { q: row.dataset.q || '', where: where,
                                      jump: +(row.dataset.line || 0) });
  }
});

document.addEventListener('keydown', function(e){
  var typing = /^(INPUT|TEXTAREA)$/.test(e.target.tagName) || e.target.isContentEditable;
  if (e.key === 'Escape'){
    /* the review layer only hears Escape while a document is on screen; from a
       list the tray would otherwise be stuck open */
    if (typing) return e.target.blur();
    var tray = $('tray'), t = Shell.active();
    if (tray.classList.contains('open') && (!t || t.kind !== 'doc')) $('tray-close').click();
    return;
  }
  if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === '/'){
    e.preventDefault();
    if (Shell.navMode() === 'notes') Shell.setNavMode('docs');
    Shell.nav();
    var i = $('nvq-i');
    if (i) i.focus(); else Shell.palette(true);
    return;
  }
  if (e.key === 'r' && can('reindex')){ e.preventDefault(); return reindex(); }
  if (e.key === 't'){ pickTheme(MD.nextTheme()); }
});
$('theme').addEventListener('click', function(){ pickTheme(MD.nextTheme()); });

/* the setting is the default for every window; the browser remembers the last
   one you actually chose, so the reader opened on its own agrees */
function pickTheme(name){
  var t = MD.setTheme(name);
  Shell.refresh();
  if (can('settings')) api('settings', { set: { theme: t } });
  return t;
}
MD.restoreTheme(SET && SET.values ? SET.values.theme : '');
marked.setOptions({ gfm:true });

if (D.withSessions){
  var anyHere = false;
  for (var k in D.sessions){ if (inRepo(D.sessions[k].p)){ anyHere = true; break; } }
  if (!anyHere) sesScope = 'all';        // this repo has no history of its own yet
}

/* ── go ─────────────────────────────────────────────────────────────────── */
var restored = Shell.init({
  storeKey: 'rubricator:layout:' + hash(D.root),
  make: makeSurface, spec: specFor, nav: navFor, search: palSearch, menu: menuItems,
  onFocus: function(){ Shell.nav(); }
});
stat();
if (D.open) openDoc(D.open, {});
else if (!restored) Shell.open({ kind:'search', id:'', title:'Search' });

window.__ws = { data: D, dossier: buildDossier, caps: CAPS,
                reindex: reindex, ensureText: ensureText, ensureAllText: ensureAllText,
                openDoc: openDoc, openSession: openSession, related: relatedDocs,
                shell: window.Shell, refresh: refreshAll,
                setQuery: function(q){ query = q; Shell.refresh(); } };
})();
