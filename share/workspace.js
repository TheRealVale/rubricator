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
var VIEWS = [], view = 'search', query = '';
var libSort = 'recent', libFlat = false, libFacet = {}, libOpen = {}, libSel = '';
var sesScope = 'here', sesLive = false, sesSel = '', sesQuery = '';
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
  return '<div class="tfile' + (libSel === d.rel ? ' on' : '') + '" data-doc="' + esc(d.rel) + '">' +
    '<span class="nm">' + esc(d.rel.split('/').pop()) + '</span>' +
    (mark ? '<span class="kind">' + mark + '</span>' : '') +
    (n ? '<span class="n">' + n + '</span>' : '') +
    (isStale(d) ? '<span class="sub w" title="code it describes moved on">⚠ ' + st.targetChurn + '</span>' : '') +
    '<span class="sub">' + (d.pages ? d.pages + 'p' : (d.words ? d.words + 'w' : '—')) + '</span>' +
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
function viewLibrary(){
  var docs = libDocs();
  var sorts = [['recent','recent'],['stale','stale'],['notes','notes'],['size','size'],['title','name']];
  var out = ['<div class="ctl">' +
    '<div class="seg">' +
      '<button data-lmode="tree" class="' + (libFlat ? '' : 'on') + '">tree</button>' +
      '<button data-lmode="flat" class="' + (libFlat ? 'on' : '') + '">flat</button>' +
    '</div><div class="seg">' +
      sorts.map(function(x){ return '<button data-lsort="' + x[0] + '" class="' +
        (libSort === x[0] ? 'on' : '') + '">' + x[1] + '</button>'; }).join('') +
    '</div>' +
    '<button class="chip' + (libFacet.notes ? ' on' : '') + '" data-lfacet="notes">has notes</button>' +
    '<button class="chip' + (libFacet.stale ? ' on' : '') + '" data-lfacet="stale">stale</button>' +
    '<button class="chip' + (libFacet.recent ? ' on' : '') + '" data-lfacet="recent">last 14 days</button>' +
    '<span class="sp">' + docs.length + ' of ' + D.docs.length + '</span></div>'];
  if (!docs.length) return out.join('') + '<div class="empty">No document matches those filters.</div>';
  out.push('<div class="tree">' + (libFlat ? docs.map(fileRow).join('') : libTree(docs)) + '</div>');
  return out.join('');
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
      out.push('<div class="row" data-doc="' + esc(i._doc.rel) + '">' +
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
function viewSessions(){
  if (!D.withSessions) return '<div class="empty">Session data was not indexed.<br><br>' +
    'Re-run with <span class="f">md --sessions</span> to include your own history. ' +
    'It stays on this machine and cannot be written to a shareable file.</div>';
  var q = sesQuery.trim();
  var all = sessionList(), live = 0;
  all.forEach(function(x){ if (x.m.live) live++; });
  var total = Object.keys(D.sessions).length;
  var out = ['<div class="qbox"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="1.9" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.6-3.6"/></svg>' +
    '<input id="sq" type="text" placeholder="Something you said, or the name of a repo…" value="' +
    esc(sesQuery) + '" autocomplete="off" spellcheck="false">' +
    '<span class="hint">' + D.prompts.length + ' prompts</span></div>',
    '<div class="ctl">' +
    '<div class="seg">' +
      '<button data-sscope="here" class="' + (sesScope === 'here' ? 'on' : '') + '">this repo</button>' +
      '<button data-sscope="all" class="' + (sesScope === 'all' ? 'on' : '') + '">everywhere</button>' +
    '</div>' +
    '<button class="chip' + (sesLive ? ' on' : '') + '" data-slive="1">resumable only</button>' +
    '<span class="sp">' + all.length + (q ? ' matching' : ' of ' + total) + ' · ' + live + ' resumable</span></div>'];

  /* the whole point of this search is not knowing which repo it was in */
  if (q && sesScope === 'here'){
    var everywhere = sessionList('all').length;
    if (everywhere > all.length){
      out.push('<div class="qnote">' + (everywhere - all.length) + ' more in other repositories — ' +
        '<button class="chip" data-sscope="all">search everywhere</button></div>');
    }
  }

  if (!all.length) return out.join('') + '<div class="empty">' + (q
    ? 'Nothing you said matches “' + esc(q) + '”' + (sesScope === 'here' ? ' in this repository.' : ' in any of them.')
    : 'No sessions recorded for this directory.<br><br>Switch to <b>everywhere</b> to see the ' +
      total + ' sessions on this machine.') + '</div>';

  out.push('<div class="qnote">A session is <span class="dot live"></span> resumable while its ' +
    'transcript is still on disk, and <span class="dot arch"></span> archived once it is gone — ' +
    'the prompts survive, the files it touched and <span class="f">claude -r</span> do not.</div>');

  if (q){
    all.slice(0, 40).forEach(function(x){
      out.push('<div class="row" data-ses="' + esc(x.sid) + '" data-q="' + esc(q) + '">' +
        '<div class="t"><span class="dot ' + (x.m.live ? 'live' : 'arch') + '"></span>' +
          esc(x.m.t || '(no prompt recorded)') + '</div>' +
        (x.best ? '<div class="snip">' + snippet(x.best.p.text, q, 200) + '</div>' : '') +
        '<div class="meta"><span class="pill">' + esc(shortRepo(x.m.p)) + '</span>' +
        '<span>' + x.m.n + ' prompts</span>' +
        (x.hits ? '<span>' + x.hits + ' mention' + (x.hits > 1 ? 's' : '') + '</span>' : '<span>title match</span>') +
        '<span>' + ago(x.m.b) + ' ago</span>' +
        (x.m.live ? '' : '<span class="pill">no transcript</span>') + '</div></div>');
    });
    return out.join('');
  }

  var group = '';
  all.forEach(function(x){
    var g = dayLabel(x.m.b);
    if (g !== group){ group = g; out.push('<div class="grp">' + g + '</div>'); }
    out.push('<div class="srow' + (sesSel === x.sid ? ' on' : '') + '" data-ses="' + esc(x.sid) + '">' +
      '<span class="dot ' + (x.m.live ? 'live' : 'arch') + '"></span>' +
      '<span class="ttl">' + esc(x.m.t || '(no prompt recorded)') + '</span>' +
      (sesScope === 'all' ? '<span class="sub">' + esc(shortRepo(x.m.p)) + '</span>' : '') +
      '<span class="sub">' + x.m.n + 'p</span>' +
      '<span class="sub">' + span(x.m) + '</span></div>');
  });
  return out.join('');
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

function openSession(sid, q){
  var m = D.sessions[sid];
  if (!m) return;
  sesSel = sid;
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
  $('spath').textContent = shortRepo(m.p) + ' · session ' + sid.slice(0, 8);
  $('sbody').innerHTML = out.join('');
  $('spane').classList.add('on', 'side');
  document.body.classList.add('split');
  $('spane').scrollTop = 0;
  render();
}
function closeSession(){
  sesSel = '';
  $('spane').classList.remove('on', 'side');
  if (!$('reader').classList.contains('on')) document.body.classList.remove('split');
  render();
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
    render();
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
  open: function(rel){ openDoc(rel, '', true); }
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

/* ── reader ───────────────────────────────────────────────────────────── */
function openDoc(rel, q, side){
  var d = docBy(rel);
  if (!d) return;
  if (d.text == null) return ensureText([rel], function(){ if (d.text != null) openDoc(rel, q, side); });
  libSel = rel;
  $('rpath').textContent = d.rel;
  var tl = $('rtime'); if (tl) tl.innerHTML = docTimeline(d);

  /* the same renderer the single-file reader uses, so the document behaves the
     same here: anchors, alerts, code copy, mermaid — and the same block-to-line
     mapping the review layer needs */
  var doc = $('doc'), out, premapped = false;
  if (d.kind === 'pdf' || d.kind === 'word'){
    $('fm').innerHTML = d.note
      ? '<div class="docnote">' + esc(d.note) + '</div>' : '';
    out = MD.renderExtracted({ doc: doc, text: d.text });
    premapped = true;
  } else {
    $('fm').innerHTML = '';
    out = MD.render({
      doc: doc,
      fm:  $('fm'),
      raw: d.text,
      base: 'file://' + d.abs.replace(/[^/]*$/, '')
    });
  }

  /* META.path is the absolute path, which is exactly what the reader keys its
     annotations on — so notes written here are the same notes it shows */
  if (window.MDReview){
    window.MDReview.open({
      doc: doc, premapped: premapped,
      raw: premapped ? out.raw : d.text,
      body: premapped ? out.raw : out.body, fmLines: out.fmLines,
      META: { path: d.abs, rel: d.rel, name: d.rel.split('/').pop(),
              dir: d.abs.replace(/[^/]*$/, ''), base: 'file://' + d.abs }
    });
  }

  if (can('asset')){
    var pre = 'file://' + D.root + '/';
    doc.querySelectorAll('img[src],video[src],source[src]').forEach(function(el){
      var v = el.getAttribute('src') || '';
      if (v.indexOf(pre) === 0) el.setAttribute('src', BASE + '/asset?p=' + encodeURIComponent(v.slice(pre.length)));
    });
  }
  if (q) markHits(doc, q);
  $('reader').classList.toggle('side', !!side);
  document.body.classList.toggle('split', !!side);
  $('reader').classList.add('on');
  $('reader').scrollTop = 0;
  if (side) render();                 // keep the selected row marked in the list
  var first = doc.querySelector('mark.hit');
  if (first) setTimeout(function(){ first.scrollIntoView({block:'center'}); }, 60);
  $('rcopy').onclick = function(){ copy(d.abs); toast('path copied'); };
  var send = $('rsend');
  if (send){
    send.style.display = can('launch') ? '' : 'none';
    send.onclick = function(){
      /* the notes you just took become the first thing the session hears */
      var text = window.__mdReview ? window.__mdReview.build() : '';
      if (!text) text = 'Read ' + d.rel + ' and tell me what you make of it.';
      act('launch', d.rel, text, 'session opening in a new terminal window');
    };
  }
  var rev = $('rreveal');
  if (rev){
    rev.style.display = can('reveal') ? '' : 'none';
    rev.onclick = function(){ act('reveal', d.rel, '', 'revealed in Finder'); };
  }
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
function closeReader(){
  libSel = '';
  $('reader').classList.remove('on', 'side');
  if (!$('spane').classList.contains('on')) document.body.classList.remove('split');
  $('tray').classList.remove('open');
  document.body.classList.remove('tray-open');
  $('composer').classList.remove('show');
  $('pop').classList.remove('show');
  render();                       // note counts may have changed while it was open
}
function readerBusy(){
  return $('composer').classList.contains('show') || $('tray').classList.contains('open');
}

/* ── shell ────────────────────────────────────────────────────────────── */
function render(){
  /* the search box is rebuilt on every render, and renders now come from more
     than typing — hydration, a watch event, a reindex. Whoever caused it, the
     caret has to come back exactly where it was or you cannot type. */
  var act = document.activeElement, sel = null, selId = '';
  if (act && act.tagName === 'INPUT' && act.id){
    selId = act.id; sel = [act.selectionStart, act.selectionEnd];
  }

  $('tabs').innerHTML = VIEWS.map(function(v){
    return '<button data-v="' + v.id + '" class="' + (v.id===view?'on':'') + '">' + v.label +
      (v.n != null ? '<span class="n">' + v.n + '</span>' : '') + '</button>';
  }).join('');
  var builtin = { search:viewSearch, docs:viewLibrary, stale:viewStale,
                  notes:viewNotes, sessions:viewSessions, graph:viewGraph,
                  settings:viewSettings };
  var mine = USER_VIEWS.filter(function(v){ return v.id === view; })[0];
  $('page').innerHTML = mine ? mine.render(D, RB) : (builtin[view] || viewSearch)();

  var q = $('q');
  if (q) q.addEventListener('input', function(){ query = q.value; render(); });
  var sq = $('sq');
  if (sq) sq.addEventListener('input', function(){ sesQuery = sq.value; render(); });

  var focusOn = selId ? $(selId) : ((view === 'search' && query) ? q : null);
  if (focusOn){
    focusOn.focus({ preventScroll: true });
    if (sel) { try { focusOn.setSelectionRange(sel[0], sel[1]); } catch(e){} }
  }
  needText();          // may render again later; the caret is already restored
  var dz = $('dossier');
  if (dz) dz.onclick = function(){ copy(buildDossier()); toast('dossier copied — paste it to your agent'); };
  var dw = $('dossier-what');
  if (dw) dw.onclick = function(){ toast('documents, your open notes, past prompts (scrubbed) and the code most specific to them'); };
}
function setView(v){ view = v; render(); }

/* the first search is the moment the page needs every document body */
function needText(){
  if (!query || textAll || !can('text')) return;
  ensureAllText(function(){ render(); });
}

if (D.withSessions){
  var anyHere = false;
  for (var k in D.sessions){ if (inRepo(D.sessions[k].p)){ anyHere = true; break; } }
  if (!anyHere) sesScope = 'all';        // this repo has no history of its own yet
}

VIEWS = [
  { id:'search', label:'Search' },
  { id:'docs', label:'Library', n: D.docs.length },
  { id:'stale', label:'Stale' },
  { id:'notes', label:'Notes' },
  { id:'sessions', label:'Sessions', n: D.withSessions ? Object.keys(D.sessions).length : null },
  { id:'graph', label:'Graph' },
  { id:'settings', label:'Settings' }
].concat(USER_VIEWS.map(function(v){ return { id:v.id, label:v.label || v.id }; }));

/* ── reindex, and the heartbeat that decides how long the server lives ───── */
function reindex(done){
  if (!can('reindex')) return done && done();
  var b = $('reidx'); if (b) b.classList.add('busy');
  api('reindex', {}, function(j){
    ['docs','stale','prompts','sessions','touches','hasGit','took','notes'].forEach(function(k){
      if (j[k] !== undefined) D[k] = j[k];
    });
    textAll = false;
    if (D.notes && window.MDReview) DISK = D.notes;
    if (b) b.classList.remove('busy');
    stat(); render();
    if (window.MDReview && $('reader').classList.contains('on') && libSel){
      var d = docBy(libSel);
      if (d) { d.text = null; openDoc(libSel, '', $('reader').classList.contains('side')); }
    }
    toast('reindexed — ' + D.docs.length + ' documents');
    done && done();
  }, function(){ if (b) b.classList.remove('busy'); toast('reindex failed'); done && done(); });
}
function stat(){
  $('wstat').textContent = D.docs.length + ' docs · indexed in ' + D.took + 's' +
    (D.withSessions ? ' · ' + D.prompts.length + ' prompts' : '');
}
if (can('live')){
  var bar = document.querySelector('.wsbar'), themeBtn = $('theme');
  var rb = document.createElement('button');
  rb.id = 'reidx'; rb.className = 'btn'; rb.title = 'Reindex (r)';
  rb.setAttribute('aria-label', 'Reindex');
  rb.style.cssText = 'all:unset;cursor:pointer;padding:6px;border-radius:7px;color:var(--fg-muted)';
  rb.innerHTML = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" ' +
    'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 3v6h-6"/></svg>';
  bar.insertBefore(rb, themeBtn);
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
      if (libSel && changed.indexOf(libSel) >= 0){
        /* reload the open document where you were reading it, not at the top */
        var pane = $('reader'), y = pane.scrollTop, side = pane.classList.contains('side');
        openDoc(libSel, '', side);
        setTimeout(function(){ pane.scrollTop = y; }, 40);
        toast(libSel + ' changed on disk — reloaded');
      } else {
        toast(changed.length + (changed.length > 1 ? ' documents' : ' document') + ' changed on disk');
        render();
      }
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
stat();

document.addEventListener('click', function(e){
  var tab = e.target.closest('#tabs button');
  if (tab) return setView(tab.dataset.v);

  var seg = e.target.closest('[data-lmode],[data-lsort],[data-lfacet],[data-sscope],[data-slive]');
  if (seg){
    var d = seg.dataset;
    if (d.lmode)  libFlat = d.lmode === 'flat';
    if (d.lsort)  libSort = d.lsort;
    if (d.lfacet) libFacet[d.lfacet] = !libFacet[d.lfacet];
    if (d.sscope) sesScope = d.sscope;
    if (d.slive)  sesLive = !sesLive;
    return render();
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
  var gb = e.target.closest('[data-graph]');
  if (gb){ graphOn = gb.dataset.graph === '1'; return render(); }
  var dir = e.target.closest('[data-dir]');
  if (dir){
    libOpen[dir.dataset.dir] = libOpen[dir.dataset.dir] === false;
    return render();
  }
  var ab = e.target.closest('[data-act]');
  if (ab) return act(ab.dataset.act, ab.dataset.id, '',
                     ab.dataset.act === 'fork' ? 'forking in a new terminal window'
                                               : 'resuming in a new terminal window');
  var cmd = e.target.closest('[data-copy]');
  if (cmd){ copy(cmd.dataset.copy); return toast('copied — paste it into a terminal'); }

  var ses = e.target.closest('[data-ses]');
  if (ses){
    if (view !== 'sessions' && !$('spane').classList.contains('on')) setView('sessions');
    var got = openSession(ses.dataset.ses, ses.dataset.q || '');
    /* jump to the first matching prompt rather than making you hunt for it */
    var first = $('sbody').querySelector('.pitem.hit');
    if (first) setTimeout(function(){ first.scrollIntoView({ block:'center' }); }, 60);
    return got;
  }

  var row = e.target.closest('[data-doc]');
  if (row && !e.target.closest('#reader')){
    /* opened from a list: the reader takes the right half and the list stays put */
    var beside = view === 'docs' || $('spane').classList.contains('on');
    return openDoc(row.dataset.doc, row.dataset.q || query.trim(), beside);
  }
  if (e.target.id === 'rclose') closeReader();
  if (e.target.id === 'sclose') closeSession();
});
document.addEventListener('keydown', function(e){
  var typing = /^(INPUT|TEXTAREA)$/.test(e.target.tagName);
  if (e.key === 'Escape'){
    if ($('reader').classList.contains('on')){ if (!readerBusy()) closeReader(); }
    else if ($('spane').classList.contains('on')) closeSession();
    else if (typing) e.target.blur();
    return;
  }
  if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === '/'){ e.preventDefault(); if (view !== 'search') setView('search'); var q=$('q'); if (q) q.focus(); }
  if (e.key === 'r' && can('reindex')){ e.preventDefault(); reindex(); return; }
  if (e.key === 't'){ pickTheme(MD.nextTheme()); }
});
$('theme').addEventListener('click', function(){ pickTheme(MD.nextTheme()); });

/* the setting is the default for every window; the browser remembers the last
   one you actually chose, so the reader opened on its own agrees */
function pickTheme(name){
  var t = MD.setTheme(name);
  if (view === 'settings') render();
  if (can('settings')) api('settings', { set: { theme: t } });
  return t;
}
MD.restoreTheme(SET && SET.values ? SET.values.theme : '');
marked.setOptions({ gfm:true });
render();
if (D.open) openDoc(D.open, '');
window.__ws = { data: D, dossier: buildDossier, setView: setView, caps: CAPS,
                reindex: reindex, ensureText: ensureText, ensureAllText: ensureAllText,
                openDoc: openDoc, closeDoc: closeReader,
                openSession: openSession, closeSession: closeSession,
                related: relatedDocs,
                setQuery: function(q){ query = q; render(); } };
})();
