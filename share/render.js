/* md renderer — markdown source into the reader's DOM.
   Shared by the single-file reader and the workspace pane, so a document looks
   and behaves the same wherever it is opened. Everything downstream (the review
   layer's line mapping, the outline, search) assumes this exact output. */
(function(){
"use strict";

function esc(s){
  return String(s == null ? '' : s).replace(/[&<>"]/g, function(c){
    return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];
  });
}

/* ── the document is untrusted ────────────────────────────────────────────
   Markdown carries raw HTML, and a document can come from anywhere — a repo you
   cloned, a plan an agent wrote, a file someone sent you. Rendered into a page
   that can talk to a local server, an <img onerror> is not a curiosity.

   Sanitising happens inside a <template>, whose content is inert: images do not
   load and handlers do not fire, so nothing runs before it is stripped. */
var BAD_TAGS = { SCRIPT:1, IFRAME:1, FRAME:1, OBJECT:1, EMBED:1, LINK:1, META:1,
                 BASE:1, FORM:1, STYLE:1, PORTAL:1 };

function unsafeUrl(v){
  var u = String(v || '').replace(/[\u0000-\u0020]/g, '').toLowerCase();
  if (u.indexOf('javascript:') === 0 || u.indexOf('vbscript:') === 0) return true;
  if (u.indexOf('data:') === 0 && u.indexOf('data:image/') !== 0) return true;
  return false;
}

function sanitise(node){
  var els = node.querySelectorAll('*'), i, j;
  for (i = els.length - 1; i >= 0; i--){
    var el = els[i];
    if (BAD_TAGS[el.tagName]){ el.remove(); continue; }
    var at = el.attributes;
    for (j = at.length - 1; j >= 0; j--){
      var name = at[j].name, low = name.toLowerCase();
      if (low.indexOf('on') === 0 || low === 'srcdoc' || low === 'formaction'){
        el.removeAttribute(name);
      } else if ((low === 'href' || low === 'src' || low === 'action' ||
                  low === 'poster' || low === 'srcset' || low === 'xlink:href') &&
                 unsafeUrl(at[j].value)){
        el.removeAttribute(name);
      }
    }
  }
  return node;
}

var COPY = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>';
var OK   = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>';
var ALERT_ICON = { note:'ℹ', tip:'✦', important:'❖', warning:'▲', caution:'⚠' };

/* front matter is split off before parsing: it is metadata, not content, and
   counting its lines is what keeps every later line number honest */
function splitFrontMatter(raw){
  var m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(raw);
  if (!m) return { body: raw, lines: 0, html: '' };
  var rows = m[1].split(/\r?\n/).filter(function(l){ return /^[A-Za-z0-9_.-]+\s*:/.test(l); });
  var html = '';
  if (rows.length) {
    html = '<dl class="fm">' + rows.map(function(l){
      var i = l.indexOf(':');
      return '<dt>' + esc(l.slice(0, i).trim()) + '</dt><dd>' +
             esc(l.slice(i + 1).trim().replace(/^["']|["']$/g, '')) + '</dd>';
    }).join('') + '</dl>';
  }
  return { body: raw.slice(m[0].length), lines: m[0].split('\n').length - 1, html: html };
}

function resolveUrls(doc, base){
  if (!base) return;
  function abs(u){ try { return new URL(u, base).href; } catch(e){ return u; } }
  doc.querySelectorAll('img[src],a[href],source[src],source[srcset],video[src],video[poster]')
    .forEach(function(el){
      var attr = el.hasAttribute('src') ? 'src' : (el.hasAttribute('href') ? 'href' : null);
      if (!attr) return;
      var v = el.getAttribute(attr);
      if (!v || v.charAt(0) === '#') return;
      el.setAttribute(attr, abs(v));
    });
}

function headingIds(doc){
  var used = {}, list = [];
  doc.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(h){
    var slug = h.textContent.toLowerCase().trim()
      .replace(/[^\wÀ-ɏЀ-ӿ\- ]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-') || 'section';
    if (used[slug] != null) { used[slug]++; slug += '-' + used[slug]; } else used[slug] = 0;
    h.id = slug;
    var a = document.createElement('a');
    a.className = 'anchor'; a.href = '#' + slug; a.textContent = '#';
    a.setAttribute('aria-hidden', 'true');
    h.insertBefore(a, h.firstChild);
    list.push(h);
  });
  return list;
}

function alerts(doc){
  doc.querySelectorAll('blockquote').forEach(function(bq){
    var p = bq.querySelector('p'); if (!p) return;
    var m = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*/i.exec(p.textContent);
    if (!m) return;
    var kind = m[1].toLowerCase();
    p.innerHTML = p.innerHTML.replace(/^\[!\w+\]\s*(<br\s*\/?>)?\s*/i, '');
    bq.classList.add('alert', kind);
    var t = document.createElement('div');
    t.className = 'alert-t';
    t.textContent = ALERT_ICON[kind] + ' ' + kind.charAt(0).toUpperCase() + kind.slice(1);
    bq.insertBefore(t, bq.firstChild);
    if (!p.textContent.trim() && !p.querySelector('img,code')) p.remove();
  });
}

function taskLists(doc){
  doc.querySelectorAll('li').forEach(function(li){
    var cb = li.querySelector(':scope > input[type=checkbox]');
    if (!cb) return;
    li.classList.add('task');
    if (cb.checked) li.classList.add('done');
  });
}

/* tables and code blocks get a wrapper each. The wrapper takes the element's
   place in the child list, so the block-to-line mapping still lines up. */
function tables(doc){
  doc.querySelectorAll('table').forEach(function(t){
    var w = document.createElement('div'); w.className = 'table-wrap';
    t.parentNode.insertBefore(w, t); w.appendChild(t);
  });
}

function codeBlocks(doc){
  var mermaids = [];
  doc.querySelectorAll('pre > code').forEach(function(code){
    var pre = code.parentNode;
    var cls = (code.className.match(/language-([\w+#-]+)/) || [])[1] || '';
    if (cls === 'mermaid') {
      var d = document.createElement('div');
      d.className = 'mermaid'; d.textContent = code.textContent;
      pre.parentNode.replaceChild(d, pre);
      mermaids.push(d);
      return;
    }
    var wrap = document.createElement('div'); wrap.className = 'code-block';
    pre.parentNode.insertBefore(wrap, pre); wrap.appendChild(pre);
    if (cls) {
      var l = document.createElement('span'); l.className = 'lang'; l.textContent = cls;
      wrap.appendChild(l);
    }
    var b = document.createElement('button');
    b.className = 'btn copy'; b.innerHTML = COPY; b.title = 'Copy';
    b.addEventListener('click', function(){
      navigator.clipboard.writeText(code.textContent).then(function(){
        b.innerHTML = OK; b.classList.add('ok');
        setTimeout(function(){ b.innerHTML = COPY; b.classList.remove('ok'); }, 1400);
      });
    });
    wrap.appendChild(b);
    if (window.hljs) { try { hljs.highlightElement(code); } catch(e){} }
  });
  return mermaids;
}

/* mermaid is configured once from the live CSS variables, then run per document */
var mermaidReady = false;
function initMermaid(){
  if (mermaidReady || !window.mermaid) return;
  var cs = getComputedStyle(document.documentElement);
  var v = function(n){ return cs.getPropertyValue(n).trim(); };
  var dark = document.documentElement.getAttribute('data-mode') !== 'light';
  mermaid.initialize({ startOnLoad:false, theme: dark ? 'dark' : 'default', securityLevel:'strict',
    themeVariables:{
      fontFamily:'-apple-system,BlinkMacSystemFont,"SF Pro Text",Inter,system-ui,sans-serif',
      fontSize:'14px',
      background: v('--bg-soft'),
      primaryColor: v('--bg-elev'), primaryTextColor: v('--fg'), primaryBorderColor: v('--border'),
      secondaryColor: v('--bg-soft'), tertiaryColor: v('--bg-soft'),
      lineColor: v('--fg-dim'), textColor: v('--fg'),
      mainBkg: v('--bg-elev'), nodeBorder: v('--border'),
      clusterBkg: v('--bg-soft'), clusterBorder: v('--border-soft'),
      edgeLabelBackground: v('--bg-soft'),
      titleColor: v('--fg'), noteBkgColor: v('--bg-elev'), noteTextColor: v('--fg-muted')
    } });
  mermaidReady = true;
}

/* o: { doc, fm, raw, base, onReady } → { body, fmLines, headings } */
function render(o){
  var doc = o.doc;
  var fm  = splitFrontMatter(o.raw);

  marked.setOptions({ gfm:true, breaks:false });
  if (o.fm) o.fm.innerHTML = fm.html;              // built here, already escaped
  var tpl = document.createElement('template');
  tpl.innerHTML = marked.parse(fm.body);
  sanitise(tpl.content);
  doc.textContent = '';
  doc.appendChild(tpl.content);

  resolveUrls(doc, o.base);
  var headings = headingIds(doc);
  alerts(doc);
  taskLists(doc);
  tables(doc);
  var mermaids = codeBlocks(doc);

  if (mermaids.length && window.mermaid) {
    initMermaid();
    try {
      mermaid.run({ nodes: mermaids }).then(function(){
        if (o.onReady) o.onReady();
      }).catch(function(){ if (o.onReady) o.onReady(); });
    } catch(e){ if (o.onReady) o.onReady(); }
  } else if (o.onReady) {
    o.onReady();
  }

  return { body: fm.body, fmLines: fm.lines, headings: headings };
}

/* ── themes ───────────────────────────────────────────────────────────────
   Three palettes; each is either light or dark, and a few rules need to know
   which. Older pages stored "dark" and "light" — those still resolve. */
var THEMES = { rubric:'dark', slate:'dark', bone:'light' };
var LEGACY = { dark:'rubric', light:'bone' };
function theme(name){ return THEMES[name] ? name : (LEGACY[name] || 'rubric'); }
function current(){ return theme(document.documentElement.getAttribute('data-theme')); }
function setTheme(name){
  name = theme(name);
  var r = document.documentElement;
  r.setAttribute('data-theme', name);
  r.setAttribute('data-mode', THEMES[name]);
  try { localStorage.setItem('md-theme', name); } catch(e){}
  return name;
}
function nextTheme(){
  var k = Object.keys(THEMES);
  return k[(k.indexOf(current()) + 1) % k.length];
}
function restoreTheme(fallback){
  var saved = null;
  try { saved = localStorage.getItem('md-theme'); } catch(e){}
  if (saved || fallback) setTheme(saved || fallback);
  else setTheme(current());          // still normalise what the page was built with
}

/* A PDF or a Word file has no markdown source to map, so the blocks are made
   here and a source is synthesised from them: one paragraph per block, joined
   the way the block boundaries imply. The review layer then anchors, quotes and
   exports exactly as it does for markdown, without knowing the difference. */
function renderExtracted(o){
  var doc = o.doc, i;
  doc.textContent = '';
  if (o.html){
    var tpl = document.createElement('template');
    tpl.innerHTML = o.html;
    sanitise(tpl.content);
    doc.appendChild(tpl.content);
  } else {
    /* Blank lines are the obvious paragraph break, but textutil hands back Word
       documents with none at all and a PDF page arrives as one blob. So a part
       that is long and has line breaks of its own is split on those too —
       otherwise a 44,000-character document is three blocks you cannot mark up. */
    var parts = [];
    String(o.text || '').split(/\n{2,}/).forEach(function(part){
      if (part.length > 400 && part.indexOf('\n') >= 0) parts = parts.concat(part.split('\n'));
      else parts.push(part);
    });
    for (i = 0; i < parts.length; i++){
      var t = parts[i].replace(/\s+$/, '');
      if (!t) continue;
      var head = /^(#{1,6})\s+(.*)$/.exec(t);
      var el;
      if (head){
        el = document.createElement('h' + Math.min(6, head[1].length));
        el.textContent = head[2];
      } else {
        el = document.createElement('p');
        el.textContent = t;
        el.style.whiteSpace = 'pre-wrap';       // extracted text keeps its breaks
      }
      doc.appendChild(el);
    }
  }
  tables(doc);

  /* the source is synthesised from the blocks, so it has to be read before
     headingIds() puts an anchor character inside every heading */
  var raw = [], line = 1;
  for (i = 0; i < doc.children.length; i++){
    var b = doc.children[i];
    var txt = (b.textContent || '').replace(/\s+$/, '');
    var n = txt.split('\n').length;
    b.dataset.lineStart = line;
    b.dataset.lineEnd = line + n - 1;
    raw.push(txt);
    line += n + 1;
  }
  headingIds(doc);
  return { raw: raw.join('\n\n'), fmLines: 0 };
}

window.MD = { render: render, renderExtracted: renderExtracted, esc: esc, sanitise: sanitise, themes: THEMES, theme: current,
              setTheme: setTheme, nextTheme: nextTheme, restoreTheme: restoreTheme };
})();
