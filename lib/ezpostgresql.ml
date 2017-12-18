open Lwt.Infix



module type QUERYABLE = sig
  type t
  val one : query:string -> ?params:string array -> t -> string array Lwt.t
  val all : query:string -> ?params:string array -> t -> string array array Lwt.t
  val command : query:string -> ?params:string array -> t -> unit Lwt.t
  val command_returning : query:string -> ?params:string array -> t -> string array array Lwt.t
end

type connection = Postgresql.connection



type t = connection

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
      c#exec ~expect:[Postgresql.Command_ok] ~params query |> ignore
    ) conn

(* command_returning has the same semantic as all.
   We're keeping them separate for clarity. *)
let command_returning = all

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

  let command_returning = all

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
  let command_returning = all



  module Pool = struct

    let begin_ (f : t -> unit Lwt.t) pool =
      Lwt_pool.use pool (begin_ f)

  end

end
