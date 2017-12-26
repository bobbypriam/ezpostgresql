open Lwt.Infix



type connection = Postgresql.connection
type error = Postgresql.error

module type QUERYABLE = sig
  type t
  val one : query:string -> ?params:string array -> t -> (string array option, error) result Lwt.t
  val all : query:string -> ?params:string array -> t -> (string array array, error) result Lwt.t
  val command : query:string -> ?params:string array -> t -> (unit, error) result Lwt.t
  val command_returning : query:string -> ?params:string array -> t -> (string array array, error) result Lwt.t
end



type t = connection

let connect ~conninfo =
  Lwt_preemptive.detach (fun () ->
      try Ok (new Postgresql.connection ~conninfo ())
      with Postgresql.Error e -> Error e
    )

let one ~query ?(params=[||]) conn =
  Lwt_preemptive.detach (fun (c : connection) ->
      try
        let result = c#exec ~expect:[Postgresql.Tuples_ok] ~params query in
        Ok (Some (result#get_tuple 0))
      with
      | Postgresql.Error (Postgresql.Tuple_out_of_range (_, _)) -> Ok None
      | Postgresql.Error e -> Error e
    ) conn

let all ~query ?(params=[||]) conn =
  Lwt_preemptive.detach (fun (c : connection) ->
      try
        let result = c#exec ~expect:[Postgresql.Tuples_ok] ~params query in
        Ok result#get_all
      with Postgresql.Error e -> Error e
    ) conn

let command ~query ?(params=[||]) conn =
  Lwt_preemptive.detach (fun (c : connection) ->
      try
        c#exec ~expect:[Postgresql.Command_ok] ~params query |> ignore;
        Ok ()
      with Postgresql.Error e -> Error e
    ) conn

(* command_returning has the same semantic as all.
   We're keeping them separate for clarity. *)
let command_returning = all

let finish conn =
  Lwt_preemptive.detach (fun (c : connection) ->
      try Ok c#finish
      with Postgresql.Error e -> Error e
    ) conn



module Pool = struct

  type t = connection Lwt_pool.t

  let create ~conninfo ~size () =
    let open Lwt.Infix in
    Lwt_pool.create size (fun () ->
        connect ~conninfo () >>= function
        | Ok conn -> Lwt.return conn
        | Error e ->
          failwith @@ "Ezpostgresql: Failed to connect. Conninfo=" ^ conninfo
      )

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

  let begin_ (conn : connection) =
    command ~query:"BEGIN" conn >>= fun res ->
    match res with
    | Ok () -> Ok conn |> Lwt.return
    | Error e -> Error e |> Lwt.return

  let commit (trx : t) =
    command ~query:"COMMIT" trx

  let rollback (trx : t) =
    command ~query:"ROLLBACK" trx

  let one = one
  let all = all
  let command = command
  let command_returning = all



  module Pool = struct

    let begin_ pool =
      Lwt_pool.use pool begin_

  end

end
