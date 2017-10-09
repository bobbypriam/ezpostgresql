let conninfo = "host=localhost dbname=mydb"

let tests = [

  "connect", [
    Alcotest_lwt.test_case "could connect" `Quick (fun _ _ ->
        let%lwt conn = Ezpostgresql.connect ~conninfo () in
        Lwt.return @@ Alcotest.(check (string)) "same string" "localhost" conn#host
      )
  ];

  "one", [
    Alcotest_lwt.test_case "could run `one` query" `Quick (fun _ _ ->
        let%lwt conn = Ezpostgresql.connect ~conninfo () in
        let%lwt res =
          Ezpostgresql.one ~query:"
            SELECT * FROM person WHERE name = $1
          " ~params:[| "Bobby" |] conn in
        Lwt.return @@ Alcotest.(check (string)) "same string" "Bobby" (res.(0))
      )
  ];

  "all", [
    Alcotest_lwt.test_case "could run `all` query" `Quick (fun _ _ ->
        let%lwt conn = Ezpostgresql.connect ~conninfo () in
        let%lwt res = Ezpostgresql.all ~query:"
          SELECT * FROM person
        " conn in
        Lwt.return @@ Alcotest.(check (int)) "same string" 2 (Array.length res)
      )
  ];

  "Pool.create", [
    Alcotest_lwt.test_case "could use connection from pool" `Quick (fun _ _ ->
        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in
        Lwt_pool.use pool (fun c ->
            Lwt.return @@ Alcotest.(check (string)) "same string" "localhost" c#host
          )
      )
  ];

  "Pool.one", [
    Alcotest_lwt.test_case "could run `one` query using pool" `Quick (fun _ _ ->
        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in
        let%lwt res = Ezpostgresql.Pool.one ~query:"
          SELECT * FROM person WHERE name = $1
        " ~params:[| "Bobby" |] pool in
        Lwt.return @@ Alcotest.(check (string)) "same string" "Bobby" (res.(0))
      )
  ];

  "Pool.all", [
    Alcotest_lwt.test_case "could run `all` query using pool" `Quick (fun _ _ ->
        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in
        let%lwt res = Ezpostgresql.Pool.all ~query:"
          SELECT * FROM person
        " pool in
        Lwt.return @@ Alcotest.(check (int)) "same string" 2 (Array.length res)
      )
  ];

]

let _ =
  Alcotest.run "Ezpostgresql" tests
