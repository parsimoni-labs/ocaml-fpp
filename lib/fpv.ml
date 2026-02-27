(** FPP topology to F Prime Visual JSON.

    Produces JSON files compatible with
    {{:https://github.com/fprime-community/fprime-visual}fprime-visual}. *)

module SSet = Set.Make (String)
module J = Jsont.Json

(* ── Helpers ─────────────────────────────────────────────────────── *)

let index_of x xs =
  let rec go i = function
    | [] -> 0
    | y :: _ when String.equal y x -> i
    | _ :: rest -> go (i + 1) rest
  in
  go 0 xs

let connected_instances connections =
  List.fold_left
    (fun acc (conn : Ast.connection) ->
      let src = Gen_ml.pid_inst_name conn.conn_from_port.data in
      let dst = Gen_ml.pid_inst_name conn.conn_to_port.data in
      SSet.add src (SSet.add dst acc))
    SSet.empty connections

(* ── Column layering via Kahn's algorithm ────────────────────────── *)

let compute_layers names connections =
  let seen_edge = Hashtbl.create 64 in
  let succ_of = Hashtbl.create 16 in
  let in_deg = Hashtbl.create 16 in
  List.iter
    (fun n ->
      Hashtbl.replace succ_of n [];
      Hashtbl.replace in_deg n 0)
    names;
  List.iter
    (fun (conn : Ast.connection) ->
      let src = Gen_ml.pid_inst_name conn.conn_from_port.data in
      let dst = Gen_ml.pid_inst_name conn.conn_to_port.data in
      if
        src <> dst && Hashtbl.mem in_deg src && Hashtbl.mem in_deg dst
        && not (Hashtbl.mem seen_edge (src, dst))
      then begin
        Hashtbl.replace seen_edge (src, dst) ();
        Hashtbl.replace succ_of src
          (dst :: (try Hashtbl.find succ_of src with Not_found -> []));
        Hashtbl.replace in_deg dst
          (1 + try Hashtbl.find in_deg dst with Not_found -> 0)
      end)
    connections;
  let layer = Hashtbl.create 16 in
  List.iter (fun n -> Hashtbl.replace layer n 0) names;
  let queue = Queue.create () in
  Hashtbl.iter (fun n d -> if d = 0 then Queue.push n queue) in_deg;
  while not (Queue.is_empty queue) do
    let n = Queue.pop queue in
    let l = Hashtbl.find layer n in
    List.iter
      (fun s ->
        if l + 1 > Hashtbl.find layer s then Hashtbl.replace layer s (l + 1);
        let d = Hashtbl.find in_deg s - 1 in
        Hashtbl.replace in_deg s d;
        if d = 0 then Queue.push s queue)
      (Hashtbl.find succ_of n)
  done;
  layer

(* ── JSON construction helpers ───────────────────────────────────── *)

let jname s = J.name s
let jmem k v = J.mem (jname k) v
let jobject fields = J.object' fields
let jarray items = J.list items
let jstring s = J.string s
let jint n = J.int n

(* ── Port tracking ───────────────────────────────────────────────── *)

let init_port_tables connections =
  let out_order = Hashtbl.create 16 in
  let in_order = Hashtbl.create 16 in
  let out_count = Hashtbl.create 32 in
  let in_count = Hashtbl.create 32 in
  let ensure_port order inst port_name =
    let names = try Hashtbl.find order inst with Not_found -> [] in
    if not (List.mem port_name names) then
      Hashtbl.replace order inst (names @ [ port_name ])
  in
  List.iter
    (fun (conn : Ast.connection) ->
      let src = Gen_ml.pid_inst_name conn.conn_from_port.data in
      let dst = Gen_ml.pid_inst_name conn.conn_to_port.data in
      ensure_port out_order src conn.conn_from_port.data.pid_port.data;
      ensure_port in_order dst conn.conn_to_port.data.pid_port.data)
    connections;
  (in_order, out_order, in_count, out_count)

(* ── Connection tuples ───────────────────────────────────────────── *)

let build_connection_tuples connections inst_pos in_order out_order in_count
    out_count =
  let next_num count inst port_name =
    let key = (inst, port_name) in
    let n = try Hashtbl.find count key with Not_found -> 0 in
    Hashtbl.replace count key (n + 1);
    n
  in
  List.map
    (fun (conn : Ast.connection) ->
      let src = Gen_ml.pid_inst_name conn.conn_from_port.data in
      let dst = Gen_ml.pid_inst_name conn.conn_to_port.data in
      let sp = conn.conn_from_port.data.pid_port.data in
      let dp = conn.conn_to_port.data.pid_port.data in
      let src_col, src_comp = Hashtbl.find inst_pos src in
      let dst_col, dst_comp = Hashtbl.find inst_pos dst in
      let src_pi =
        index_of sp (try Hashtbl.find out_order src with Not_found -> [])
      in
      let dst_pi =
        index_of dp (try Hashtbl.find in_order dst with Not_found -> [])
      in
      let src_num = next_num out_count src sp in
      let dst_num = next_num in_count dst dp in
      ( (src_col, src_comp, src_pi, src_num),
        (dst_col, dst_comp, dst_pi, dst_num) ))
    connections

(* ── JSON builders ───────────────────────────────────────────────── *)

let build_columns_json columns in_order out_order in_count out_count =
  let port_json count inst names =
    List.map
      (fun pn ->
        let c = try Hashtbl.find count (inst, pn) with Not_found -> 0 in
        jobject
          [
            jmem "name" (jstring pn);
            jmem "portNumbers" (jarray (List.init c (fun i -> jint i)));
          ])
      names
  in
  Array.to_list
    (Array.map
       (fun col ->
         jarray
           (List.map
              (fun (n, _, _) ->
                let out_names =
                  try Hashtbl.find out_order n with Not_found -> []
                in
                let in_names =
                  try Hashtbl.find in_order n with Not_found -> []
                in
                jobject
                  [
                    jmem "instanceName" (jstring n);
                    jmem "inputPorts" (jarray (port_json in_count n in_names));
                    jmem "outputPorts"
                      (jarray (port_json out_count n out_names));
                  ])
              col))
       columns)

let build_connections_json conn_tuples =
  List.map
    (fun ((sc, si, sp, sn), (dc, di, dp, dn)) ->
      jarray
        [
          jarray [ jint sc; jint si; jint sp; jint sn ];
          jarray [ jint dc; jint di; jint dp; jint dn ];
        ])
    conn_tuples

(* ── Topology → FPV JSON ────────────────────────────────────────── *)

let pp_topology tu ppf (topo : Ast.def_topology) =
  let flat = Gen_ml.flatten_topology tu topo in
  let instances = Gen_ml.resolve_topology_instances tu flat in
  let groups = Gen_ml.collect_direct_connections flat in
  let connections = Gen_ml.all_connections groups in
  let connected = connected_instances connections in
  let instances =
    List.filter (fun (n, _, _) -> SSet.mem n connected) instances
  in
  let names = List.map (fun (n, _, _) -> n) instances in
  (* Column assignments *)
  let layer_of = compute_layers names connections in
  let max_layer =
    List.fold_left
      (fun acc n -> max acc (try Hashtbl.find layer_of n with Not_found -> 0))
      0 names
  in
  let columns = Array.init (max_layer + 1) (fun _ -> ref []) in
  List.iter
    (fun ((n, _, _) as inst) ->
      let l = try Hashtbl.find layer_of n with Not_found -> 0 in
      columns.(l) := !(columns.(l)) @ [ inst ])
    instances;
  let columns = Array.map (fun r -> !r) columns in
  (* Instance positions *)
  let inst_pos = Hashtbl.create 16 in
  Array.iteri
    (fun ci col ->
      List.iteri (fun ii (n, _, _) -> Hashtbl.replace inst_pos n (ci, ii)) col)
    columns;
  (* Port tables and connection tuples *)
  let in_order, out_order, in_count, out_count = init_port_tables connections in
  let conn_tuples =
    build_connection_tuples connections inst_pos in_order out_order in_count
      out_count
  in
  (* Assemble JSON *)
  let column_json =
    build_columns_json columns in_order out_order in_count out_count
  in
  let conn_json = build_connections_json conn_tuples in
  let json =
    jobject
      [
        jmem "columns" (jarray column_json);
        jmem "connections" (jarray conn_json);
      ]
  in
  Jsont.pp_json ppf json;
  Fmt.pf ppf "@."
