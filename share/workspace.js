/* markside workspace — search a repo's markdown, its git activity and your own sessions. */
(function(){
"use strict";
var D = JSON.parse(document.getElementById('wsdata').textContent);
var $ = function(id){ return document.getElementById(id); };
var DAY = 86400;
var now = Math.floor(Date.now() / 1000);

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
  var i = text.toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return esc(text.slice(0, len || 150).trim());
  var a = Math.max(0, i - 60), b = Math.min(text.length, i + q.length + (len || 110));
  return (a ? '…' : '') + esc(text.slice(a, i)) + '<mark>' + esc(text.slice(i, i+q.length)) +
         '</mark>' + esc(text.slice(i+q.length, b)) + (b < text.length ? '…' : '');
}
function count(text, q){
  if (!q) return 0;
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
function docScore(d, q){
  return count(d.title, q) * 8 + d.headings.reduce(function(a,h){ return a + count(h.text, q) * 4; }, 0)
       + count(d.text, q);
}

/* ── views ────────────────────────────────────────────────────────────── */
var VIEWS = [], view = 'search', query = '';

function shortPath(p){ return p.replace(D.root + '/', '').replace(/^\/Users\/[^/]+/, '~'); }

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
        '<div class="meta"><span>' + count(x.d.text, q) + ' matches</span><span>' + x.d.words + ' words</span>' +
        '<span>touched ' + ago(x.d.mtime) + ' ago</span>' +
        (an ? '<span class="pill ok">' + an + ' note' + (an>1?'s':'') + '</span>' : '') + '</div></div>');
    });
  }
  if (prompts.length){
    out.push('<div class="grp">You asked about this <span class="c">' + prompts.length + ' prompts</span></div>');
    prompts.slice(0, 12).forEach(function(p){
      out.push('<div class="row" style="cursor:default"><div class="snip">' + snippet(p.text, q, 240) + '</div>' +
        '<div class="meta"><span>' + esc((p.project||'').split('/').pop()) + '</span><span>' + ago(p.t) + ' ago</span></div></div>');
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

function viewDocs(){
  var rows = D.docs.slice().sort(function(a,b){ return b.mtime - a.mtime; });
  var out = ['<table class="ws"><thead><tr><th data-sort="title">Document</th>' +
    '<th class="num" data-sort="words">words</th><th class="num" data-sort="mtime">touched</th>' +
    (D.hasGit ? '<th class="num" data-sort="commits">commits</th>' : '') +
    '<th class="num">notes</th></tr></thead><tbody>'];
  rows.forEach(function(d){
    var s = D.stale[d.rel] || {}, an = annosFor(d).filter(function(i){ return i.state!=='stale'; }).length;
    out.push('<tr data-doc="' + esc(d.rel) + '"><td><b>' + esc(d.title) + '</b><br>' +
      '<span class="f" style="color:var(--fg-dim)">' + esc(d.rel) + '</span></td>' +
      '<td class="num">' + d.words + '</td><td class="num">' + ago(d.mtime) + '</td>' +
      (D.hasGit ? '<td class="num">' + (s.commits||0) + '</td>' : '') +
      '<td class="num">' + (an || '') + '</td></tr>');
  });
  return out.join('') + '</tbody></table>';
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

function viewSessions(){
  if (!D.withSessions) return '<div class="empty">Session data was not indexed.<br><br>' +
    'Re-run with <span class="f">md --workspace --sessions</span> to include your own history. ' +
    'It stays on this machine and cannot be written to a shareable file.</div>';
  var byProj = {};
  D.prompts.forEach(function(p){ var k = (p.project||'?').split('/').pop(); byProj[k] = (byProj[k]||0)+1; });
  var keys = Object.keys(byProj).sort(function(a,b){ return byProj[b]-byProj[a]; });
  var out = ['<div class="qnote">' + D.prompts.length + ' prompts · ' + Object.keys(D.sessions).length +
    ' sessions with file activity · ' + Object.keys(D.touches).length + ' files touched</div>',
    '<div class="grp">Across repos</div><table class="ws"><thead><tr><th>Project</th><th class="num">prompts</th></tr></thead><tbody>'];
  keys.forEach(function(k){ out.push('<tr><td class="f">' + esc(k) + '</td><td class="num">' + byProj[k] + '</td></tr>'); });
  return out.join('') + '</tbody></table>';
}

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
function openDoc(rel, q){
  var d = D.docs.filter(function(x){ return x.rel === rel; })[0];
  if (!d) return;
  $('rpath').textContent = d.rel;
  var body = d.text.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, '');
  $('rbody').innerHTML = marked.parse(body);
  $('rbody').querySelectorAll('pre code').forEach(function(c){
    if (window.hljs) try { hljs.highlightElement(c); } catch(e){}
  });
  if (q) markHits($('rbody'), q);
  $('reader').classList.add('on');
  $('reader').scrollTop = 0;
  var first = $('rbody').querySelector('mark.hit');
  if (first) setTimeout(function(){ first.scrollIntoView({block:'center'}); }, 60);
  $('rcopy').onclick = function(){ copy(d.abs); toast('path copied'); };
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
function closeReader(){ $('reader').classList.remove('on'); }

/* ── shell ────────────────────────────────────────────────────────────── */
function render(){
  $('tabs').innerHTML = VIEWS.map(function(v){
    return '<button data-v="' + v.id + '" class="' + (v.id===view?'on':'') + '">' + v.label +
      (v.n != null ? '<span class="n">' + v.n + '</span>' : '') + '</button>';
  }).join('');
  $('page').innerHTML = ({search:viewSearch, docs:viewDocs, stale:viewStale,
                          notes:viewNotes, sessions:viewSessions}[view])();
  var q = $('q');
  if (q){
    q.addEventListener('input', function(){ query = q.value; var p = q.selectionStart; render();
      var n = $('q'); if (n){ n.focus(); try { n.setSelectionRange(p,p); } catch(e){} } });
    if (view === 'search' && query) q.focus();
  }
  var dz = $('dossier');
  if (dz) dz.onclick = function(){ copy(buildDossier()); toast('dossier copied — paste it to your agent'); };
  var dw = $('dossier-what');
  if (dw) dw.onclick = function(){ toast('documents, your open notes, past prompts (scrubbed) and the code most specific to them'); };
}
function setView(v){ view = v; render(); }

VIEWS = [
  { id:'search', label:'Search' },
  { id:'docs', label:'Documents', n: D.docs.length },
  { id:'stale', label:'Stale' },
  { id:'notes', label:'Notes' },
  { id:'sessions', label: D.withSessions ? 'History' : 'History ·' }
];

$('wname').textContent = D.name;
$('wpath').textContent = D.root.replace(/^\/Users\/[^/]+/, '~');
$('wstat').textContent = D.docs.length + ' docs · indexed in ' + D.took + 's' +
  (D.withSessions ? ' · ' + D.prompts.length + ' prompts' : '');

document.addEventListener('click', function(e){
  var tab = e.target.closest('#tabs button');
  if (tab) return setView(tab.dataset.v);
  var row = e.target.closest('[data-doc]');
  if (row && !$('reader').classList.contains('on')) return openDoc(row.dataset.doc, row.dataset.q || query.trim());
  if (e.target.id === 'rclose') closeReader();
});
document.addEventListener('keydown', function(e){
  var typing = /^(INPUT|TEXTAREA)$/.test(e.target.tagName);
  if (e.key === 'Escape'){ if ($('reader').classList.contains('on')) closeReader(); else if (typing) e.target.blur(); return; }
  if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === '/'){ e.preventDefault(); if (view !== 'search') setView('search'); var q=$('q'); if (q) q.focus(); }
  if (e.key === 't'){
    var r = document.documentElement, t = r.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    r.setAttribute('data-theme', t); try { localStorage.setItem('md-theme', t); } catch(e2){}
  }
});
$('theme').addEventListener('click', function(){
  var r = document.documentElement, t = r.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
  r.setAttribute('data-theme', t); try { localStorage.setItem('md-theme', t); } catch(e){}
});
try { var th = localStorage.getItem('md-theme'); if (th) document.documentElement.setAttribute('data-theme', th); } catch(e){}
marked.setOptions({ gfm:true });
render();
window.__ws = { data: D, dossier: buildDossier, setView: setView,
                setQuery: function(q){ query = q; render(); } };
})();
