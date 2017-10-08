let connect ~conninfo =
  Lwt_preemptive.detach (fun () ->
      new Postgresql.connection ~conninfo ()
    )

let create_pool ~conninfo ~size () =
  Lwt_pool.create size (connect ~conninfo)
