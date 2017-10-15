open Lwt.Infix

type connection = Postgresql.connection

let connect ~conninfo =
  Lwt_preemptive.detach (fun () ->
      new Postgresql.connection ~conninfo ()
    )

let one ~query ?(params=[||]) conn =
  Lwt_preemptive.detach (fun (c : connection) ->
      let result = c#exec ~expect:[Postgresql.Tuples_ok] ~params query in
      result#get_tuple 0
    ) conn

let all ~query ?(params=[||]) conn =
  Lwt_preemptive.detach (fun (c : connection) ->
      let result = c#exec ~expect:[Postgresql.Tuples_ok] ~params query in
      result#get_all
    ) conn

let command ~query ?(params=[||]) conn =
  Lwt_preemptive.detach (fun (c : connection) ->
      let _ = c#exec ~expect:[Postgresql.Command_ok] ~params query in
      ()
    ) conn

let finish conn =
  Lwt_preemptive.detach (fun (c : connection) ->
      c#finish
    ) conn

module Pool = struct

  type t = connection Lwt_pool.t

  let create ~conninfo ~size () =
    Lwt_pool.create size (connect ~conninfo)

  let one ~query ?(params=[||]) pool =
    Lwt_pool.use pool (one ~query ~params)

  let all ~query ?(params=[||]) pool =
    Lwt_pool.use pool (all ~query ~params)

  let command ~query ?(params=[||]) pool =
    Lwt_pool.use pool (command ~query ~params)

end

module Transaction = struct

  type t = connection

  let begin_ (f : t -> unit Lwt.t) (conn : connection) =
    command ~query:"BEGIN" conn >>= fun () ->
    f conn

  let commit (trx : t) =
    command ~query:"COMMIT" trx

  let rollback (trx : t) =
    command ~query:"ROLLBACK" trx

  let one = one
  let all = all
  let command = command


  module Pool = struct

    let begin_ (f : t -> unit Lwt.t) pool =
      Lwt_pool.use pool (begin_ f)

  end

end
