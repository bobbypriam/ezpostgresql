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


let rec wait_for_result (conn : connection) =
  conn#consume_input;
  if conn#is_busy then
    Lwt_unix.yield () >>= fun () -> wait_for_result conn
  else
    match conn#get_result with
    | None -> Lwt.return (Ok None)
    | Some result ->
      (* Free up the connection. *)
      assert (conn#get_result = None);
      Lwt.return (Ok (Some result))

let send_query_and_wait query params (conn : connection) =
  Lwt.catch
    (fun () ->
       conn#send_query ~params query;
       wait_for_result conn)
    (function
       | Postgresql.Error e -> Lwt.return (Error e)
       | e -> Lwt.fail e)



let one ~query ?(params=[||]) (conn : connection) =
  let open Lwt_result.Infix in
  let promise = send_query_and_wait query params conn in
  print_endline "Does not block";
  promise >|= function
  | None -> None
  | Some result ->
    try Some (result#get_tuple 0) with
    | Postgresql.Error Postgresql.Tuple_out_of_range (_, _) -> None

let all ~query ?(params=[||]) conn =
  let open Lwt_result.Infix in
  send_query_and_wait query params conn >|= function
  | None -> [||]
  | Some result -> result#get_all

let command ~query ?(params=[||]) conn =
  let open Lwt_result.Infix in
  send_query_and_wait query params conn >|= fun _ -> ()

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
        | Error _e ->
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
