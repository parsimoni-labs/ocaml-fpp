(** FPP topology to F Prime Visual JSON.

    Produces JSON files compatible with
    {{:https://github.com/fprime-community/fprime-visual}fprime-visual}, the
    browser-based topology visualiser for F Prime. Component instances are
    assigned to columns via longest-path layering, with their ports and
    connections encoded as index-based tuples.

    {2 Example}

    {[
      let tu = Fpp.parse_file "model.fpp" in
      let topo = List.hd (Fpp.topologies tu) in
      Fpp.Fpv.pp_topology tu Format.std_formatter topo
    ]} *)

val pp_topology : Ast.translation_unit -> Ast.def_topology Fmt.t
(** [pp_topology tu] is a pretty-printer for topology definitions as
    FPV-compatible JSON. The topology is flattened (imports resolved) before
    rendering. Instances are laid out in columns using longest-path layering;
    connections reference instances and ports by index. *)
