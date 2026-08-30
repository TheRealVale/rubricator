/* rubricator kit — the small framework the surfaces are written in, and the
   half of `window.RB` that a view you wrote yourself is handed.

   Two ideas, both of them answers to a way this page has actually broken.

   `html` builds markup out of a tagged template and escapes every hole in it,
   so escaping is what happens when you do nothing rather than something you
   have to remember at each of several hundred interpolations. Markup you have
   already built passes through untouched; markup you vouch for goes through
   `trust`, which is the only way raw HTML gets in and therefore the only thing
   an audit has to read.

   `table` turns a set of `data-` verbs into a click handler whose selector is
   derived from the verbs themselves. The bug it exists to make impossible was
   a handler added to the body of the dispatcher while the selector that has to
   match first was left alone: three buttons in the navigator that could not be
   clicked, in a file where nothing failed and no test noticed. */
(function(){
"use strict";

/* ── markup ───────────────────────────────────────────────────────────── */

/* `'` is escaped as well as the four that matter for double-quoted attributes,
   because a view someone else wrote may well quote an attribute the other way
   and the cost of covering it is one character in a character class. */
var ESCAPES = { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' };
function esc(s){
  return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){ return ESCAPES[c]; });
}

/* the marker that says "this is markup, not text". `html` returns one, so a
   template nests in a template without being escaped a second time. */
function trust(s){ return { __html: String(s == null ? '' : s) }; }

/* every hole in a template goes through here. An array flattens — the surfaces
   are written as `list.map(row)` and that should read as itself rather than as
   `.join('')` at the end of every line. `null`, `undefined` and both booleans
   render as nothing, which is what makes `${n && html`…`}` say what it looks
   like it says. */
function fuse(v){
  if (v == null || v === false || v === true) return '';
  if (v.__html != null) return v.__html;
  if (Array.isArray(v)){
    var out = '';
    for (var i = 0; i < v.length; i++) out += fuse(v[i]);
    return out;
  }
  return esc(v);
}

function html(parts){
  var out = parts[0];
  for (var i = 1; i < arguments.length; i++) out += fuse(arguments[i]) + parts[i];
  return { __html: out };
}

/* ── clicking ─────────────────────────────────────────────────────────── */

/* `data-fooBar` in a dataset is `data-foo-bar` in a selector */
function dash(k){ return k.replace(/[A-Z]/g, function(c){ return '-' + c.toLowerCase(); }); }

/* A table of verbs. `spec` maps a dataset key to what that verb does; the
   handler gets the attribute's value, the element carrying it and the event.
   `after` runs once if anything fired, which is where the redraw goes.

   Every verb on the matched element fires, not just the first — the navigator's
   controls share a row and a redraw, and a chip that sets two things at once
   should not have to say so twice. */
function table(spec, after){
  var keys, sel;
  function rebuild(){
    keys = Object.keys(spec);
    sel = keys.map(function(k){ return '[data-' + dash(k) + ']'; }).join(',');
  }
  rebuild();
  function run(e){
    if (!sel) return false;
    var el = e.target.closest(sel);
    if (!el) return false;
    var hit = false;
    for (var i = 0; i < keys.length; i++){
      var v = el.dataset[keys[i]];
      if (v === undefined) continue;
      spec[keys[i]](v, el, e);
      hit = true;
    }
    if (hit && after) after();
    return hit;
  }
  /* a verb registered after the fact — this is what a view of your own gets */
  run.on = function(key, fn){ spec[key] = fn; rebuild(); return run; };
  run.has = function(key){ return Object.prototype.hasOwnProperty.call(spec, key); };
  run.selector = function(){ return sel; };
  run.verbs = function(){ return keys.slice(); };
  return run;
}

/* The page's own API. workspace.js adds the half that needs the index — data,
   view, open, toast — to the same object, so a view you wrote yourself has one
   place to look. */
window.RB = { html: html, trust: trust, esc: esc, fuse: fuse, table: table };
})();
