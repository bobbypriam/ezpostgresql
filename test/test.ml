(* This brings the >>= symbols into scope. *)
open Lwt_result.Infix

let conninfo =
  try Sys.getenv "DATABASE_URL"
  with Not_found -> "postgresql://localhost:5432"

let get_fail_message (e : Postgresql.error) : string =
  match e with
  | Postgresql.Tuple_out_of_range (_, _) -> "Tuple out of range"
  | Postgresql.Field_out_of_range (_, _) -> "Field out of range"
  | Postgresql.Connection_failure s -> "Connection failure: " ^ s
  | _ -> "General failure"

let raw_execute query =
  try
    let conn = new Postgresql.connection ~conninfo () in
    let _ = conn#exec ~expect:[Postgresql.Command_ok] query in
    conn#finish
  with Postgresql.Error e -> print_endline (get_fail_message e); exit 1

let create_test_table () =
  raw_execute "
    CREATE TABLE IF NOT EXISTS person (
      name VARCHAR(100) NOT NULL,
      age INTEGER NOT NULL
    )
  "

let drop_test_table () =
  raw_execute "
    DROP TABLE IF EXISTS person
  "

let tear_down () =
  raw_execute "
    TRUNCATE TABLE person
  "

let tests = [

  "connect", [
    Alcotest_lwt.test_case "could connect" `Quick (fun _ _ ->
        let open Ezpostgresql in

        let%lwt test_result =
          connect ~conninfo () >>= fun conn ->
          finish conn in

        match test_result with
        | Ok () -> Alcotest.(check unit) "Finish successfully" () () |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );
  ];

  "one", [
    Alcotest_lwt.test_case "could run `one` query" `Quick (fun _ _ ->
        let open Ezpostgresql in

        let%lwt test_result =
          connect ~conninfo () >>= fun conn ->

          raw_execute "INSERT INTO person VALUES ('Bobby', 19), ('Anne', 18)";

          one
            ~query:"SELECT * FROM person WHERE name = $1"
            ~params:[| "Bobby" |]
            conn >>= fun row_opt ->

          finish conn >>= fun () ->

          Lwt_result.return row_opt in

        tear_down ();

        match test_result with
        | Ok (Some row) -> Alcotest.(check (string)) "have correct name" "Bobby" (row.(0)) |> Lwt.return
        | Ok None -> Alcotest.fail "Record not found" |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );

    Alcotest_lwt.test_case "returns Ok None if record not found" `Quick (fun _ _ ->
        let open Ezpostgresql in

        let%lwt test_result =
          connect ~conninfo () >>= fun conn ->

          raw_execute "INSERT INTO person VALUES ('Bobby', 19), ('Anne', 18)";

          one
            ~query:"SELECT * FROM person WHERE name = $1"
            ~params:[| "Non Existent" |]
            conn >>= fun row_opt ->

          finish conn >>= fun () ->

          Lwt_result.return row_opt in

        tear_down ();

        match test_result with
        | Ok (Some _) -> Alcotest.fail "Should not match any record" |> Lwt.return
        | Ok None -> Alcotest.(check unit) "returns Ok None" () () |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );
  ];

  "all", [
    Alcotest_lwt.test_case "could run `all` query" `Quick (fun _ _ ->
        let open Ezpostgresql in

        let%lwt test_result =
          connect ~conninfo () >>= fun conn ->

          raw_execute "INSERT INTO person VALUES ('Bobby', 19), ('Anne', 18)";

          all ~query:"SELECT * FROM person" conn >>= fun rows ->

          finish conn >>= fun () ->

          Lwt_result.return rows in

        tear_down ();

        match test_result with
        | Ok rows -> Alcotest.(check (int)) "have length 2" 2 (Array.length rows) |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );
  ];

  "command", [
    Alcotest_lwt.test_case "could run `command` query" `Quick (fun _ _ ->
        let open Ezpostgresql in

        let%lwt test_result =
          connect ~conninfo () >>= fun conn ->

          command
            ~query:"CREATE TEMP TABLE test_data (some_num INTEGER NOT NULL)"
            conn >>= fun () ->

          command
            ~query:"INSERT INTO test_data VALUES ($1)"
            ~params:[| (string_of_int 42) |]
            conn >>= fun () ->

          one ~query:"SELECT some_num FROM test_data" conn >>= fun row_opt ->

          finish conn >>= fun () ->

          Lwt_result.return row_opt in

        tear_down ();

        match test_result with
        | Ok (Some row) ->
          Alcotest.(check (int)) "have correct value" 42 (int_of_string row.(0)) |> Lwt.return
        | Ok None -> Alcotest.fail "Record not found" |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );
  ];

  "command_returning", [
    Alcotest_lwt.test_case "could run `command_returning` query" `Quick (fun _ _ ->
        let open Ezpostgresql in

        let%lwt test_result =
          connect ~conninfo () >>= fun conn ->

          command_returning
            ~query:"
              INSERT INTO person (name, age) VALUES ($1, $2), ($3, $4)
              RETURNING name
            "
            ~params:[| "Bobby"; (string_of_int 19); "Anne"; (string_of_int 17) |]
            conn >>= fun rows ->

          command_returning
            ~query:"
              UPDATE person SET age = $1 WHERE 1=1
              RETURNING age
            "
            ~params:[| (string_of_int 10) |]
            conn >>= fun rows2 ->

          finish conn >>= fun () ->

          Lwt_result.return (rows, rows2) in

        tear_down ();

        match test_result with
        | Ok (rows, rows2) -> Lwt.return @@ (
            Alcotest.(check (int)) "correct rows length" 2 (Array.length rows);
            Alcotest.(check (string)) "corect name value" "Bobby" rows.(0).(0);
            Alcotest.(check (int)) "correct rows2 length" 2 (Array.length rows2);
            Alcotest.(check (int)) "correct updated age value" 10 (int_of_string rows2.(0).(0));
            Alcotest.(check (int)) "correct updated age value" 10 (int_of_string rows2.(1).(0));
          )
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );
  ];

  "Pool.create", [
    Alcotest_lwt.test_case "could use connection from pool" `Quick (fun _ _ ->
        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in
        Lwt_pool.use pool (fun c ->
            Lwt.return @@ Alcotest.(check (bool)) "test" true (c#backend_pid > 0)
          )
      );
  ];

  "Pool.one", [
    Alcotest_lwt.test_case "could run `one` query using pool" `Quick (fun _ _ ->
        let open Ezpostgresql.Pool in

        let pool = create ~conninfo ~size:10 () in

        let%lwt test_result =
          raw_execute "INSERT INTO person VALUES ('Bobby', 19), ('Anne', 18)";

          one
            ~query:"SELECT * FROM person WHERE name = $1"
            ~params:[| "Bobby" |]
            pool in

        tear_down ();

        match test_result with
        | Ok (Some row) -> Alcotest.(check (string)) "have correct name" "Bobby" (row.(0)) |> Lwt.return
        | Ok None -> Alcotest.fail "Record not found" |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );

    Alcotest_lwt.test_case "returns Ok None if record not found" `Quick (fun _ _ ->
        let open Ezpostgresql.Pool in

        let pool = create ~conninfo ~size:10 () in

        let%lwt test_result =
          raw_execute "INSERT INTO person VALUES ('Bobby', 19), ('Anne', 18)";

          one
            ~query:"SELECT * FROM person WHERE name = $1"
            ~params:[| "Non Existent" |]
            pool in

        tear_down ();

        match test_result with
        | Ok (Some _) -> Alcotest.fail "Should not match any record" |> Lwt.return
        | Ok None -> Alcotest.(check unit) "returns Ok None" () () |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );
  ];

  "Pool.all", [
    Alcotest_lwt.test_case "could run `all` query using pool" `Quick (fun _ _ ->
        let open Ezpostgresql.Pool in

        let pool = create ~conninfo ~size:10 () in

        let%lwt test_result =
          raw_execute "INSERT INTO person VALUES ('Bobby', 19), ('Anne', 18)";

          all ~query:"SELECT * FROM person" pool in

        tear_down ();

        match test_result with
        | Ok rows -> Alcotest.(check (int)) "have length 2" 2 (Array.length rows) |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      )
  ];

  "Pool.command", [
    Alcotest_lwt.test_case "could run `command` query using pool" `Quick (fun _ _ ->
        let open Ezpostgresql.Pool in

        let pool = create ~conninfo ~size:10 () in

        let%lwt test_result =
          command
            ~query:"CREATE TEMP TABLE test_data (some_num INTEGER NOT NULL)"
            pool >>= fun () ->

          command
            ~query:"INSERT INTO test_data VALUES ($1)"
            ~params:[| (string_of_int 42) |]
            pool >>= fun () ->

          one ~query:"SELECT some_num FROM test_data" pool in

        tear_down ();

        match test_result with
        | Ok (Some row) ->
          Alcotest.(check (int)) "have correct value" 42 (int_of_string row.(0)) |> Lwt.return
        | Ok None -> Alcotest.fail "Record not found" |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );
  ];

  "Pool.command_returning", [
    Alcotest_lwt.test_case "could run `command_returning` query using pool" `Quick (fun _ _ ->
        let open Ezpostgresql.Pool in
        let pool = create ~conninfo ~size:10 () in

        let%lwt test_result =
          command_returning
            ~query:"
              INSERT INTO person (name, age) VALUES ($1, $2), ($3, $4)
              RETURNING name
            "
            ~params:[| "Bobby"; (string_of_int 19); "Anne"; (string_of_int 17) |]
            pool >>= fun rows ->

          command_returning
            ~query:"
              UPDATE person SET age = $1 WHERE 1=1
              RETURNING age
            "
            ~params:[| (string_of_int 10) |]
            pool >>= fun rows2 ->

          Lwt_result.return (rows, rows2) in

        tear_down ();

        match test_result with
        | Ok (rows, rows2) -> Lwt.return @@ (
            Alcotest.(check (int)) "correct rows length" 2 (Array.length rows);
            Alcotest.(check (string)) "corect name value" "Bobby" rows.(0).(0);
            Alcotest.(check (int)) "correct rows2 length" 2 (Array.length rows2);
            Alcotest.(check (int)) "correct updated age value" 10 (int_of_string rows2.(0).(0));
            Alcotest.(check (int)) "correct updated age value" 10 (int_of_string rows2.(1).(0));
          )
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );
  ];


  "Transaction", [
    Alcotest_lwt.test_case "could run `command` in transaction" `Quick (fun _ _ ->
        let open Ezpostgresql.Transaction in

        let%lwt test_result =
          Ezpostgresql.connect ~conninfo () >>= fun conn ->

          begin_ conn >>= fun trx ->

          command
            ~query:"INSERT INTO person VALUES ('Bobby', 19)"
            trx >>= fun () ->

          command
            ~query:"INSERT INTO person VALUES ('Anne', 18)"
            trx >>= fun () ->

          commit trx >>= fun () ->

          Ezpostgresql.all ~query:"SELECT * FROM person" conn >>= fun rows ->

          Ezpostgresql.finish conn >>= fun () ->

          Lwt_result.return rows in

        tear_down ();

        match test_result with
        | Ok rows -> Alcotest.(check (int)) "have length 2" 2 (Array.length rows) |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );

    Alcotest_lwt.test_case "rollback aborts all commands" `Quick (fun _ _ ->
        let open Ezpostgresql.Transaction in

        let%lwt test_result =
          Ezpostgresql.connect ~conninfo () >>= fun conn ->

          begin_ conn >>= fun trx ->

          command
            ~query:"INSERT INTO person VALUES ('Bobby', 19)"
            trx >>= fun () ->

          command
            ~query:"INSERT INTO person VALUES ('Anne', 18)"
            trx >>= fun () ->

          rollback trx >>= fun () ->

          Ezpostgresql.all ~query:"SELECT * FROM person" conn >>= fun rows ->

          Ezpostgresql.finish conn >>= fun () ->

          Lwt_result.return rows in

        tear_down ();

        match test_result with
        | Ok rows -> Alcotest.(check (int)) "have length 0" 0 (Array.length rows) |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      )
  ];

  "Transaction.Pool", [
    Alcotest_lwt.test_case "could run `command` in transaction" `Quick (fun _ _ ->
        let open Ezpostgresql.Transaction in

        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in

        let%lwt test_result =
          Pool.begin_ pool >>= fun trx ->

          command
            ~query:"INSERT INTO person VALUES ('Bobby', 19)"
            trx >>= fun () ->

          command
            ~query:"INSERT INTO person VALUES ('Anne', 18)"
            trx >>= fun () ->

          commit trx >>= fun () ->

          Ezpostgresql.Pool.all ~query:"SELECT * FROM person" pool in

        tear_down ();

        match test_result with
        | Ok rows -> Alcotest.(check (int)) "have length 2" 2 (Array.length rows) |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      );

    Alcotest_lwt.test_case "rollback aborts all commands" `Quick (fun _ _ ->
        let open Ezpostgresql.Transaction in

        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in

        let%lwt test_result =
          Pool.begin_ pool >>= fun trx ->

          command
            ~query:"INSERT INTO person VALUES ('Bobby', 19)"
            trx >>= fun () ->

          command
            ~query:"INSERT INTO person VALUES ('Anne', 18)"
            trx >>= fun () ->

          rollback trx >>= fun () ->

          Ezpostgresql.Pool.all ~query:"SELECT * FROM person" pool in

        tear_down ();

        match test_result with
        | Ok rows -> Alcotest.(check (int)) "have length 0" 0 (Array.length rows) |> Lwt.return
        | Error e -> Alcotest.fail (get_fail_message e) |> Lwt.return
      )
  ];

]

let _ =
  drop_test_table ();
  create_test_table ();
  Alcotest.run "Ezpostgresql" tests
