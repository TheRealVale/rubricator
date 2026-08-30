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
    /* the body of a refusal is the reason for it — a server that answers 409
       with an explanation is no use if the page throws the explanation away */
    .then(function(r){
      if (r.ok) return r.json();
      return r.json().then(
        function(j){ return Promise.reject({ status: r.status, body: j }); },
        function(){ return Promise.reject({ status: r.status }); });
    })
    /* two-argument then, not .catch: a bug thrown inside cb must not be
       reported back as "the server failed" and run the failure path too */
    .then(function(j){ try { cb && cb(j); } catch(e){ console.error('rubricator:', e); } },
          function(e){ try { fail && fail(e || {}); } catch(err){} });
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
var textPending = false;
function ensureAllText(cb){
  if (textAll || !can('text')) { textAll = true; return cb(); }
  if (textPending) return;              // one corpus fetch, however fast you type
  textPending = true;
  api('text', { rels: [] }, function(j){
    absorb(j);
    textAll = true; textPending = false; cb();
  }, function(){ textPending = false; cb(); });
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
function act(verb, id, text, ok, extra){
  if (!can('launch')) return toast('actions are off — start with md --allow-launch');
  var body = { verb: verb, id: id, text: text || '' };
  if (extra) for (var k in extra) body[k] = extra[k];
  api('act', body, function(j){
    if (j && j.error) return toast(j.error);
    toast((ok || 'done') + (j && j.terminal ? ' — ' + j.terminal : ''));
  }, function(){ toast(verb + ' failed'); });
}

/* notes: the server owns them when there is one, and the browser's copy is
   kept in step so the same notes show up if you open the file on its own */
var DISK = D.notes || {};
/* M6 · marks are filed under a path relative to the enclosing git repository,
   so a store written in one clone loads in a second clone at a different path,
   and `md .` and `md docs/` in one repository read the same marks. The server
   computes the key — the page does not reimplement the git walk-up — and hands
   it over as `nkey`. Falling back to `abs` keeps a page built by an older
   build readable. review.js's own localStorage key is untouched. */
function nkeyOf(d){ return (d && (d.nkey || d.abs)) || ''; }

/* A static page carries `D.notes` — workspace.py ships the sidecar with it
   deliberately, so a page you hand to someone arrives with the marks you made
   in it. It then never read them: the bridge below is installed only when there
   is a server to write back to, so the review layer fell through to
   `localStorage`, which on a freshly opened file is empty. The navigator badge
   read `DISK` (L3) and said 3; the tray beside it said *Nothing yet*. Same
   defect as L3, one tier over, and it survived L3 because L3 fixed the
   aggregate views and this is the per-document one.

   Read-only, because there is nowhere to write: marks made on a static page
   stay in that browser, which is what the page already says. */
if (!can('notes') && window.MDReview && D.notes){
  window.MDReview.identity = { by: D.by || '' };
  var _localGet = window.MDReview.storage.get;
  window.MDReview.storage.get = function(key, path, nkey){
    var mine = null;
    try { mine = _localGet.call(this, key, path, nkey); } catch(e){}
    var theirs = DISK[nkey || path] || null;
    if (!theirs) return mine;
    if (!mine) return theirs;
    /* whichever was saved later; a mark made in this browser after the page was
       built is newer than the one baked into it */
    return (mine.saved || 0) > (theirs.saved || 0) ? mine : theirs;
  };
}

if (can('notes') && window.MDReview){
  window.MDReview.identity = { by: D.by || '' };
  window.MDReview.storage.get = function(key, path, nkey){
    path = nkey || path;
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
  window.MDReview.storage.set = function(key, val, path, nkey){
    path = nkey || path;
    try { localStorage.setItem(key, JSON.stringify(val)); } catch(e){}
    DISK[path] = val;
    clearTimeout(window.__noteT);
    window.__noteT = setTimeout(function(){
      api('notes', { path: path, store: val },
          function(){ noteTrouble(''); },
          /* This was a toast, cleared after 1,900 ms and logged nowhere — the
             sole report that the tool had failed to keep the one thing it
             exists to keep. It now stays in the strip until a save succeeds. */
          function(e){
            var b = e && e.body;
            /* O2 · a second root is read-only, and the refusal says why. The
               alternative — what shipped — was writing the mark into the first
               repository and reporting success. */
            if (b && b.error === 'read-only') noteTrouble(path.split('/').pop(), b.reason);
            else noteTrouble(path.split('/').pop());
          });
    }, 400);
  };
}

/* every note changes two things outside the tray: the count on the tab it was
   written on, and the navigator. Whoever stores it, the window is told. */
if (window.MDReview){
  var _set = window.MDReview.storage.set;
  window.MDReview.storage.set = function(key, val, path, nkey){
    _set.call(this, key, val, path, nkey);
    clearTimeout(window.__markT);
    window.__markT = setTimeout(function(){
      if (window.Shell){ Shell.paint(); Shell.nav(); }
    }, 60);
  };
}

/* annotations live in the reader's local storage, keyed by a hash of the abs path */
function hash(s){ var h=5381,i=s.length; while(i) h=(h*33^s.charCodeAt(--i))>>>0; return h.toString(36); }
/* Every corpus-wide view of your notes comes through here, and it used to read
   `localStorage` only — while the notes themselves were being written correctly
   to `.rubricator/notes.json` and shipped to the page as `DISK`, in scope on
   the line below. The server binds port 0, so every `md <dir>` is a new origin
   and therefore a fresh empty `localStorage`: not empty on the first run, empty
   on *every* run. So the Notes surface, the tab badges, the facets, ⌘K and —
   worst — the dossier builder, which ships the result into an agent's prompt,
   all answered "which of my notes are still open?" with *none*, every launch,
   with the answer sitting on disk three inches away.

   Disk first, because disk is the durable one. `localStorage` remains the
   static tier's only store, so it stays as the fallback rather than going. */
function annosFor(doc){
  var st = DISK[nkeyOf(doc)] || null;
  if (!st){
    try {
      var raw = localStorage.getItem('md-review:' + hash(doc.abs));
      st = raw ? JSON.parse(raw) : null;
    } catch(e){ st = null; }
  }
  if (!st) return [];
  return (st.items || []).map(function(i){ i._doc = doc; return i; });
}
function allAnnos(){
  return D.docs.reduce(function(acc, d){ return acc.concat(annosFor(d)); }, []);
}
/* M4 · the aggregate views filtered on one bit that meant two things. A mark
   whose text moved is still a mark; only one whose text is gone is not. Legacy
   stores carry `state:'stale'` and are read, never rewritten, here too. */
function anchorOf(i){
  if (i.anchorState) return i.anchorState;
  return i.state === 'stale' ? 'orphaned' : 'attached';
}
function isLive(i){ return anchorOf(i) !== 'orphaned'; }

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
/* ── one query parser, and every matcher goes through it ──────────────────
   `count()` used to be a single case-insensitive indexOf of the whole query,
   so a two-word search asked whether that exact string appeared. Measured on a
   330-document corpus: `auth` found 132, `auth flow` found 2, `flow auth` and
   `authentication flow` found nothing. Against 37 two-word queries each built
   from two words of a document's own title, it returned zero for 25 of them.

   Requiring every term fixes the misses and creates a different problem — with
   AND alone, `business match` goes from 0 hits to 111, because both words are
   everywhere. So the ranking half is not optional.

   The plan specified `Σ per-term count + 3 × phrase count`, and that was
   measured and rejected: raw frequency swamps the bonus, so for `auth flow`
   neither of the two documents that actually contain the phrase reached the
   top five, beaten by documents saying "auth" forty times and "flow" ten. What
   ships is `Σ √(per-term count) + 6 × phrase count` — damping the per-term
   half is what makes the bonus matter. Measured against the alternatives on a
   330-document corpus: phrase-carrying documents in the top five went 0/2 to
   2/2 for `auth flow` and 3/5 to 5/5 for `rate limit`, and over 37 two-word
   queries each built from two words of a document's own title, the shipped
   matcher returned nothing for 27 while this returns nothing for none.
   No stemming, no fuzzy matching, no index. */
function terms(q){
  return (q || '').toLowerCase().split(/\s+/).filter(Boolean);
}
/* every term present — the AND half, for callers that want a yes or no */
function hits(text, q){
  if (!q) return true;
  if (!text) return false;
  var t = text.toLowerCase(), ts = terms(q);
  for (var i = 0; i < ts.length; i++) if (t.indexOf(ts[i]) < 0) return false;
  return true;
}
function occurrencesOf(t, s){
  var n = 0, i = 0;
  while (s && (i = t.indexOf(s, i)) >= 0){ n++; i += s.length; }
  return n;
}
/* the literal number of times the query's terms appear, for anything that
   shows a figure to a human rather than sorting by it */
function occurrences(text, q){
  if (!q || !text) return 0;
  var t = text.toLowerCase();
  if (!hits(text, q)) return 0;
  return terms(q).reduce(function(a, s){ return a + occurrencesOf(t, s); }, 0);
}
function count(text, q){
  if (!q || !text) return 0;
  var t = text.toLowerCase(), ts = terms(q);
  var n = 0;
  for (var i = 0; i < ts.length; i++){
    var c = occurrencesOf(t, ts[i]);
    if (!c) return 0;                       // every term, or nothing
    n += Math.sqrt(c);                      // damped: see the note above
  }
  if (ts.length > 1) n += 6 * occurrencesOf(t, q.toLowerCase().trim());
  return n;
}
function snippet(text, q, len){
  text = text || '';
  if (!q) return esc(text.slice(0, len || 150).trim());
  /* prefer the whole phrase; fall back to the first term that appears, so a
     multi-word query still lands the excerpt on something relevant */
  var lt = text.toLowerCase(), needle = q.toLowerCase().trim();
  var i = lt.indexOf(needle);
  if (i < 0){
    var ts = terms(q);
    for (var k = 0; k < ts.length && i < 0; k++){ needle = ts[k]; i = lt.indexOf(needle); }
  }
  if (i < 0) return esc(text.slice(0, len || 150).trim());
  var a = Math.max(0, i - 60), b = Math.min(text.length, i + needle.length + (len || 110));
  return (a ? '…' : '') + esc(text.slice(a, i)) + '<mark>' + esc(text.slice(i, i + needle.length)) +
         '</mark>' + esc(text.slice(i + needle.length, b)) + (b < text.length ? '…' : '');
}

/* ── the topic join ───────────────────────────────────────────────────── */
function promptHits(q){
  if (!D.withSessions || !q) return [];
  if (promptsWithheld()) return [];
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
    /* `inThese`, not `hits`: a local of that name shadows the matcher two
       functions up, and the call below is the only line that needs both */
    var df = D.touches[k].length, inThese = 0, weight = 0;
    D.touches[k].forEach(function(s){
      if (!set[s]) return;
      inThese++;
      weight += (weights && weights[s]) || 1;   // a session that asked 12 times counts more than one that asked once
    });
    if (!inThese) continue;
    var score = (weight * inThese) / df;
    if (ql && hits(k, ql)) score *= 4;                        // the name itself is evidence
    out.push({ file: k, hits: inThese, df: df, s: score, here: k.indexOf(D.root + '/') === 0 });
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
var query = '', navQ = '', allQ = '', navOpts = false;
var libSort = 'recent', libFlat = false, libFacet = {}, libOpen = {};
var libStatus = '';
/* Q2 · the facet keys off the leading word, the row shows the value verbatim.
   The register expected `status:` values to repeat and they do not: this
   repository has 13 distinct shapes across 16 documents that carry one, of
   which `plan — <date>` is the only one appearing more than twice. A facet on
   the whole string would be one document per chip. The leading word is a
   truncation, not a classifier — nothing is mapped, merged or guessed, and the
   full value is always the thing you read in the row. */
function statusKey(d){
  var v = ((d && d.status) || '').trim();
  /* At least three letters, and the word has to end where it ends. Without the
     length floor, `status: G1 shipped · G2–G3 partly` yields a chip called `g`,
     which is not a status anyone would filter by — and two of this repository's
     sixteen do exactly that. A `status:` whose value is a sentence has no key
     and is absent from the facet, which is the honest answer: the field is
     there, it just is not a status. The row still shows nothing invented. */
  var m = /^([A-Za-z]{3,})(?![A-Za-z0-9])/.exec(v);
  return m ? m[1].toLowerCase() : '';
}
function statusKeys(docs){
  var seen = {}, out = [];
  docs.forEach(function(d){
    var k = statusKey(d);
    if (k && !seen[k]){ seen[k] = 1; out.push(k); }
  });
  return out.sort();
}
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

/* Two things can still be arriving while you type: the document bodies, which
   are left on disk until the first search asks for them, and the session index.
   Until they land the counts are a floor rather than an answer, so the surface
   says which one it is waiting for and never claims nothing matched. */
function pendingWork(){
  var w = [];
  if (searching()) w.push('reading the documents');
  if (D.sessionsPending) w.push('reading your history');
  return w;
}

function viewSearch(){
  var q = query.trim(), out = [], waiting = q ? pendingWork() : [];
  var corpus = D.docs.length + ' documents' +
    (promptsWithheld() ? '' : !D.withSessions ? ''
      : D.sessionsPending ? ' and your history'
      : ' and ' + D.prompts.length + ' prompts');
  out.push('<div class="qbox' + (waiting.length ? ' busy' : '') + '">' +
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round">' +
    '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.6-3.6"/></svg>' +
    '<input id="q" placeholder="Search ' + corpus + '…" value="' + esc(query) +
    '" autocomplete="off" spellcheck="false">' +
    '<span class="hint">' + (waiting.length ? 'searching…' : '/ to focus') + '</span></div>');
  out.push(savedRow());
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

  if (waiting.length) out.push('<div class="qnote wait">' + waiting.join(' and ') +
    ' — matching on names and headings so far, and these numbers will grow</div>');
  out.push('<div class="qnote">' + docs.length + ' documents · ' + prompts.length + ' prompts · ' +
    Object.keys(sids).length + ' sessions' +
    (Object.keys(projects).length > 1 ? ' · <b>' + Object.keys(projects).length + ' repos</b>' : '') + '</div>');

  if (docs.length){
    out.push('<div class="grp">Documents <span class="c">' + docs.length + '</span></div>');
    docs.slice(0, 25).forEach(function(x){
      var an = annosFor(x.d).filter(isLive).length;
      out.push('<div class="row" data-doc="' + esc(x.d.rel) + '" data-q="' + esc(q) + '">' +
        '<div class="t">' + esc(x.d.title) + '<span class="p">' + esc(x.d.rel) + '</span></div>' +
        '<div class="snip">' + snippet(x.d.text, q) + '</div>' +
        '<div class="meta">' +
        (nameHit(x.d, q) ? '<span class="pill">name</span>' : '') +
        '<span>' + occurrences(x.d.text, q) + ' in the text</span><span>' + x.d.words + ' words</span>' +
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
  /* "Nothing matched" is a claim about the whole corpus, and it is not one this
     surface can make until the whole corpus is here */
  if (!docs.length && !prompts.length)
    out.push('<div class="empty">' + (waiting.length ? 'Searching…' : 'Nothing matched.') + '</div>');
  else out.push('<div class="act"><button id="dossier">Copy dossier for your agent</button>' +
    '<button class="ghost" id="dossier-open">read it first</button>' +
    (can('settings') ? '<button class="ghost" id="search-save">save this search</button>' : '') +
    '<button class="ghost" id="dossier-what">what goes in it?</button></div>');
  return out.join('');
}

/* ── Q3 · saved searches ──────────────────────────────────────────────────
   `{name, query}` and nothing else. Standing rule 4: persist the selection,
   never the assembly. Opening one re-runs the search against today's index, so
   a pack saved a week ago reflects the corpus as it is now rather than as it
   was — which is the whole reason it is worth saving at all. Stored in
   config.json behind the whitelist (rule 2), because every run is a new origin
   and localStorage would lose it. */
function savedSearches(){
  return (SET && SET.values && SET.values.searches) || [];
}
function saveSearch(name, q){
  var list = savedSearches().filter(function(x){ return x.name !== name; });
  list.push({ name: name, query: q });
  setOne('searches', list.slice(-50), 'saved “' + name + '”');
}
function dropSearch(name){
  setOne('searches', savedSearches().filter(function(x){ return x.name !== name; }),
         'removed “' + name + '”');
}
function savedRow(){
  var list = savedSearches();
  if (!list.length) return '';
  return '<div class="saved"><span class="lbl">saved</span>' + list.map(function(x){
    return '<button class="chip" data-saved="' + esc(x.name) + '" title="' + esc(x.query) +
           ' — re-run against today\'s index">' + esc(x.name) + '</button>';
  }).join('') + '</div>';
}

/* Q3 · the dossier was assembled on every keystroke and thrown away — it could
   only ever be copied, never read. Same builder, rendered. */
function viewDossier(){
  var q = query.trim();
  var out = ['<div class="qbox"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="1.9" stroke-linecap="round"><circle cx="11" cy="11" r="7"/>' +
    '<path d="M20 20l-3.6-3.6"/></svg><input id="q" placeholder="A topic…" value="' +
    esc(query) + '" autocomplete="off" spellcheck="false"><span class="hint">/ to focus</span></div>'];
  out.push(savedRow());
  if (!q) return out.join('') + '<div class="empty">A dossier is what you would paste to an ' +
    'agent before asking it anything: the documents that cover a topic, your open marks on ' +
    'them with the text they are about, what you asked before, and the code most specific to ' +
    'those conversations.<br><br>Type a topic. Nothing here is stored — a saved search keeps ' +
    'the question, and the answer is rebuilt from the index every time you open it.</div>';
  var text = buildDossier();
  out.push('<pre class="dossier">' + esc(text) + '</pre>');
  out.push('<div class="act"><button id="dossier">Copy it</button>' +
    (can('settings') ? '<button class="ghost" id="search-save">save this search</button>' : '') +
    '</div>');
  return out.join('');
}

function noteCount(d){
  return annosFor(d).filter(isLive).length;
}
/* There were two predicates for one idea. The navigator's ⚠ fired on
   `targetChurn > 0` and the Stale surface additionally required the document to
   be 30 days untouched, so one repository showed 231 triangles against 129
   rows. The glyph is gone — it was unranked, decorated 46% of a corpus, and
   said "code it describes moved on" about a signal that correlates r = 0.84
   with how many paths a document quotes and r = 0.12 with its age. What
   survives is the surface, ranked, and the facet now shares its predicate so
   the two finally agree. */
function staleRow(d){
  if (d.kind && d.kind !== 'md') return null;    // a contract does not go stale
  var s = D.stale[d.rel];
  if (!s) return null;
  if (!(s.targetChurn > 0)) return null;
  if (!((now - (s.last || 0)) > 30 * DAY)) return null;
  return s;
}
/* a document the detector could not judge at all: it named no file the index
   recognises, so it is not "fresh" — it is unmeasured, and the surface has to
   say so rather than counting it as clean */
function unjudgeable(d){
  if (d.kind && d.kind !== 'md') return false;
  var s = D.stale[d.rel];
  return !s || !(s.targets && s.targets.length);
}
var LIBSORT = {
  recent: function(a,b){ return b.mtime - a.mtime; },
  stale:  function(a,b){ return ((D.stale[b.rel]||{}).targetChurn||0) - ((D.stale[a.rel]||{}).targetChurn||0); },
  notes:  function(a,b){ return noteCount(b) - noteCount(a); },
  size:   function(a,b){ return b.words - a.words; },
  title:  function(a,b){ return a.rel.localeCompare(b.rel); }
};
/* One name per idea. The sort key `stale` reads as *activity* wherever a human
   sees it, because the facet over the same signal is called *behind its code* —
   two words for one thing is how a panel stops being legible. */
var SORTS = [['recent','recent'], ['stale','activity'], ['notes','notes'],
             ['size','size'], ['title','name']];
function sortLabel(k){
  for (var i = 0; i < SORTS.length; i++) if (SORTS[i][0] === k) return SORTS[i][1];
  return k;
}
/* The facets, once. The list and the counts beside each filter read the same
   table, so the number on a row is always the number of rows that row produces.
   Two copies of this drifted apart the moment one of them gained a predicate. */
var LIBFACETS = [
  { k:'notes',     label:'has notes',      test: function(d){ return noteCount(d) > 0; } },
  { k:'stale',     label:'behind its code', test: function(d){ return !!staleRow(d); } },
  { k:'untracked', label:'untracked',      test: function(d){ return !!d.untracked; } },
  { k:'recent',    label:'last 14 days',   test: function(d){ return now - d.mtime < 14 * DAY; } }
];
function libPass(d, on, status){
  for (var i = 0; i < LIBFACETS.length; i++){
    var f = LIBFACETS[i];
    if (on[f.k] && !f.test(d)) return false;
  }
  /* Q2 · a document that still says `planned` while the code shipped is a
     falsifiable claim about itself, which a churn count is not. Filter to one,
     sort by age, and the stale claims are in front of you. */
  if (status && statusKey(d) !== status) return false;
  return true;
}
function libDocs(){
  var out = D.docs.filter(function(d){ return libPass(d, libFacet, libStatus); });
  return out.sort(LIBSORT[libSort] || LIBSORT.recent);
}
/* how many documents survive if this facet is on, combined with whatever else
   is already on — so a row reading 0 tells you not to spend the click */
function libCount(key, statusKey_){
  var on = {}; for (var k in libFacet) on[k] = libFacet[k];
  if (key) on[key] = true;
  var st = statusKey_ === undefined ? libStatus : statusKey_;
  return D.docs.filter(function(d){ return libPass(d, on, st); }).length;
}
function fileRow(d){
  var n = noteCount(d), st = D.stale[d.rel] || {};
  var mark = d.kind === 'pdf' ? 'PDF' : (d.kind === 'word' ? 'DOC' : '');
  return '<div class="tfile' + (CURREL === d.rel ? ' on' : (OPENSET[d.rel] ? ' open' : '')) +
    '" data-doc="' + esc(d.rel) + '">' +
    '<span class="nm">' + esc(d.rel.split('/').pop()) + '</span>' +
    (mark ? '<span class="kind">' + mark + '</span>' : '') +
    (d.untracked ? '<span class="kind" title="not committed yet">NEW</span>' : '') +
    /* Q2 · the key is the chip, the full value is the tooltip — and a status
       with no key gets no chip rather than an empty one. */
    (statusKey(d) ? '<span class="kind st" title="front matter says: ' + esc(d.status) + '">' +
      esc(statusKey(d)) + '</span>' : '') +
    /* O2 · in a multi-root workspace the row says which repository it is from,
       and whether marks can be written to it. Only the first root has a notes
       store; the others are read-only and now say so instead of having their
       marks written into the first repository. */
    (d.repo ? '<span class="kind repo"' + (d.readonly
        ? ' title="Read-only here — marks are stored in the first repository of a '
          + 'multi-root workspace. Open ' + esc(d.repo) + ' on its own to mark it."'
        : ' title="' + esc(d.repo) + '"') + '>' + esc(d.repo) +
      (d.readonly ? ' ·&nbsp;ro' : '') + '</span>' : '') +
    (n ? '<span class="n">' + n + '</span>' : '') +
    (d.pages ? '<span class="sub">' + d.pages + 'p</span>' : '') +
    (libSort === 'size' && d.words ? '<span class="sub">' + d.words + 'w</span>' : '') +
    '<span class="sub">' + ago(d.mtime) + '</span></div>';
}
function libDirs(docs){
  var out = {};
  docs.forEach(function(d){
    var parts = d.rel.split('/');
    for (var i = 0; i < parts.length - 1; i++) out[parts.slice(0, i + 1).join('/')] = 1;
  });
  return Object.keys(out);
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
  var rows = D.docs.map(function(d){ return { d: d, s: staleRow(d) }; })
    .filter(function(x){ return !!x.s; })
    .sort(function(a,b){ return b.s.targetChurn - a.s.targetChurn; });
  var blind = D.docs.filter(unjudgeable).length;
  /* Two different empties, and the old text asserted the wrong one. It said
     "every document that names code has been touched since that code last
     changed" on a repository where the detector had resolved zero targets for
     87 of 99 documents — an all-clear about documents it never looked at. */
  if (!rows.length){
    return '<div class="empty">' +
      (blind >= D.docs.length
        ? 'Nothing here could be judged. This looks for files a document names in backticks '
          + 'and matches them against git; none of these ' + D.docs.length + ' documents named one.'
        : 'None of the ' + (D.docs.length - blind) + ' documents that name a file has fallen behind it.'
          + (blind ? '<br><br>' + blind + ' of ' + D.docs.length + ' named no file this could check, '
                     + 'so nothing is known about them either way.' : '')) +
      '</div>';
  }
  var out = ['<div class="qnote">Documents whose named files kept changing after the document stopped. ' +
    'Churn is counted only in the files each document actually mentions in backticks or links — ' +
    'so this measures what a document claims about code, not whether it is any good.' +
    (blind ? ' <b>' + blind + ' of ' + D.docs.length + '</b> named no file this could check and are not '
             + 'ranked here at all.' : '') + '</div>',
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
  out.push('</tbody></table>');
  /* it sliced to 40 and said nothing: 40 of 129 and 40 of 154 looked identical */
  if (rows.length > 40)
    out.push('<div class="qnote">showing 40 of ' + rows.length + ', ranked by commits since</div>');
  return out.join('');
}

/* Q4 · the Notes surface, and the text of the Notes surface, from one walk of
   the same data — so the Copy cannot drift from what you are looking at.

   Grouped by verb because that is how the screen groups it. The register said
   *grouped by document*, and *byte-comparable to what is rendered* is the
   stronger of its two requirements, so the screen won.

   The header is not decoration. `reanchor()` has exactly one caller — `openDoc`
   — so every item for a document you have not opened this run carries a
   `lineStart` from whenever it was last opened, possibly several rewrites ago.
   The single-document export re-verifies its anchors; this one cannot, and says
   so rather than implying a precision it does not have. */
var VERB_ORDER = ['change','question','cut','expand','note','approve'];
function notesWalk(){
  var items = allAnnos();
  var open = items.filter(isLive);
  var moved = items.filter(function(i){ return anchorOf(i) === 'moved'; }).length;
  var gone = items.length - open.length;
  var groups = [], byVerb = {};
  open.forEach(function(i){ (byVerb[i.verb] = byVerb[i.verb] || []).push(i); });
  VERB_ORDER.forEach(function(v){ if (byVerb[v]) groups.push({ verb: v, items: byVerb[v] }); });
  return { items: items, open: open, moved: moved, gone: gone, groups: groups };
}
function notesHead(w){
  return w.open.length + ' open' + (w.moved ? ' · ' + w.moved + ' moved' : '') +
         (w.gone ? ' · ' + w.gone + ' whose text is gone' : '');
}
function viewNotes(){
  var w = notesWalk();
  if (!w.items.length) return '<div class="empty">No annotations yet.<br><br>' +
    'Open a document with <span class="f">md &lt;file&gt;</span>, mark it up, and your notes show up here — ' +
    'across every document in the repo.</div>';
  var out = ['<div class="qnote">' + esc(notesHead(w)) +
    '<button class="chip" id="notes-copy" title="Copy exactly what is listed here">copy</button></div>'];
  w.groups.forEach(function(g){
    out.push('<div class="grp">' + g.verb + ' <span class="c">' + g.items.length + '</span></div>');
    g.items.forEach(function(i){
      out.push('<div class="row" data-doc="' + esc(i._doc.rel) + '" data-line="' +
        (i.lineStart || 0) + '">' +
        '<div class="t">' + esc(i.heading || i._doc.title) + '<span class="p">' + esc(i._doc.rel) +
        ':' + i.lineStart + (anchorOf(i) === 'moved' ? ' moved' : '') + '</span></div>' +
        (i.note ? '<div class="snip">' + esc(i.note) + '</div>' : '') + '</div>');
    });
  });
  return out.join('');
}
function notesText(){
  var w = notesWalk();
  if (!w.items.length) return '';
  var out = ['Notes across ' + D.name + ' — ' + notesHead(w) + '.',
    'Line numbers are as of when each document was last opened, not as of now:',
    'a document you have not opened this run may have been rewritten since.',
    'For anchors that have just been re-verified, open the document and export from there.',
    ''];
  w.groups.forEach(function(g){
    g.items.forEach(function(i){
      out.push(i._doc.rel + ':' + (i.lineStart || 0) + ' [' + g.verb + ']' +
               (anchorOf(i) === 'moved' ? ' (moved)' : '') +
               (i.note ? ' ' + String(i.note).replace(/\s*\n\s*/g, ' ') : ''));
    });
  });
  return out.join('\n') + '\n';
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
   touched, and everything you said in it.

   Every block is a `.fsec` carrying the name of what it holds, because the
   find bar has to be able to say *where* it is looking — and hiding a whole
   section that matched nothing is one attribute, not a tree walk. */
function sessionHTML(sid, convo){
  var m = D.sessions[sid];
  if (!m) return '<div class="empty">That session is not in the index.</div>';
  if (promptsWithheld()) return withheldNote();
  var mine = D.prompts.filter(function(p){ return p.sid === sid; })
                      .sort(function(a, b){ return a.t - b.t; });
  var docs = relatedDocs(sid);
  var pre = D.root + '/';
  /* the ordinal travels with the row: it is what the reveal and edit verbs
     take, so that the page names a position in the server's own list rather
     than a path of its own choosing */
  var all = (m.files || []).map(function(f, i){ return { abs: f, n: i }; });
  var here = all.filter(function(x){ return x.abs.indexOf(pre) === 0; });
  var away = all.filter(function(x){ return x.abs.indexOf(pre) !== 0; });

  var out = ['<section class="fsec sabout" data-f="about">',
    '<h3>' + esc(m.t || '(no prompt recorded)') + '</h3>',
    '<div class="who">' +
      '<span><span class="dot ' + (m.live ? 'live' : 'arch') + '"></span> ' +
        (m.live ? 'resumable' : 'archived — transcript gone') + '</span>' +
      '<span>' + esc((m.p || 'unknown project').replace(/^\/Users\/[^/]+/, '~')) + '</span>' +
      '<span>' + m.n + ' prompts</span><span>' + span(m) + '</span>' +
      '<span>last active ' + ago(m.b) + ' ago</span>' +
      /* the id is what every other tool wants from you, and it used to be
         available only inside a longer command */
      '<span class="sid" data-copy="' + esc(sid) + '" title="' + esc(sid) +
        ' — click to copy">' + esc(sid.slice(0, 8)) + '</span>' +
      '</div>', '</section>'];

  if (m.live && can('launch')){
    out.push('<section class="fsec sabout" data-f="about">',
      '<div class="grp">Pick it up</div>',
      '<div class="act"><button data-act="resume" data-id="' + esc(sid) + '">Resume this session</button>' +
      '<button class="ghost" data-act="fork" data-id="' + esc(sid) + '">Fork it</button></div>',
      '<div class="qnote" style="margin-top:9px">Resume continues the conversation where it ' +
      'stopped. Fork branches off without disturbing the original.</div>',
      '<div class="grp">or by hand</div>',
      '<div class="cmd" data-copy="cd ' + esc(m.p || D.root) + ' && claude -r ' + esc(sid) + '">' +
        'cd ' + esc((m.p || D.root).replace(/^\/Users\/[^/]+/, '~')) + ' &amp;&amp; claude -r ' + esc(sid.slice(0, 8)) + '…' +
        '<span style="color:var(--fg-dim)">  click to copy</span></div>', '</section>');
  } else if (m.live){
    out.push('<section class="fsec sabout" data-f="about">',
      '<div class="grp">Pick it up</div>',
      '<div class="cmd" data-copy="cd ' + esc(m.p || D.root) + ' && claude -r ' + esc(sid) + '">' +
        'cd ' + esc((m.p || D.root).replace(/^\/Users\/[^/]+/, '~')) + ' &amp;&amp; claude -r ' + esc(sid.slice(0, 8)) + '…' +
        '<span style="color:var(--fg-dim)">  ⌘ click to copy</span></div>',
      '<div class="qnote" style="margin-top:8px">Add <span class="f">--fork-session</span> to branch off it ' +
        'without disturbing the original.</div>', '</section>');
  } else {
    out.push('<section class="fsec sabout" data-f="about">',
      '<div class="grp">Pick it up</div>',
      '<div class="qnote">The transcript for this session is no longer on disk, so it cannot be resumed. ' +
      'What survives is below — copy it into a new session instead.</div>', '</section>');
  }

  if (docs.length){
    out.push('<section class="fsec" data-f="files">' +
      '<div class="grp">Documents it bears on <span class="c">by the files they describe</span></div>' +
      docs.map(function(x){
        return '<div class="tfile" data-doc="' + esc(x.d.rel) + '">' +
          '<span class="nm">' + esc(x.d.title) + '</span>' +
          '<span class="sub">' + esc(x.d.rel) + '</span>' +
          '<span class="sub">' + (x.own ? 'edited here' : x.hit + ' file' + (x.hit > 1 ? 's' : '')) + '</span></div>';
      }).join('') + '</section>');
  }
  /* the whole list, not the first forty: a truncation you cannot open is a
     file the find bar swears is not there. Every row is in the DOM even when
     its folder is shut — collapsing is CSS, so ⌘F still finds what it says
     it finds and the folder holding the hit opens itself. */
  out.push(sesFileGroup(sid, here, 'here', 'Files it changed here', pre));
  out.push(sesFileGroup(sid, away, 'away', 'Elsewhere', ''));
  out.push('<section class="fsec" data-f="convo"><div class="convo">' +
    (convo || promptList(mine)) + '</div></section>');
  return out.join('');
}
/* ── the files a session changed ──────────────────────────────────────────
   A session in a working repository touches hundreds of files across a hundred
   folders. As a flat list of paths that is neither readable nor usable: nothing
   can be opened, and the one part you recognise — the filename — sits at the
   end of the longest string on the row.

   So the kinds come first, as a bar that is also the filter, because "204
   TypeScript files and four plans" is the question you have before any single
   row. Then folders in path order, each eliding the stem it shares with the row
   above it: these paths repeat `src/app/event/event-editor/features/` eight
   times over and only the tail ever differs. */
var sesKind = {}, sesOpen = {};

function extOf(p){
  var b = p.split('/').pop(), i = b.lastIndexOf('.');
  return i > 0 ? b.slice(i + 1).toLowerCase() : '';
}
/* five buckets, because the palette has five colours and a legend nobody can
   hold in their head is decoration. The chips still name the real extension. */
function kindColour(ext){
  if (/^(md|markdown|mdx|mdc)$/.test(ext)) return 'var(--accent)';
  if (/^(ts|tsx|js|jsx|mjs|cjs|py|rb|go|rs|java|kt|swift|php|sh|zsh)$/.test(ext)) return 'var(--purple)';
  if (/^(sql|prisma|graphql)$/.test(ext)) return 'var(--green)';
  if (/^(html|htm|css|scss|sass|less|vue|svelte)$/.test(ext)) return 'var(--yellow)';
  return 'var(--fg-dim)';
}
var KINDMAX = 6;                        // chips beyond this collapse into `other`

/* The segments a folder shares with the one above it. These paths repeat
   `src/app/event/event-editor/features/` eight times over and only the tail
   ever differs, so the head is drawn quiet: the row still carries the whole
   path, and still copies the whole path, it just stops shouting the part you
   already read. Only whole segments count — `docs/` and `docsets/` share no
   stem. */
function elideStem(dir, prev){
  var a = dir.split('/'), b = (prev || '').split('/'), i = 0;
  while (i < a.length - 1 && a[i] === b[i]) i++;
  return i ? a.slice(0, i).join('/') + '/' : '';
}

function sesFileGroup(sid, items, gid, label, pre){
  if (!items.length) return '';
  var key = sid + ':' + gid;
  var picked = sesKind[key] || '';
  var open = sesOpen[key] || {};

  items.forEach(function(x){
    x.rel = pre && x.abs.indexOf(pre) === 0 ? x.abs.slice(pre.length) : shortPath(x.abs);
    x.dir = x.rel.indexOf('/') < 0 ? '' : x.rel.replace(/\/[^/]*$/, '/');
    x.name = x.rel.split('/').pop();
    x.ext = extOf(x.rel);
    x.doc = pre ? !!docBy(x.rel) : false;
    x.df = (D.touches[x.abs] || []).length;
  });

  /* the kind bar counts the whole group, never the filtered view: a chip that
     changed its own number when you pressed it could not be pressed again */
  var tally = {};
  items.forEach(function(x){ var e = x.ext || 'none'; tally[e] = (tally[e] || 0) + 1; });
  var ranked = Object.keys(tally).sort(function(a, b){ return tally[b] - tally[a]; });
  var top = ranked.slice(0, KINDMAX);
  var rest = ranked.slice(KINDMAX).reduce(function(a, e){ return a + tally[e]; }, 0);
  var kinds = top.map(function(e){
    return { ext: e, n: tally[e], col: kindColour(e), on: picked === e };
  });
  if (rest) kinds.push({ ext: 'other', n: rest, col: 'var(--border)', on: picked === 'other' });

  function inPick(x){
    if (!picked) return true;
    if (picked === 'other') return top.indexOf(x.ext || 'none') < 0;
    return (x.ext || 'none') === picked;
  }
  var live = items.filter(inPick);

  /* path order, so what belongs together sits together and a stem can be
     elided against the row above */
  var byDir = {}, order = [];
  live.forEach(function(x){
    if (!byDir[x.dir]){ byDir[x.dir] = []; order.push(x.dir); }
    byDir[x.dir].push(x);
  });
  order.sort();

  var h = ['<section class="fsec" data-f="files"><div class="grp">' + esc(label) +
    ' <span class="c">' + items.length + (pre ? '' : ' outside this repository') + '</span></div>'];

  h.push('<div class="kbar">' + kinds.map(function(k){
    return '<i style="width:' + (k.n / items.length * 100).toFixed(2) + '%;background:' + k.col +
           (picked && !k.on ? ';opacity:.22' : '') + '"></i>';
  }).join('') + '</div>');
  h.push('<div class="kchips">' + kinds.map(function(k){
    return '<button class="kchip' + (k.on ? ' on' : '') + '" data-fkind="' + esc(k.ext) +
      '" data-fg="' + esc(key) + '">' + esc(k.ext) + ' <b>' + k.n + '</b></button>';
  }).join('') + '</div>');

  h.push('<div class="fsum"><span' + (picked ? ' class="hit"' : '') + '>' +
    (picked ? live.length + ' of ' + items.length + ' · .' + esc(picked) + ' only · in ' +
              order.length + ' folder' + (order.length === 1 ? '' : 's')
            : items.length + ' file' + (items.length === 1 ? '' : 's') + ' across ' +
              order.length + ' folder' + (order.length === 1 ? '' : 's')) +
    '</span><span class="sp">' +
    '<button data-fall="1" data-fg="' + esc(key) + '">expand all</button>' +
    '<button data-fnone="1" data-fg="' + esc(key) + '">collapse</button>' +
    '</span></div>');

  var prev = '';
  order.forEach(function(dir){
    var fs = byDir[dir];
    var stem = elideStem(dir, prev);
    prev = dir;

    var seen = {}, dots = [];
    fs.forEach(function(x){
      var c = kindColour(x.ext);
      if (seen[c]) return;
      seen[c] = 1; dots.push(c);
    });
    /* a filter that leaves three folders standing should not leave them shut */
    var on = picked ? true : !!open[dir];

    h.push('<div class="fdir' + (on ? ' on' : '') + '">' +
      '<div class="dhd" data-fdir="' + esc(dir) + '" data-fg="' + esc(key) + '">' +
        '<span class="caret">▸</span>' +
        '<span class="pth"><span class="stem">' + esc(stem) + '</span>' +
          '<span class="leaf">' + esc(dir.slice(stem.length) || './') + '</span></span>' +
        '<span class="mix">' + dots.slice(0, 4).map(function(c){
          return '<i style="background:' + c + '"></i>'; }).join('') + '</span>' +
        '<span class="n">' + fs.length + '</span></div>' +
      '<div class="dkids">' + fs.map(function(x){
        return sesFileRow(sid, x);
      }).join('') + '</div></div>');
  });

  h.push('</section>');
  return h.join('');
}

/* `sesFileRow`, not `fileRow`: the navigator has owned that name since F6 and
   a second definition of it silently replaces the first */
function sesFileRow(sid, x){
  var acts = [];
  if (x.doc) acts.push(['open', 'Open it here', 'M4 4h9l5 5v11H4z|M13 4v5h5', 'data-doc="' + esc(x.rel) + '"']);
  if (can('reveal'))
    acts.push(['reveal', 'Reveal in Finder', 'M3 7h6l2 2h10v10H3z',
               'data-fact="reveal-file" data-sid="' + esc(sid) + '" data-n="' + x.n + '"']);
  if (can('launch'))
    acts.push(['edit', 'Open in your editor', 'M4 20h16|M14 5l5 5-9 9H5v-5z',
               'data-fact="edit-file" data-sid="' + esc(sid) + '" data-n="' + x.n + '"']);
  acts.push(['copy', 'Copy the path', 'M9 9h11v11H9z|M15 9V4H4v11h5',
             'data-copy="' + esc(x.abs) + '" data-copy-note="path copied"']);

  return '<div class="frow">' +
    '<span class="nm">' + esc(x.name) + '</span>' +
    (x.doc ? '<span class="isdoc">doc</span>' : '') +
    (x.df > 1 ? '<span class="df">' + x.df + ' sessions</span>'
              : '<span class="df only">only here</span>') +
    '<span class="facts">' + acts.map(function(a){
      return '<button ' + a[3] + ' title="' + esc(a[1]) + '" aria-label="' + esc(a[1]) + '">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
        'stroke-linecap="round" stroke-linejoin="round">' +
        a[2].split('|').map(function(d){ return '<path d="' + d + '"/>'; }).join('') +
        '</svg></button>';
    }).join('') + '</span></div>';
}

/* what survives when the transcript is gone: your half, out of history.jsonl */
function promptList(mine){
  if (!mine.length) return '';
  return '<div class="grp">What you asked <span class="c">' + mine.length + '</span></div>' +
    '<div class="plist">' + mine.map(function(p){
      return '<div class="pitem"><span class="when">' + ago(p.t) +
             ' ago</span><span class="tx">' + esc(p.text) + '</span></div>';
    }).join('') + '</div>';
}

var SET = D.settings || null;
function setOne(key, value, note, done){
  var o = {}; o[key] = value;
  api('settings', { set: o }, function(j){
    if (j.error) return toast(j.error);
    SET = j.settings;
    if (j.caps){ for (var k in j.caps) CAPS[k] = j.caps[k]; }
    refreshAll();
    toast(note || 'saved');
    done && done();
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
  out.push('<div class="ctl"><button class="chip' + (v.sessions ? ' on' : '') +
    '" data-set="sessions" data-val="' + (v.sessions ? '0' : '1') + '">' +
    (v.sessions ? 'history is indexed' : 'history is not indexed') + '</button>' +
    (forced.sessions ? '<span class="sp">' + esc(forced.sessions) + '</span>' : '') + '</div>');
  out.push('<div class="qnote">With this on, a bare <span class="f">md</span> indexes your ' +
    'Claude Code history, so a topic resolves to the sessions that discussed it and the files ' +
    'they changed. It reads every conversation on this machine, not only this project\u2019s, ' +
    'which is why it is off until you ask. A page that becomes a file \u2014 ' +
    '<span class="f">-o</span> or <span class="f">--static</span> \u2014 never picks it up from ' +
    'here; ask for it there with <span class="f">--sessions</span> or not at all.</div>');
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
function quoteLines(i){
  try {
    if (window.MDReview && MDReview.quote) return MDReview.quote(i) || [];
  } catch(e){}
  var q = String(i.quote || '');
  return q ? [q.split('\n')[0].slice(0, 160)] : [];
}
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
      L.push('  ' + x.d.rel + '  — "' + x.d.title + '" (' + occurrences(x.d.text,q) + ' mentions)');
    });
    L.push('');
  }
  var an = [];
  docs.forEach(function(x){ annosFor(x.d).filter(isLive).forEach(function(i){
    an.push('  ' + x.d.rel + ':' + i.lineStart + ' [' + i.verb + ']' +
            (anchorOf(i) === 'moved' ? ' (moved)' : '') + ' ' + (i.note || ''));
    /* Q3 · the excerpt, which this used to drop — a note without the text it is
       about asks the agent to go and find it. exportQuote already clips a
       section to its heading and a long block to its first lines. */
    quoteLines(i).forEach(function(qz){ an.push('      > ' + qz); });
  }); });
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
  /* Q1 · these carried no title and no data attribute, so a mark on the axis
     was a mark on an axis. */
  commits.forEach(function(t){
    out.push('<i class="c" data-t="' + t + '" style="left:' + x(t) +
             '" title="commit · ' + esc(ago(t)) + ' ago"></i>');
  });
  sess.forEach(function(sv){
    out.push('<i class="s" data-ses="' + esc(sv.sid) + '" style="left:' + x(sv.t) +
             '" title="' + esc((sv.title || '').slice(0, 70)) + '"></i>');
  });
  out.push('<i class="m" style="left:' + x(d.mtime) + '" title="last edited · ' +
           esc(ago(d.mtime)) + ' ago"></i>');
  out.push('<span class="lo">' + ago(lo) + ' ago</span><span class="hi">now</span></div>');
  return out.join('');
}

/* ── Q1 · which conversations touched this document ───────────────────────
   `D.touches` mapped 1,312 files back to session ids and had exactly two
   consumers: a search-ranking denominator and 9x9px dots. This is the third,
   and its empty state is designed first because the empty state is the common
   one — 264 of 330 documents in one repository and 440 of 502 in another have
   no session on record at all, and the mean over the covered ones is 1.09.

   The reason is not that nothing happened. It is that the file list comes from
   a transcript, and Claude Code sweeps transcripts after `cleanupPeriodDays`
   (30 by default), so this join has a thirty-day half-life by construction.
   Saying that is the difference between *no sessions* and *no sessions we can
   still read*. */
function docSessions(d){
  if (!D.withSessions) return '';
  var ids = (D.touches[d.abs] || []).slice();
  if (!ids.length){
    var R = D.retention, why = '';
    if (R && R.lost) why = ' ' + R.lost + ' of ' + R.known + ' sessions here can be found but ' +
      'not read any more — Claude Code removes transcripts after 30 days, and the file list ' +
      'goes with them. Raise <code>' + esc(R.setting) + '</code> in ~/.claude/settings.json ' +
      'to keep them longer.';
    return '<div class="dsess empty">No session on record touched this.' + why + '</div>';
  }
  var rows = ids.map(function(sid){
    var m = D.sessions[sid]; if (!m) return null;
    return { sid: sid, m: m };
  }).filter(Boolean).sort(function(a, b){ return (b.m.b || 0) - (a.m.b || 0); });
  if (!rows.length) return '';
  return '<div class="dsess"><b>' + rows.length + ' session' + (rows.length > 1 ? 's' : '') +
    ' touched this</b>' + rows.map(function(r){
      return '<a class="s" data-ses="' + esc(r.sid) + '">' +
        '<span class="t">' + esc(clip(r.m.t || r.sid.slice(0, 8), 64)) + '</span>' +
        '<span class="w">' + esc(ago(r.m.b)) + ' ago' + (r.m.live ? '' : ' · archived') + '</span></a>';
    }).join('') + '</div>';
}

/* Returns the marks it made, in document order — a finder steps through that
   list, and the same call that highlights is the one that counts.

   `cap` is a mark budget. Without one, a single letter against a transcript of
   several hundred turns asks for tens of thousands of elements and takes the
   tab with it; the finder passes what it has left and stops when it runs out. */
function markHits(root, q, cap){
  var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), nodes = [], n, made = [];
  cap = cap == null ? Infinity : cap;
  while ((n = w.nextNode())) nodes.push(n);
  /* every term, longest first, so `auth flow` highlights both words rather than
     nothing — the same AND the matcher uses. Longest first stops a short term
     eating the start of a longer one it is a prefix of. */
  var ts = terms(q).sort(function(a, b){ return b.length - a.length; });
  if (!ts.length) return made;
  nodes.forEach(function(node){
    if (made.length >= cap) return;
    var text = node.nodeValue, lt = text.toLowerCase();
    if (!node.parentNode) return;
    var spans = [];
    ts.forEach(function(s){
      var i = lt.indexOf(s);
      while (i >= 0){ spans.push([i, i + s.length]); i = lt.indexOf(s, i + s.length); }
    });
    if (!spans.length) return;
    spans.sort(function(a, b){ return a[0] - b[0]; });
    var frag = document.createDocumentFragment(), last = 0;
    spans.forEach(function(sp){
      if (sp[0] < last) return;                       // overlapping terms: keep the first
      frag.appendChild(document.createTextNode(text.slice(last, sp[0])));
      var m = document.createElement('mark'); m.className = 'hit';
      m.textContent = text.slice(sp[0], sp[1]);
      frag.appendChild(m);
      made.push(m);
      last = sp[1];
    });
    frag.appendChild(document.createTextNode(text.slice(last)));
    node.parentNode.replaceChild(frag, node);
  });
  return made;
}
/* the inverse, so a query can be replaced rather than layered. `normalize`
   walks every child of the node it is called on, so calling it per mark is
   quadratic in the marks sharing a paragraph — once per parent, at the end. */
function clearMarks(root){
  var ms = root.querySelectorAll('mark.hit'), parents = [];
  for (var i = 0; i < ms.length; i++){
    var m = ms[i], p = m.parentNode;
    if (!p) continue;
    p.replaceChild(document.createTextNode(m.textContent), m);
    if (!p.__nm){ p.__nm = 1; parents.push(p); }
  }
  parents.forEach(function(p){ p.__nm = 0; p.normalize(); });
}

/* ── surfaces ──────────────────────────────────────────────────────────────
   A surface is whatever a pane can hold. The shell knows only that it can
   render itself into a div and say what to call it; everything that is
   specific to a document, a session or a list lives down here. */
var TITLES = { search:'Search', stale:'Stale', notes:'Notes', dossier:'Dossier', settings:'Settings' };

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
                  dossier:viewDossier, settings:viewSettings };
  var S = {};
  S.render = function(host){ S.refresh(host); };
  S.refresh = function(host){
    var c = grabCaret(host), body;
    /* A builder that throws used to leave the last good DOM in place and say
       nothing, so a surface that had stopped working looked like a surface
       that had stopped being asked. It says so now, and offers the one thing
       that usually clears it. */
    try { body = mine ? mine.render(D, RB) : (builtin[kind] || viewSearch)(); }
    catch(e){
      console.error('rubricator: the ' + kind + ' surface failed to draw', e);
      body = '<div class="empty"><b>This surface could not be drawn.</b><br><br>' +
        esc((e && e.message) || String(e)) +
        '<br><br><button class="lnk" data-resurf="1">clear the query and try again</button></div>';
    }
    host.innerHTML = '<div class="inner">' + body + '</div>';
    var again = host.querySelector('[data-resurf]');
    if (again) again.onclick = function(){ query = ''; S.refresh(host); };
    var q = host.querySelector('#q');
    if (q) q.addEventListener('input', function(){ query = q.value; S.refresh(host); });
    var dz = host.querySelector('#dossier');
    if (dz) dz.onclick = function(){ copy(buildDossier()); toast('dossier copied — paste it to your agent'); };
    var dop = host.querySelector('#dossier-open');
    if (dop) dop.onclick = function(){
      Shell.open({ kind:'dossier', id:'', title:'Dossier' });
    };
    var ss = host.querySelector('#search-save');
    if (ss) ss.onclick = function(){
      var q = query.trim();
      if (!q) return toast('nothing to save');
      var name = window.prompt('Name this search', q.slice(0, 40));
      if (name && name.trim()) saveSearch(name.trim().slice(0, 60), q);
    };
    [].forEach.call(host.querySelectorAll('[data-saved]'), function(b){
      b.onclick = function(e){
        var x = savedSearches().filter(function(y){ return y.name === b.dataset.saved; })[0];
        if (!x) return;
        if (e.altKey) return dropSearch(x.name);
        query = x.query;
        S.refresh(host);
      };
    });
    var nc = host.querySelector('#notes-copy');
    if (nc) nc.onclick = function(e){
      e.stopPropagation();
      var t = notesText();
      if (!t) return toast('nothing to copy');
      copy(t);
      toast('copied ' + (t.split('\n').length - 6) + ' notes');
    };
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
    S.timeEl.innerHTML = docTimeline(d) + docSessions(d);

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
    if (can('reveal')) a.push({ label:'edit', fn:function(){ act('edit', d.rel, '', 'opened in your editor'); }});
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
    META: { path: d.abs, rel: d.rel, name: d.rel.split('/').pop(), nkey: nkeyOf(d),
            dir: d.abs.replace(/[^/]*$/, ''), base: 'file://' + d.abs }
  });
  var th = document.querySelector('#tray .th .t');
  if (th) th.textContent = d.rel.split('/').pop();
}

/* ── folding a long message ──────────────────────────────────────────────
   An autonomous stretch produces replies that run for pages, and scrolling
   past them to reach the next thing anybody said is most of what reading an
   old session is. Anything longer than a screenful folds to a fixed height
   and says what it is holding back.

   Opening one animates from the folded height to the measured one. The
   duration scales with the distance travelled — a fixed one is wrong at both
   ends, crawling over a small overflow and snapping shut over a large one —
   and `max-height` returns to `none` when the animation lands, so a picture
   or a diagram that arrives later is not clipped by a number measured before
   it existed. */
var FOLD_AT = 340, FOLD_TO = 216;
var CALM = !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
/* a session's file list used to fold as one long block; it collapses by folder
   now, which is the same job done by the thing you were going to click anyway */
var FOLDABLE = '.turn .bub > .md, .plist .pitem > .tx';

function foldLong(root){
  var want = [].filter.call(root.querySelectorAll(FOLDABLE), function(el){ return !el.dataset.fold; });
  if (!want.length) return;
  /* measure everything before touching anything: interleaving the two turns
     one layout into eight hundred */
  var tall = [];
  want.forEach(function(el){
    var h = el.scrollHeight;
    if (h > FOLD_AT) tall.push([el, h, parseFloat(getComputedStyle(el).lineHeight) || 20]);
  });
  tall.forEach(function(x){
    var el = x[0], b = document.createElement('button');
    el.dataset.fold = '1';
    el.classList.add('clamp');
    el.style.maxHeight = FOLD_TO + 'px';
    b.type = 'button';
    b.className = 'unfold';
    b.dataset.lines = Math.max(1, Math.round((x[1] - FOLD_TO) / x[2]));
    el.parentNode.insertBefore(b, el.nextSibling);
    foldLabel(b, el);
  });
}
function foldLabel(b, el){
  var open = el.classList.contains('open');
  var hid = open ? 0 : el.querySelectorAll('mark.hit:not(.off)').length;
  b.innerHTML = '<span class="t">' + (open ? 'show less' : 'show more') + '</span>' +
    '<span class="h">' + (open ? '' : b.dataset.lines + ' more lines' +
      (hid ? ' · ' + hid + ' match' + (hid > 1 ? 'es' : '') : '')) + '</span>';
}
/* the folds carry a match count, so they have to be relabelled when the
   query changes and not only when one of them is opened */
function foldSync(root){
  [].forEach.call(root.querySelectorAll('.unfold'), function(b){
    if (b.previousElementSibling) foldLabel(b, b.previousElementSibling);
  });
}
function foldMs(d){ return Math.round(Math.min(700, 190 + Math.abs(d) * 0.3)); }
/* a toggle mid-animation must not be finished by the previous one's listener */
function foldEnd(el, fn){
  var tok = el._fold;
  var go = function(e){
    if (e.target !== el || e.propertyName !== 'max-height') return;
    el.removeEventListener('transitionend', go);
    if (el._fold === tok) fn();
  };
  el.addEventListener('transitionend', go);
}
function unfold(el, snap){
  if (!el.classList.contains('clamp') || el.classList.contains('open')) return;
  var b = el.nextElementSibling, from = el.getBoundingClientRect().height;
  el._fold = (el._fold || 0) + 1;
  el.classList.add('open');
  el.style.transition = 'none';
  el.style.maxHeight = 'none';
  if (!snap && !CALM){
    var to = el.getBoundingClientRect().height;
    el.style.maxHeight = from + 'px';
    el.getBoundingClientRect();                       // a start the transition can see
    el.style.transition = 'max-height ' + foldMs(to - from) + 'ms cubic-bezier(.22,.61,.36,1)';
    el.style.maxHeight = to + 'px';
    foldEnd(el, function(){ el.style.maxHeight = 'none'; el.style.transition = ''; });
  } else {
    el.style.transition = '';
  }
  if (b) foldLabel(b, el);
}
function refold(el){
  if (!el.classList.contains('open')) return;
  var b = el.nextElementSibling, host = el.closest('.surf');
  /* folding something you have scrolled into throws you into whatever was
     underneath it; the message you were reading comes back to the top first */
  if (host && el.getBoundingClientRect().top < host.getBoundingClientRect().top)
    (el.closest('.turn, .pitem') || el).scrollIntoView({ block:'start' });
  var from = el.getBoundingClientRect().height;
  el._fold = (el._fold || 0) + 1;
  el.classList.remove('open');
  if (CALM){
    el.style.transition = '';
    el.style.maxHeight = FOLD_TO + 'px';
  } else {
    el.style.transition = 'none';
    el.style.maxHeight = from + 'px';
    el.getBoundingClientRect();
    el.style.transition = 'max-height ' + foldMs(from - FOLD_TO) + 'ms cubic-bezier(.4,0,.2,1)';
    el.style.maxHeight = FOLD_TO + 'px';
    foldEnd(el, function(){ el.style.transition = ''; });
  }
  if (b) foldLabel(b, el);
}

/* ── finding things inside one session ───────────────────────────────────
   ⌘F used to fall through to the browser's own find, which knows a session
   as one flat page: a word you said, the same word in a path it touched and
   the same word again in an argument passed to a tool are one undivided list
   of yellow boxes. A session is not flat — it has two halves and several
   layers — so this one is told where to look.

   Every match is counted in every scope whether or not that scope is on,
   because "nothing here" is only worth reading next to "four over there":
   the chips are how you discover that the thing you half-remember was said
   by Claude and not by you. */
var FSCOPES = [
  { k:'you',    label:'you',     sel:'.turn.you .md, .plist .pitem .tx' },
  { k:'claude', label:'Claude',  sel:'.turn.claude .md' },
  { k:'files',  label:'files',   sel:'.frow, .tfile, .did .wrote' },
  { k:'tools',  label:'tools',   sel:'.did .tool, .cmark span' },
  { k:'about',  label:'about',   sel:'.sabout' }
];
var FSEL = FSCOPES.map(function(s){ return s.sel; }).join(', ');
/* how many matches are worth drawing. Past a few thousand you are not stepping
   through them, you are narrowing the query — and the bar says so. */
var FMAX = 4000;
/* the rows "only matches" thins out, once a section has survived */
var FROW = '.turn, .cmark, .plist .pitem, .frow, .tfile, .did .tool';

function scopeOf(el){
  for (var i = 0; i < FSCOPES.length; i++) if (el.matches(FSCOPES[i].sel)) return FSCOPES[i].k;
  return 'about';
}
/* a match inside a fold or a closed disclosure is a match you cannot read */
function reveal(el){
  var c = el.closest('.clamp:not(.open)');
  if (c) unfold(c, true);                             // instantly: the scroll target must hold still
  var d = el.closest('details');
  if (d) d.open = true;
  el.scrollIntoView({ block:'center' });
}

function makeFind(surf){
  var F = { on:false, q:'', only:false, scopes:{}, list:[], at:-1, counts:{}, tmr:0 };
  function inner(){ return surf.host && surf.host.querySelector('.inner'); }
  function bar(){ return surf.host && surf.host.querySelector('.sfind'); }
  function narrowed(){ return FSCOPES.some(function(s){ return F.scopes[s.k]; }); }
  function within(k){ return !narrowed() || !!F.scopes[k]; }

  F.open = function(dir){
    if (dir && F.on && F.list.length) return F.step(dir);
    F.on = true;
    F.paint();
    var i = bar() && bar().querySelector('.fq');
    if (i){ i.focus(); i.select(); }
  };
  F.shut = function(){
    F.on = false; F.q = ''; F.only = false;
    F.list = []; F.at = -1; F.counts = {};
    var root = inner();
    if (root){ clearMarks(root); F.thin(); foldSync(root); }
    var b = bar();
    if (b){ b.hidden = true; b.innerHTML = ''; delete b.dataset.built; }
  };
  F.later = function(){ clearTimeout(F.tmr); F.tmr = setTimeout(function(){ F.run(); }, 110); };

  /* mark the whole surface, then take the highlight back off whatever is out
     of scope. Marking only the scopes that are on would be cheaper and would
     leave the chips unable to say where the misses are. */
  F.run = function(hold){
    var root = inner();
    if (!root) return;
    var was = F.at;
    clearMarks(root);
    F.list = []; F.at = -1; F.counts = {};
    var q = F.q.trim(), left = FMAX;
    F.capped = false;
    if (q){
      var els = root.querySelectorAll(FSEL);
      for (var i = 0; i < els.length; i++){
        if (left <= 0){ F.capped = true; break; }
        var el = els[i], k = scopeOf(el), got = markHits(el, q, left);
        if (!got.length) continue;
        left -= got.length;
        F.counts[k] = (F.counts[k] || 0) + got.length;
        if (within(k)) F.list.push.apply(F.list, got);   // concat here is quadratic
        else got.forEach(function(m){ m.classList.add('off'); });
      }
    }
    F.thin();
    foldSync(root);
    if (F.list.length) F.go(hold && was > 0 ? Math.min(was, F.list.length - 1) : 0, hold);
    else F.sync();
  };
  /* "only matches" is what makes a scope pay: a section that matched nothing
     goes, and inside the ones that stay, so does every row that matched
     nothing. Rows, not turns alone — a file list of four hundred is the
     reason you asked. */
  F.thin = function(){
    var root = inner();
    if (!root) return;
    var live = F.only && !!F.q.trim();
    [].forEach.call(root.querySelectorAll('.fsec'), function(s){
      s.hidden = live && !s.querySelector('mark.hit:not(.off)');
    });
    [].forEach.call(root.querySelectorAll(FROW), function(el){
      el.hidden = live && !el.querySelector('mark.hit:not(.off)');
    });
  };
  F.go = function(i, quiet){
    var n = F.list.length;
    if (!n){ F.at = -1; return F.sync(); }
    F.at = ((i % n) + n) % n;
    F.list.forEach(function(m, k){ m.classList.toggle('now', k === F.at); });
    if (!quiet) reveal(F.list[F.at]);
    F.sync();
  };
  F.step = function(d){ if (F.list.length) F.go(F.at + d); };

  /* the bar is built once and then only updated: rewriting it on every
     keystroke would take the caret with it */
  F.paint = function(){
    var b = bar();
    if (!b) return;
    b.hidden = !F.on;
    if (!F.on) return;
    if (b.dataset.built) return F.sync();
    b.dataset.built = '1';
    b.innerHTML =
      '<div class="fr">' +
        '<input class="fq" placeholder="Find in this session" spellcheck="false">' +
        '<span class="n"></span>' +
        '<button class="st" data-fstep="-1" title="Previous match — ⇧⏎">‹</button>' +
        '<button class="st" data-fstep="1" title="Next match — ⏎">›</button>' +
        '<button class="st x" data-fclose="1" title="Close — esc">✕</button>' +
      '</div>' +
      '<div class="fs"><span class="lbl">in</span>' +
        FSCOPES.map(function(s){
          return '<button class="chip" data-fscope="' + s.k + '" title="Search ' +
                 esc(s.label) + ' only">' + esc(s.label) + '<i></i></button>';
        }).join('') +
        '<button class="chip only" data-fonly="1">only matches</button></div>';
    var i = b.querySelector('.fq');
    i.value = F.q;
    i.addEventListener('input', function(){ F.q = i.value; F.later(); });
    i.addEventListener('keydown', function(e){
      if (e.key === 'Enter'){ e.preventDefault(); return F.step(e.shiftKey ? -1 : 1); }
      if (e.key === 'Escape'){ e.preventDefault(); e.stopPropagation(); return F.shut(); }
    });
    b.addEventListener('click', function(e){
      var s = e.target.closest('[data-fstep]');
      if (s) return F.step(+s.dataset.fstep);
      if (e.target.closest('[data-fclose]')) return F.shut();
      var sc = e.target.closest('[data-fscope]');
      if (sc){
        F.scopes[sc.dataset.fscope] = !F.scopes[sc.dataset.fscope];
        return F.run();
      }
      if (e.target.closest('[data-fonly]')){
        F.only = !F.only;
        F.thin();
        return F.sync();
      }
    });
    F.sync();
  };
  F.sync = function(){
    var b = bar();
    if (!b || !b.dataset.built) return;
    var q = F.q.trim(), n = F.list.length, more = F.capped ? '+' : '';
    b.querySelector('.n').textContent = !q ? '' : n ? (F.at + 1) + ' / ' + n + more : 'none';
    b.classList.toggle('none', !!q && !n);
    b.querySelector('.fq').title = F.capped
      ? 'More than ' + FMAX + ' matches — only the first are marked. Type more of it.' : '';
    [].forEach.call(b.querySelectorAll('[data-fscope]'), function(el){
      var c = F.counts[el.dataset.fscope] || 0;
      el.classList.toggle('on', !!F.scopes[el.dataset.fscope]);
      el.classList.toggle('nil', !!q && !c);
      el.querySelector('i').textContent = q ? c + more : '';
    });
    var o = b.querySelector('[data-fonly]');
    o.classList.toggle('on', F.only);
    o.disabled = !q;
    Shell.status();                        // the strip says how many, and where
  };
  /* the surface rebuilds its body on every reindex; the query outlives it */
  F.after = function(){
    if (!F.on) return;
    F.paint();
    if (F.q.trim()) F.run(true); else F.sync();
  };
  F.hint = function(){
    if (!F.on || !F.q.trim()) return '';
    var on = FSCOPES.filter(function(s){ return F.scopes[s.k]; })
                    .map(function(s){ return s.label; });
    if (F.capped) return 'more than ' + FMAX + ' matches — type more of it';
    return F.list.length + (F.list.length === 1 ? ' match' : ' matches') +
           (on.length ? ' in ' + on.join(' + ') : '');
  };
  return F;
}

function sessionSurface(sid, q){
  var S = { q: q || '', conv: null, err: '', loading: false, host: null };
  var F = makeFind(S);

  S.render = function(host){
    S.host = host;
    /* the find bar is a sibling of the body, not part of it: the body is
       rebuilt whenever the index moves and the query must survive that */
    host.innerHTML = '<div class="sfind" hidden></div><div class="inner sdet"></div>';
    S.refresh(host);
    S.load();
    /* a session opened out of a search arrives with the query already in the
       bar, so the thing you were looking for is the thing you land on */
    if (S.q){ F.q = S.q; F.on = true; }
    /* nothing can be measured or scrolled until the pane is shown */
    setTimeout(function(){ S.fold(); F.after(); }, 0);
  };
  /* history.jsonl only ever held your half. The other half is in the
     transcript, which is read once, on opening, and kept for this tab. */
  S.load = function(){
    var m = D.sessions[sid] || {};
    if (S.conv || S.err || S.loading || !can('conversation') || !m.live) return;
    S.loading = true;
    api('session?id=' + encodeURIComponent(sid), undefined, function(j){
      S.loading = false;
      if (j && j.turns && j.turns.length) S.conv = j;
      else S.err = (j && j.error) || 'nothing readable in that transcript';
      if (S.host) S.refresh(S.host);
      Shell.paint();                       // the strip can now say how long it is
    }, function(){
      S.loading = false;
      S.err = 'could not read the transcript';
      if (S.host) S.refresh(S.host);
    });
  };
  S.slot = function(){
    if (S.conv) return renderConvo(S.conv);
    if (S.loading) return '<div class="qnote">Reading the transcript…</div>';
    if (S.err) return '<div class="qnote">' + esc(S.err) + ' — what you said survives below.</div>';
    return '';
  };
  S.fold = function(){
    var box = S.host && S.host.querySelector('.inner');
    if (box && S.host.offsetHeight) foldLong(box);
  };
  S.refresh = function(host){
    S.host = host;
    if (!host.querySelector('.inner'))
      host.innerHTML = '<div class="sfind" hidden></div><div class="inner sdet"></div>';
    var box = host.querySelector('.inner'), y = host.scrollTop;
    box.innerHTML = sessionHTML(sid, S.slot());
    S.fold();                              // before the scroll is restored: folding moves everything
    if (y) host.scrollTop = y;
    F.after();
  };
  /* a pane that was never shown could not be measured, so the folds are cut
     the first time it is looked at */
  S.focus = function(){ S.fold(); };
  S.find = function(dir){ F.open(dir); };
  S.label = function(){
    var m = D.sessions[sid] || {};
    return { title: clip(m.t || sid.slice(0, 8), 30), tip: m.t || sid, kd:'SES' };
  };
  /* A document tab carries Send to Claude, reveal and copy path; a session tab
     carried nothing, so picking a conversation back up meant opening it,
     scrolling past the transcript and finding the buttons in the body. These
     are the same actions, one click from wherever you found the session. */
  S.actions = function(){
    var m = D.sessions[sid] || {}, a = [];
    var cwd = m.p || D.root;
    if (m.live && can('launch')){
      a.push({ label:'Resume', cls:'go', fn:function(){
        act('resume', sid, '', 'resuming in a new terminal window'); }});
      a.push({ label:'fork', fn:function(){
        act('fork', sid, '', 'forked into a new terminal window'); }});
    }
    a.push({ label:'find', fn:function(){ F.open(0); }});
    a.push({ label:'copy id', fn:function(){ copy(sid); toast('session id copied'); }});
    if (m.live) a.push({ label:'copy command', fn:function(){
      copy('cd ' + cwd + ' && claude -r ' + sid);
      toast('resume command copied'); }});
    if (can('reveal') && m.p) a.push({ label:'reveal', fn:function(){
      act('reveal-session', sid, '', 'revealed in Finder'); }});
    return a;
  };
  S.hint = function(){
    var m = D.sessions[sid] || {};
    var f = F.hint();
    if (f) return f;
    if (S.conv) return S.conv.you + ' from you · ' + S.conv.claude + ' from Claude · ⌘F searches it';
    return m.live ? 'resumable · claude -r ' + sid.slice(0, 8) : 'archived — the transcript is gone';
  };
  return S;
}

/* ── a conversation, as a conversation ───────────────────────────────────
   Yours on the right, Claude's on the left: the one layout convention
   nobody has to be taught. What Claude *did* between saying things is a
   quiet line under the bubble — thinking as a count, tools behind a
   disclosure, and the files it wrote as chips you can open. */
function renderConvo(c){
  var out = ['<div class="grp">The conversation <span class="c">' +
    c.you + ' from you · ' + c.claude + ' from Claude' +
    (c.truncated ? ' · too long to show in full' : '') + '</span></div>'];
  var last = '';
  c.turns.forEach(function(t){
    if (t.who === 'mark'){
      last = '';
      out.push('<div class="cmark ' + esc(t.kind) + '"><span>' + esc(t.text || t.kind) + '</span></div>');
      return;
    }
    var mine = t.who === 'you', run = t.who === last;
    last = t.who;
    /* Claude usually speaks several times before you answer; a run of them is
       one exchange, so only the first carries a clock and the gap tightens */
    out.push('<div class="turn ' + (mine ? 'you' : 'claude') + (run ? ' cont' : '') + '">' +
      (!run && t.t ? '<div class="tm">' + clock(t.t) + '</div>' : '') +
      '<div class="bub"><div class="md">' + turnHTML(t.text) + '</div>' +
      (mine ? '' : didHTML(t)) + '</div></div>');
  });
  return out.join('');
}
function turnHTML(text){
  if (!text) return '<p class="nothing">—</p>';
  var box = document.createElement('div');
  try { box.innerHTML = marked.parse(text); } catch(e){ box.textContent = text; }
  MD.sanitise(box);                        // a transcript is untrusted like anything else
  return box.innerHTML;
}
function didHTML(t){
  var parts = [];
  if (t.thinking) parts.push('<span class="th">' + t.thinking + ' thought' +
    (t.thinking > 1 ? 's' : '') + '</span>');
  if (t.tools && t.tools.length){
    parts.push('<details class="tools"><summary>' + t.tools.length + ' tool call' +
      (t.tools.length > 1 ? 's' : '') + '</summary>' +
      t.tools.map(function(x){
        return '<div class="tool"><span class="n">' + esc(x.n) + '</span>' +
          (x.b ? '<span class="b">' + esc(x.b) + '</span>' : '') +
          (x.ok === false ? '<span class="err">failed</span>' : '') + '</div>';
      }).join('') + '</details>');
  }
  var files = (t.wrote || []).map(function(f){ return [f, 'created']; })
    .concat((t.edited || []).map(function(f){ return [f, 'edited']; }));
  if (files.length){
    parts.push('<div class="wrote">' + files.map(function(x){
      var open = docBy(x[0]) ? ' go" data-doc="' + esc(x[0]) + '"' : '"';
      return '<span class="fchip' + open + ' title="' + esc(x[0]) + '">' +
        '<i>' + x[1] + '</i>' + esc(x[0].split('/').pop()) + '</span>';
    }).join('') + '</div>');
  }
  return parts.length ? '<div class="did">' + parts.join('') + '</div>' : '';
}
function clock(ts){
  var d = new Date(ts * 1000);
  return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
}

/* ── the navigator's three modes ─────────────────────────────────────────── */
function navDocs(){
  marks();
  var docs = libDocs(), all = docs.length;
  if (navQ){
    var s = navQ.toLowerCase();
    docs = docs.filter(function(d){
      return hits(d.rel, navQ) || hits(d.title || '', navQ);
    });
  }
  var sorts = SORTS;
  var sks = statusKeys(D.docs);
  var onCount = LIBFACETS.filter(function(f){ return libFacet[f.k]; }).length + (libStatus ? 1 : 0);
  var narrowed = docs.length !== D.docs.length;
  var TICK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.4" ' +
             'stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5L19 7"/></svg>';

  /* Row one is what the panel *is*: a shape, and a way in to how it is narrowed.
     The count moved out of it — a bare number floating at the end of a control
     row says neither what it counts nor that anything is filtering it. */
  var h = ['<div class="nvctl"><div class="r">' +
    '<div class="seg">' +
      '<button data-lmode="tree" class="' + (libFlat ? '' : 'on') + '">tree</button>' +
      '<button data-lmode="flat" class="' + (libFlat ? 'on' : '') + '">flat</button>' +
    '</div>' +
    (libFlat ? '' :
      '<button class="opt ico" data-tree="open" title="Expand every folder">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" ' +
        'stroke-linecap="round" stroke-linejoin="round"><path d="M7 10l5 5 5-5"/></svg></button>' +
      '<button class="opt ico" data-tree="shut" title="Collapse every folder">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" ' +
        'stroke-linecap="round" stroke-linejoin="round"><path d="M7 14l5-5 5 5"/></svg></button>') +
    '<span class="sp"></span>' +
    '<button class="opt disc' + (navOpts ? ' on' : '') + '" data-navopts="1" ' +
      'title="Sorting and filters">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" ' +
      'stroke-linecap="round" stroke-linejoin="round"><path d="M4 6h16M7 12h10M10 18h4"/></svg>' +
      '<span class="l">sort &amp; filter</span>' +
      (onCount ? '<span class="badge">' + onCount + '</span>' : '') +
    '</button></div>'];

  /* …and one line that says the state in words whether the drawer is open or
     not, so you can tell at a glance that a filter is on. */
  h.push('<div class="sum">' +
    '<span class="' + (narrowed ? 'hit' : '') + '">' +
      (narrowed ? docs.length + ' of ' + D.docs.length : D.docs.length + ' documents') +
    '</span><span class="by">by ' + esc(sortLabel(libSort)) + '</span>' +
    (onCount ? '<button class="lnk" data-lclear="1">clear</button>' : '') +
    '</div>');

  if (navOpts){
    /* A label gutter, so a group name never shares a line with the controls it
       names and nothing wraps raggedly. The navigator is 252px: four text chips
       cannot share a row at that width, which is why the facets are rows. */
    h.push('<div class="drw">');

    h.push('<div class="fgrp"><span class="lbl">sort</span><div class="opts">' +
      sorts.map(function(x){
        return '<button class="chip' + (libSort === x[0] ? ' on' : '') +
               '" data-lsort="' + x[0] + '">' + x[1] + '</button>';
      }).join('') + '</div></div>');

    h.push('<div class="sep"></div>');
    h.push('<div class="fgrp"><span class="lbl">show</span><div class="opts col">' +
      LIBFACETS.map(function(f){
        var on = !!libFacet[f.k], n = libCount(f.k);
        return '<button class="ck' + (on ? ' on' : '') + '" data-lfacet="' + f.k + '">' +
          '<span class="box">' + (on ? TICK : '') + '</span>' +
          '<span class="t">' + f.label + '</span>' +
          '<span class="n">' + n + '</span></button>';
      }).join('') + '</div></div>');

    if (sks.length){
      h.push('<div class="sep"></div>');
      h.push('<div class="fgrp"><span class="lbl">says</span><div class="opts">' +
        sks.map(function(k){
          return '<button class="chip mono' + (libStatus === k ? ' on' : '') +
                 '" data-lstatus="' + esc(k) + '" title="' + libCount(null, k) +
                 ' documents whose front matter says ' + esc(k) + '">' + esc(k) + '</button>';
        }).join('') + '</div></div>');
    }
    h.push('</div>');
  }
  h.push('</div>');
  h.push(docs.length
    ? '<div class="tree">' + ((libFlat || navQ) ? docs.map(fileRow).join('') : libTree(docs)) + '</div>'
    : '<div class="empty">Nothing matches those filters.<br><br>' +
      '<button class="lnk" data-lclear="1">Clear them</button></div>');
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
  if (!D.withSessions) return { html: sessionsOff(), foot:'' };
  if (D.sessionsPending) return { html:'<div class="empty">Reading your history…<br><br>' +
    'Every transcript on this machine, once. The documents are already here.</div>', foot:'' };
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
           foot: Object.keys(D.sessions).length + ' sessions · '
                 + (promptsWithheld() ? 'prompts not in a static page' : D.prompts.length + ' prompts') };
}

function navNotes(){
  marks();
  var items = allAnnos().filter(isLive);
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

/* Two ways to have no history, and only one of them is a dead end. A served
   page can index it here and now; a static page carries what it was built with
   and cannot go and read anything. */
function sessionsOff(){
  if (!can('live'))
    return '<div class="empty">This page was built without your history.<br><br>' +
      'A static page carries only what it was given. Open the workspace with ' +
      '<span class="f">md --sessions</span> to search what you have said.</div>';
  return '<div class="empty">Your Claude Code history is not indexed.<br><br>' +
    'Index it and a topic resolves to the sessions that discussed it and the files ' +
    'they changed — every project on this machine, not only this one.<br><br>' +
    '<button class="lnk" data-wantsessions="1">index it now</button><br><br>' +
    '<span class="f">Reading it takes a couple of seconds and nothing leaves the ' +
    'machine. It stays on for future windows; Settings turns it back off.</span></div>';
}

/* ── All ─────────────────────────────────────────────────────────────────
   One field over three kinds, because when you are looking for something you
   usually remember *what it was about*, not whether you wrote it down, said
   it to Claude, or scribbled it in a margin. */
function navAll(){
  marks();
  var q = allQ.trim(), lq = q.toLowerCase(), h = [], counts = [];
  function hit(s){ return !!s && hits(s, q); }
  if (q && !textAll && can('text')) ensureAllText(function(){ Shell.nav(); });

  var docs = q ? D.docs.filter(function(d){ return hit(d.rel) || hit(d.title) || hit(d.text); })
                       .sort(function(a, b){
                         var an = hit(a.rel.split('/').pop()) ? 1 : 0;
                         var bn = hit(b.rel.split('/').pop()) ? 1 : 0;
                         return bn - an || b.mtime - a.mtime;
                       })
               : D.docs.slice().sort(function(a, b){ return b.mtime - a.mtime; });
  if (docs.length){
    counts.push(docs.length + ' doc' + (docs.length > 1 ? 's' : ''));
    h.push('<div class="grp">Documents <span class="c">' + docs.length + '</span></div>');
    docs.slice(0, q ? 12 : 6).forEach(function(d){ h.push(fileRow(d)); });
  }

  if (D.withSessions){
    var ss = [];
    for (var sid in D.sessions){
      var m = D.sessions[sid];
      if (!q){ ss.push({ sid:sid, m:m, s:0 }); continue; }
      var r = sessionScore(sid, m, q);
      if (r.s) ss.push({ sid:sid, m:m, s:r.s, best:r.best });
    }
    ss.sort(q ? function(a, b){ return b.s - a.s || b.m.b - a.m.b; }
               : function(a, b){ return b.m.b - a.m.b; });
    if (ss.length){
      counts.push(ss.length + ' session' + (ss.length > 1 ? 's' : ''));
      h.push('<div class="grp">Sessions <span class="c">' + ss.length + '</span></div>');
      var cur = curSid();
      ss.slice(0, q ? 10 : 4).forEach(function(x){
        h.push('<div class="srow' + (cur === x.sid ? ' on' : '') + '" data-ses="' + esc(x.sid) +
          '" data-q="' + esc(q) + '" title="' + esc(x.m.t || '') + '">' +
          '<span class="dot ' + (x.m.live ? 'live' : 'arch') + '"></span>' +
          '<span class="ttl">' + esc(x.m.t || '(no prompt recorded)') + '</span>' +
          '<span class="sub">' + esc(shortRepo(x.m.p)) + '</span></div>');
      });
    }
  }

  var notes = allAnnos().filter(function(i){
    return isLive(i) && (!q || hit(i.note) || hit(i.quote) || hit(i.heading));
  }).sort(function(a, b){ return b._doc.mtime - a._doc.mtime || a.lineStart - b.lineStart; });
  if (notes.length){
    counts.push(notes.length + ' note' + (notes.length > 1 ? 's' : ''));
    h.push('<div class="grp">Notes <span class="c">' + notes.length + '</span></div>');
    notes.slice(0, q ? 10 : 4).forEach(function(i){
      h.push('<div class="tfile" data-doc="' + esc(i._doc.rel) + '" data-line="' + (i.lineStart || 0) +
        '" title="' + esc(i.note || i.quote || '') + '">' +
        '<span class="kind">' + esc((i.verb || '').slice(0, 4)) + '</span>' +
        '<span class="nm">' + esc(clip(i.note || i.quote || i.heading || '—', 40)) + '</span>' +
        '<span class="sub">' + esc(i._doc.rel.split('/').pop()) + '</span></div>');
    });
  }

  if (!h.length) h.push('<div class="empty">Nothing matches “' + esc(q) + '”.</div>');
  else if (!q) h.unshift('<div class="nvnote">The most recent of everything. ' +
    'Type to search documents, conversations and your own notes at once.</div>');
  return { html: h.join(''), filter: allQ,
           placeholder: 'Documents, sessions, notes',
           onFilter: function(v){ allQ = v; Shell.nav(); },
           foot: q ? counts.join(' · ') : 'everything, newest first' };
}

function navFor(mode){
  if (mode === 'all') return navAll();
  if (mode === 'sessions') return navSessions();
  if (mode === 'notes') return navNotes();
  return navDocs();
}

/* ── find anything ───────────────────────────────────────────────────────
   Four kinds in one list, because when you are looking for something you
   rarely know which of them it is. */
function palSearch(q, kind){
  q = (q || '').trim();
  /* In serve mode `workspace.py` strips `text` from every document, so the
     palette was matching `undefined` for bodies and reporting the result as a
     confident hit count: on a 330-document corpus, `auth` gave 0 palette rows
     against 132 from the Search surface. Worse, it silently became full-text
     for the rest of the run if you happened to visit the Search surface or the
     All navigator first — two ways to get two different answers to the same
     keystroke. Ask for the bodies, and until they land say so in the sentence
     `searching()` already ships rather than printing a number. */
  if (q && !textAll && can('text')) ensureAllText(function(){ Shell.palRedraw(); });
  var lq = q.toLowerCase(), groups = [], total = 0;
  var partial = q && !textAll && can('text');
  function want(k){ return !kind || kind === k; }
  function hit(s){ return !!s && hits(s, q); }

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
    /* The Sessions navigator has defaulted to this repository since B4, with an
       `everywhere` toggle and an escape hatch for a repo with no history. The
       palette had neither, so ⌘K answered a question about *this* project with
       prompt text from every directory on the machine — twenty of them here —
       and said nothing about where any of it came from. Same default, same
       toggle, same hatch (N4). */
    var ss = [], elsewhere = 0;
    for (var sid in D.sessions){
      var m = D.sessions[sid];
      var here = sesScope !== 'here' || inRepo(m.p);
      if (!q){ if (here) ss.push({ sid:sid, m:m, s:0 }); else elsewhere++; continue; }
      var r = sessionScore(sid, m, q);
      if (!r.s) continue;
      if (here) ss.push({ sid:sid, m:m, s:r.s, best:r.best }); else elsewhere++;
    }
    ss.sort(q ? function(a, b){ return b.s - a.s || b.m.b - a.m.b; }
               : function(a, b){ return b.m.b - a.m.b; });
    total += ss.length;
    var label = (q ? 'Sessions' : 'Recent sessions')
              + (sesScope === 'here' ? ' · this repo' : ' · everywhere');
    if (elsewhere && sesScope === 'here') label += ' · ' + elsewhere + ' more elsewhere (⇧⌘K)';
    groups.push({ label: label, rows: ss.slice(0, 6).map(function(x){
      return { kind:'session', title: clip(x.m.t || '(no prompt recorded)', 64),
               sub: shortRepo(x.m.p) + ' · ' + x.m.n + 'p',
               open: { kind:'session', id:x.sid, q:q, title:clip(x.m.t || x.sid, 30) } };
    }) });
  }

  if (want('note') && q){
    var notes = allAnnos().filter(function(i){
      return isLive(i) && (hit(i.note) || hit(i.quote) || hit(i.heading));
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
           count: !q ? ''
                  : partial ? 'searching the documents…'
                  : total + (total === 1 ? ' hit' : ' hits') };
}

/* ── P5 · the keymap ─────────────────────────────────────────────────────
   The whole workspace keymap existed only in the README — a tool whose
   interface *is* a keymap, failing at its own premise. Ported from the reader's
   ⌘/ sheet: same markup, same classes, this page's keys. */
var KEYS = [
  ['Moving', [
    ['⌘ K', 'find anything — documents, sessions, notes, surfaces'],
    ['⇧ ⌘ K', 'widen a session search past this repository'],
    ['⌘ F', 'search inside the session you are reading'],
    ['⏎ / ⇧ ⏎', 'next / previous match, from the find field'],
    ['/', 'filter the navigator, in whichever mode it is in'],
    ['⌘ 1-9', 'jump to a tab'], ['⌘ ⌥ [ ]', 'previous / next tab'],
    ['⌘ W', 'close the tab'], ['⌘ \\', 'split the pane'], ['⌘ B', 'the navigator'],
    ['⌘ E', 'cycle the navigator modes']
  ]],
  ['Marking', [
    ['j / k', 'move between blocks'], ['c', 'change'], ['?', 'question'],
    ['x', 'cut'], ['e', 'expand'], ['n', 'note'], ['a', 'approve'],
    ['f', 'the feedback panel'], ['⌘ ⏎', 'copy the feedback'],
    ['esc', 'close what is open']
  ]],
  ['This page', [
    ['r', 'reindex'], ['t', 'light / dark'], ['?', 'this sheet']
  ]]
];
var KEYS_NOTE =
  '<b>⌘F is deliberately not bound.</b> It falls through to the browser\'s own ' +
  'find bar, which already has a hit count, next and previous, and wrap-around — ' +
  'and searches the page you are actually looking at. The reader binds ⌘F because ' +
  'it has one document; this page does not because it has several.';
function drawKeys(){
  var c = document.getElementById('keys-cols');
  if (!c || c.dataset.done) return;
  c.innerHTML = KEYS.map(function(g){
    return '<div class="grp"><b>' + esc(g[0]) + '</b>' + g[1].map(function(r){
      return '<div class="row"><kbd>' + r[0] + '</kbd><span>' + esc(r[1]) + '</span></div>';
    }).join('') + '</div>';
  }).join('') + '<div class="note" style="grid-column:1/-1">' + KEYS_NOTE + '</div>';
  c.dataset.done = '1';
}
function toggleKeys(on){
  var k = document.getElementById('keys');
  if (!k) return;
  drawKeys();
  k.hidden = on === undefined ? !k.hidden : !on;
  if (!k.hidden) { var x = document.getElementById('keys-x'); if (x) x.focus(); }
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
  out.push({ label:'Keys', key:'?', run: function(){ toggleKeys(true); } });
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
/* A static page carries no prompts: `bin/md` refuses --out with --sessions
   because your history stays on this machine, and baking the same corpus into a
   cached .html was the same disclosure by another route (N2). The cost is real,
   so the surfaces that used to search prompts say which kind of empty they are
   rather than returning nothing. */
function promptsWithheld(){ return D.withSessions && !D.prompts.length && D.promptsWithheld > 0; }
function withheldNote(){
  return '<div class="empty">Prompt search needs the live workspace. This page is static, '
       + 'so the ' + D.promptsWithheld.toLocaleString() + ' prompts behind these sessions '
       + 'were left out of it deliberately \u2014 run <code>md --sessions</code> without '
       + '<code>--static</code> to search them.</div>';
}

/* the last note that failed to reach disk, if any — held until one succeeds */
var noteFail = '', noteWhy = '';
function noteTrouble(name, why){
  if (noteFail === name && noteWhy === why) return;
  noteFail = name; noteWhy = why || '';
  if (name) console.error('rubricator: could not write notes for ' + name +
                          (why ? ' — ' + why : ' to .rubricator/notes/'));
  stat();
}

function stat(){
  var bits = [can('watch') ? 'watching for changes' : (can('live') ? 'served locally' : 'a static page')];
  bits.push('indexed in ' + D.took + 's');
  if (D.sessionsPending) bits.push('<span class="busy">reading your history…</span>');
  else if (D.withSessions) bits.push(Object.keys(D.sessions).length + ' sessions');
  /* the archive is on a thirty-day fuse and the Sessions list cannot say so on
     its own: a row marked archived looks like rubricator lost it. The ratio is
     counted from history.jsonl, which outlives the transcripts. */
  var R = D.retention;
  if (R && R.lost) bits.push(R.readable + '/' + R.known + ' readable');
  if (noteFail) bits.push('<b class="warn" title="' + esc(noteWhy ||
      'The server refused the write. Your marks are in this browser only until it succeeds.') +
      '">notes for ' + esc(noteFail) + ' are not on disk</b>');
  Shell.status(bits.join(' · '),
    R && R.lost
      ? R.lost + ' of ' + R.known + ' sessions can be found but not read — Claude Code '
        + 'removes transcripts after 30 days. Raise ' + R.setting + ' in '
        + '~/.claude/settings.json to keep them longer.'
      : '');
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

/* ── history arrives after the window ──────────────────────────────────────
   The documents are indexed in a tenth of a second and the transcripts in two,
   so the window opens on the documents and this is the one request that waits.
   `ask` is the empty state's button: the server was started without history and
   is being told to go and read it. */
function indexSessions(ask){
  if (!can('live')) return;
  if (ask){ D.withSessions = 1; D.sessionsPending = 1; Shell.nav(); }
  api('sessions', ask ? {} : undefined, function(j){
    if (!j || !j.withSessions){ D.withSessions = 0; D.sessionsPending = 0; return refreshAll(); }
    D.sessions = j.sessions || {};
    D.prompts = j.prompts || [];
    D.touches = j.touches || {};
    if (j.retention !== undefined) D.retention = j.retention;
    if (j.deep !== undefined) D.deep = j.deep;
    D.withSessions = 1;
    D.sessionsPending = j.pending ? 1 : 0;
    byS = null;
    scopeToWhatExists();
    Shell.nav(); refreshAll();
    if (ask) toast(Object.keys(D.sessions).length + ' sessions indexed');
  }, function(){
    D.sessionsPending = 0;
    toast('could not read your history');
    Shell.nav();
  });
}

/* Default to `everywhere` in a repository with no history of its own — with
   `this repo` it would open on a list of nothing. Runs again when a deferred
   index lands, because at first paint there is nothing to count. */
function scopeToWhatExists(){
  if (!D.withSessions) return;
  for (var k in D.sessions){ if (inRepo(D.sessions[k].p)) return; }
  sesScope = 'all';
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
  var uf = e.target.closest('.unfold');
  if (uf){
    var body = uf.previousElementSibling;
    if (body) body.classList.contains('open') ? refold(body) : unfold(body);
    return;
  }
  var seg = e.target.closest('[data-lmode],[data-lsort],[data-lfacet],[data-sscope],[data-slive]');
  if (seg){
    var d = seg.dataset;
    if (d.lmode)  libFlat = d.lmode === 'flat';
    if (d.lsort)  libSort = d.lsort;
    if (d.lfacet) libFacet[d.lfacet] = !libFacet[d.lfacet];
    if (d.lstatus) libStatus = libStatus === d.lstatus ? '' : d.lstatus;
    if (d.lclear){ libFacet = {}; libStatus = ''; }
    if (d.sscope) sesScope = d.sscope;
    if (d.slive)  sesLive = !sesLive;
    return Shell.nav();
  }
  /* the same move as the Settings toggle, because the empty state promises the
     same thing: on now, and on the next time you open a window */
  if (e.target.closest('[data-wantsessions]'))
    return setOne('sessions', true, 'indexing your history…',
                  function(){ indexSessions(true); });
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
    var note = null, then = null;
    if (key === 'terminal')
      note = 'sessions will open in ' + (raw ? raw.replace('.app','') : 'whatever ran md');
    /* turning history on is not a promise about the next window: this one goes
       and reads it. Turning it off leaves this window as it is — throwing away
       an index you are looking at would be a strange way to store a preference */
    if (key === 'sessions')
      if (val){ note = 'indexing your history…'; then = function(){ indexSessions(true); }; }
      else note = 'off from the next window on';
    return setOne(key, val, note, then);
  }
  if (e.target.closest('[data-seteditor]')){
    var f = $('s-editor');
    return setOne('editor', f ? f.value.trim() : '', 'editor saved');
  }
  if (e.target.closest('[data-navopts]')){ navOpts = !navOpts; return Shell.nav(); }
  var tw = e.target.closest('[data-tree]');
  if (tw){
    var shut = tw.dataset.tree === 'shut';
    libDirs(libDocs()).forEach(function(d){ libOpen[d] = !shut; });
    return Shell.nav();
  }
  var dir = e.target.closest('[data-dir]');
  if (dir){
    libOpen[dir.dataset.dir] = libOpen[dir.dataset.dir] === false;
    return Shell.nav();
  }
  var ab = e.target.closest('[data-act]');
  if (ab) return act(ab.dataset.act, ab.dataset.id, '',
                     ab.dataset.act === 'fork' ? 'forking in a new terminal window'
                                               : 'resuming in a new terminal window');
  /* ── the files a session changed ─────────────────────────────────────── */
  var kb = e.target.closest('[data-fkind]');
  if (kb){
    var kk = kb.dataset.fg;
    sesKind[kk] = sesKind[kk] === kb.dataset.fkind ? '' : kb.dataset.fkind;
    return Shell.refresh();
  }
  var fd = e.target.closest('[data-fdir]');
  if (fd){
    var fk = fd.dataset.fg;
    if (!sesOpen[fk]) sesOpen[fk] = {};
    sesOpen[fk][fd.dataset.fdir] = !sesOpen[fk][fd.dataset.fdir];
    return Shell.refresh();
  }
  var fa = e.target.closest('[data-fall],[data-fnone]');
  if (fa){
    var ak = fa.dataset.fg, want = !!fa.dataset.fall, o = {};
    if (want){
      /* the folder names are in the DOM already; asking it beats threading the
         list through a data attribute on every button */
      [].forEach.call(document.querySelectorAll('[data-fdir][data-fg="' + ak + '"]'),
                      function(el){ o[el.dataset.fdir] = true; });
    }
    sesOpen[ak] = o;
    if (!want) sesKind[ak] = '';
    return Shell.refresh();
  }
  var fx = e.target.closest('[data-fact]');
  if (fx) return act(fx.dataset.fact, fx.dataset.sid, '',
                     fx.dataset.fact === 'reveal-file' ? 'revealed in Finder'
                                                       : 'opened in your editor',
                     { n: +fx.dataset.n });

  var cmd = e.target.closest('[data-copy]');
  if (cmd){ copy(cmd.dataset.copy);
    return toast(cmd.dataset.copyNote || 'copied — paste it into a terminal'); }

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
    var ks = document.getElementById('keys');
    if (ks && !ks.hidden){ ks.hidden = true; return; }
    var tray = $('tray'), t = Shell.active();
    if (tray.classList.contains('open') && (!t || t.kind !== 'doc')) $('tray-close').click();
    return;
  }
  if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === '/'){
    /* P5 · `/` used to knock the navigator out of Notes mode before focusing
       the filter, so the one keystroke for "filter what I am looking at" could
       not filter notes — the only mode where you are hunting your own words. */
    e.preventDefault();
    Shell.nav();
    var i = $('nvq-i');
    if (i) i.focus(); else Shell.palette(true);
    return;
  }
  if (e.key === '?'){
    /* `?` is also the Question verb. The review layer owns it while a document
       is on screen, and only then — so the sheet takes the key from the lists,
       where nothing else wants it, and never out from under a mark. */
    var at = Shell.active();
    if (at && at.kind === 'doc') return;
    e.preventDefault(); return toggleKeys();
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

scopeToWhatExists();
if (D.sessionsPending) indexSessions(false);

/* ── go ─────────────────────────────────────────────────────────────────── */
/* the sheet's own controls */
['keys-x'].forEach(function(id){
  var b = document.getElementById(id);
  if (b) b.addEventListener('click', function(){ toggleKeys(false); });
});
(function(){
  var k = document.getElementById('keys');
  if (k) k.addEventListener('click', function(e){ if (e.target === k) toggleKeys(false); });
})();

var restored = Shell.init({
  storeKey: 'rubricator:layout:' + hash(D.root),
  make: makeSurface, spec: specFor, nav: navFor, search: palSearch,
    /* ⇧⌘K in the palette presses the `everywhere` button in the Sessions
       navigator: one scope behind both surfaces (N4). It only ever widens —
       the key is called widen, the row that advertises it says "search
       everywhere", and narrowing again is one click on a control that is
       always on screen. */
    widen: function(){ sesScope = 'all'; Shell.nav(); }, menu: menuItems,
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
