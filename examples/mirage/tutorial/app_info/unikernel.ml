let start () =
  let libs = Build_info.V1.Statically_linked_libraries.to_list () in
  Logs.info (fun f ->
      f "Static libraries:@ %a"
        Fmt.(
          list ~sep:sp (fun ppf lib ->
              let name = Build_info.V1.Statically_linked_library.name lib in
              let version =
                Option.map Build_info.V1.Version.to_string
                  (Build_info.V1.Statically_linked_library.version lib)
              in
              match version with
              | None -> pf ppf "%s" name
              | Some v -> pf ppf "%s.%s" name v))
        libs);
  Lwt.return_unit
