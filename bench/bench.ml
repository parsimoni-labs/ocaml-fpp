(** Benchmark for ofpp analysis pipeline. *)

let collect_fpp_files dir =
  let files = ref [] in
  let rec walk d =
    let entries = Sys.readdir d in
    Array.iter
      (fun entry ->
        let path = Filename.concat d entry in
        if Sys.is_directory path then walk path
        else if Filename.check_suffix path ".fpp" then files := path :: !files)
      entries
  in
  if Sys.file_exists dir && Sys.is_directory dir then walk dir;
  List.rev !files

let time_ns f =
  let t0 = Sys.time () in
  let result = f () in
  let t1 = Sys.time () in
  (result, (t1 -. t0) *. 1e9)

let parse files =
  let n = List.length files in
  let parsed = ref 0 in
  let failed = ref 0 in
  let tus =
    List.filter_map
      (fun file ->
        match Fpp.parse_file file with
        | tu ->
            incr parsed;
            Some tu
        | exception _ ->
            incr failed;
            Fmt.pr "  FAIL: %s@." file;
            None)
      files
  in
  Fmt.pr "  parsed: %d/%d files (%d failed)@." !parsed n !failed;
  tus

let check tus =
  let n_diags = ref 0 in
  let n_errors = ref 0 in
  let n_warnings = ref 0 in
  List.iter
    (fun tu ->
      let diags = Fpp.Check.run Fpp.Check.default tu in
      List.iter
        (fun (d : Fpp.Check.diagnostic) ->
          incr n_diags;
          match d.severity with
          | `Error -> incr n_errors
          | `Warning -> incr n_warnings)
        diags)
    tus;
  Fmt.pr "  diagnostics: %d (%d errors, %d warnings)@." !n_diags !n_errors
    !n_warnings

let () =
  Memtrace.trace_if_requested ();
  let upstream_dir =
    let candidates =
      [
        "test/upstream";
        "../test/upstream";
        Filename.concat
          (Filename.dirname Sys.executable_name)
          "../test/upstream";
      ]
    in
    match List.find_opt Sys.file_exists candidates with
    | Some d -> d
    | None ->
        Fmt.epr "error: cannot find test/upstream directory@.";
        exit 1
  in
  let files = collect_fpp_files upstream_dir in
  Fmt.pr "benchmark: %d FPP files from %s@." (List.length files) upstream_dir;
  let iters = 100 in
  (* Phase 1: parse *)
  let tus, parse_ns = time_ns (fun () -> parse files) in
  Fmt.pr "  parse (1x):  %.2f ms@." (parse_ns /. 1e6);
  (* Phase 2: check *)
  let (), check_ns = time_ns (fun () -> check tus) in
  Fmt.pr "  check (1x):  %.2f ms@." (check_ns /. 1e6);
  (* Phase 3: repeated check for stable measurement *)
  let (), total_ns =
    time_ns (fun () ->
        for _ = 1 to iters do
          List.iter (fun tu -> ignore (Fpp.Check.run Fpp.Check.default tu)) tus
        done)
  in
  let per_iter_us = total_ns /. Float.of_int iters /. 1e3 in
  Fmt.pr "  check (%dx): %.2f ms total, %.1f us/iter@." iters (total_ns /. 1e6)
    per_iter_us;
  Fmt.pr "  throughput:  %.0f files/s (check only)@."
    (Float.of_int (List.length tus) /. (per_iter_us /. 1e6))
