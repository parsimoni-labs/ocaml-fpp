(* Generate doc/gallery/index.html from .fpp + .svg pairs. *)

let entries =
  [
    ("thermostat", "Thermostat", "Guarded transitions with actions");
    ("deploy", "Deploy Sequence", "Nested states with choices");
    ("fan_out", "Fan-Out", "One state fans out to many targets");
    ("self_loops", "Self-Loops", "Multiple self-transitions on one state");
    ("choice_chain", "Choice Chain", "Cascading choices before reaching a state");
    ("deep_nesting", "Deep Nesting", "Three levels of nested states");
    ("spaghetti", "Spaghetti", "Every state connects to every other");
  ]

let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let escape_html s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string buf "&amp;"
      | '<' -> Buffer.add_string buf "&lt;"
      | '>' -> Buffer.add_string buf "&gt;"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

let () =
  let dir = Sys.argv.(1) in
  print_string
    {|<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ofpp Gallery</title>
<link rel="stylesheet"
  href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script>
// Custom FPP language definition for highlight.js
hljs.registerLanguage('fpp', function(hljs) {
  return {
    name: 'FPP',
    case_insensitive: false,
    keywords: {
      keyword: 'state machine signal action guard initial enter on if else do choice entry exit',
      type: 'bool string U8 U16 U32 U64 I8 I16 I32 I64 F32 F64',
    },
    contains: [
      hljs.COMMENT('@', '$'),
      hljs.QUOTE_STRING_MODE,
      hljs.C_NUMBER_MODE,
      { className: 'punctuation', begin: /[{}(),]/ },
    ]
  };
});
</script>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #f5f5f5; color: #1a1a2e;
         max-width: 1400px; margin: 0 auto; padding: 2rem; }
  h1 { margin-bottom: 0.5rem; }
  .subtitle { color: #666; margin-bottom: 2rem; }
  .entry { background: #fff; border-radius: 12px; box-shadow: 0 1px 3px rgba(0,0,0,0.1);
           margin-bottom: 2rem; overflow: hidden; }
  .entry-header { padding: 1rem 1.5rem; border-bottom: 1px solid #eee; }
  .entry-header h2 { font-size: 1.2rem; }
  .entry-header p { color: #666; font-size: 0.9rem; margin-top: 0.25rem; }
  .entry-body { display: grid; grid-template-columns: 1fr 1fr; }
  .entry-code { border-right: 1px solid #eee; overflow: auto; max-height: 600px; }
  .entry-code pre { margin: 0; padding: 1rem; font-size: 0.85rem; }
  .entry-svg { display: flex; align-items: flex-start; justify-content: center;
               padding: 1rem; overflow: auto; max-height: 600px; background: #fafafa; }
  .entry-svg svg { max-width: 100%; height: auto; cursor: zoom-in; }
  .overlay { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.85);
             z-index: 100; cursor: zoom-out; overflow: auto; }
  .overlay.active { display: flex; align-items: center; justify-content: center; }
  .overlay svg { max-width: 95vw; max-height: 95vh; width: auto; height: auto;
                 background: #fff; border-radius: 8px; padding: 1rem; }
  @media (max-width: 900px) {
    .entry-body { grid-template-columns: 1fr; }
    .entry-code { border-right: none; border-bottom: 1px solid #eee; }
  }
</style>
</head>
<body>
<h1>ofpp dot</h1>
<p class="subtitle">State machine diagrams rendered from FPP. Source on the left, SVG on the right.</p>
|};
  List.iter
    (fun (name, title, desc) ->
      let fpp_path = Filename.concat dir (name ^ ".fpp") in
      let svg_path = Filename.concat dir (name ^ ".svg") in
      let fpp_src =
        if Sys.file_exists fpp_path then escape_html (read_file fpp_path)
        else "(source not found)"
      in
      let svg_content =
        if Sys.file_exists svg_path then read_file svg_path
        else "<p>SVG not found</p>"
      in
      Fmt.pr
        {|<div class="entry">
<div class="entry-header">
  <h2>%s</h2>
  <p>%s</p>
</div>
<div class="entry-body">
  <div class="entry-code">
    <pre><code class="language-fpp">%s</code></pre>
  </div>
  <div class="entry-svg">
    %s
  </div>
</div>
</div>
|}
        title desc fpp_src svg_content)
    entries;
  print_string
    {|<div class="overlay" id="overlay" onclick="this.classList.remove('active')"></div>
<script>
hljs.highlightAll();
document.querySelectorAll('.entry-svg').forEach(function(el) {
  el.addEventListener('click', function() {
    var overlay = document.getElementById('overlay');
    overlay.innerHTML = el.innerHTML;
    overlay.classList.add('active');
  });
});
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') document.getElementById('overlay').classList.remove('active');
});
</script>
</body>
</html>
|}
