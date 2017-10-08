let conninfo = "host=localhost"

let tests = [

  "connect", [
    Alcotest_lwt.test_case "could connect" `Quick (fun _ _ ->
        let%lwt c = Ezpostgresql.connect ~conninfo () in
        Lwt.return @@ Alcotest.(check (string)) "same string" "localhost" c#host
      )
  ];

  "create_pool", [
    Alcotest_lwt.test_case "could use connection from pool" `Quick (fun _ _ ->
        let pool = Ezpostgresql.create_pool ~conninfo ~size:10 () in
        Lwt_pool.use pool (fun c ->
            Lwt.return @@ Alcotest.(check (string)) "same string" "localhost" c#host
          )
      )
  ]

]

let _ =
  Alcotest.run "Ezpostgresql" tests
