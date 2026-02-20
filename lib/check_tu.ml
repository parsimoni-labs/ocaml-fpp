(** Translation-unit-level semantic checks.

    Runs checks across the full translation unit: redefinitions, symbol kind
    validation, dependency cycles, expression evaluation, component member
    validation, and instance/topology checks. This module is internal to the
    [fpp] library. *)

let run ~unconnected ~sync_cycle members =
  let scope = "<tu>" in
  let tu_env = Check_tu_env.build_tu_env members in
  let redefs = Check_redef.run ~scope members in
  let syms = Check_sym.run ~scope tu_env members in
  let defs = Check_def.run ~scope tu_env members in
  let comps = Check_comp.run ~scope tu_env members in
  let topos = Check_topo.run ~scope ~unconnected ~sync_cycle tu_env members in
  redefs @ syms @ defs @ comps @ topos
