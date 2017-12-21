# Ezpostgresql [![Build Status](https://travis-ci.org/bobbypriambodo/ezpostgresql.svg?branch=master)](https://travis-ci.org/bobbypriambodo/ezpostgresql)

[Lwt](https://github.com/ocsigen/lwt)-friendly wrapper for postgresql-ocaml which supports connection pooling.

## Motivation

### Problem

Using databases (in particular, postgresql) in OCaml is not straightforward.

Some libraries, such as the popular [PG'OCaml](https://github.com/darioteixeira/pgocaml), implements sophisticated compile-time type-safety while hiding the cruft in a now-deprecated camlp4 syntax extension. Others, such as [postgresql-ocaml](https://github.com/mmottl/postgresql-ocaml) goes even lower as a wrapper for libpq, the C client lib for postgres. To use it, one must be familiar with how libpq works, which means reading the docs with examples written in C. What's more, in case of postgresql-ocaml, errors are found in the form of thrown exceptions, which is undesirable and demands users' discipline for handling it.

Another problem that usually comes when building apps that comunicates with databases is to have a pooled DB connections. Most libraries don't give this support out of the box, and there doesn't seem to be any generic resource pool library for OCaml that I'm aware of except for Lwt_pool from Lwt, and the example of its usage is less documented.

### Solution

This library is a wrapper to the low-level postgresql-ocaml lib that aims to give users a friendlier interface in using postgres database by making them non-blocking (via Lwt). By friendlier, it means that we give up many points of sophisticated type safety that other libs provide and stick with writing SQL query strings with params and returning string arrays, in plain OCaml (without any syntax extension). This enables a consistent and easy-to-grasp API.

Ezpostgresql also provides a better error handling mechanism by utilizing the `result` monad. Most of the APIs have the return type of `(t, Postgresql.error) result Lwt.t`. This way, users are "forced" to handle error cases, enforced by the compiler. The use of [`Lwt_result`](https://ocsigen.org/lwt/3.1.0/api/Lwt_result) is recommended to ease dealing with the return values as well as chaining operations (see examples below).

This lib also provides an easy way of using pools of postgres connections powered by `Lwt_pool`. The API of using pooled connection is analogous to the one for single connection.

If you want more type-safe queries, then this lib is most likely not for you.

The name was inspired by the awesome [Ezjsonm](https://github.com/mirage/ezjsonm) library.

## Features

* Non-blocking, lwt-friendly interface
* Transactions
* Pooled connections
* Error handling with Result monad
* Consistent API for single connection, connection pools, and transactions

## Usage

_This library is still in version 0.x! Consider yourself warned for breaking changes._

To use this library, install via opam:

```
opam install ezpostgresql
```

## Examples

### Single connection

```ocaml
let () =
  (* Brings >>= into scope for dealing with ('a, 'b) result Lwt.t. *)
  let open Lwt_result.Infix in

  let open Ezpostgresql in

  Lwt_main.run (

    let%lwt operation_result =

      (* Connect to a database. `conninfo` is the usual postgres conninfo string. *)
      connect ~conninfo:"host=localhost" () >>= fun conn ->

      (* Run a command. The passed ~params is guaranteed to be escaped. *)
      command
        ~query:"INSERT INTO person (name, age) VALUES ($1, $2)"
        ~params:[| "Bobby"; (string_of_int 19) |]
        conn >>= fun () ->

      (* Run a query returning one result. *)
      one
        ~query:"SELECT name, age FROM person WHERE name = $1"
        ~params:[| "Bobby" |]
        conn >>= fun row_opt ->

      (* `row_opt` will be a `string array option` containing the values in order of select.
         It will have the value of `Some row` if the record is found, `None` otherwise. *)
      let () =
        match row_opt with
        | Some row ->
          print_endline row.(0); (* outputs Bobby *)
          print_endline row.(1); (* outputs 19 *)
        | None -> failwith "Record not found!"
      in

      (* Run a query returning multiple result. You may provide optional ~params. *)
      all
        ~query:"SELECT name, age FROM person"
        conn >>= fun rows ->

      (* `rows` will be a `string array array` (array of entries). *)
      print_endline (string_of_int @@ Array.length rows); (* outputs 1 *)

      (* Close the connection. *)
      finish conn in

    (* Handling of errors. `operation_result` has the type `('a, Postgresql.error) result`. *)
    match operation_result with
    | Ok () -> print_endline "Operations were successful!" |> Lwt.return
    | Error e -> print_endline "An error occurred." |> Lwt.return
  )
```

### Pooled connections

```ocaml
let () =
  let open Lwt_result.Infix in

  let open Ezpostgresql.Pool in

  (* Create a pool of DB connections with size 10. *)
  let pool = create ~conninfo:"host=localhost" ~size:10 () in

  Lwt_main.run (
    let%lwt operation_result =

      (* Run a command. The passed ~params is guaranteed to be escaped. *)
      command
        ~query:"INSERT INTO person (name, age) VALUES ($1, $2)"
        ~params:[| "Bobby"; (string_of_int 19) |]
        pool >>= fun () ->

      (* Run a query returning one result. *)
      one
        ~query:"SELECT name, age FROM person WHERE name = $1"
        ~params:[| "Bobby" |]
        pool >>= fun row_opt ->

      (* `row_opt` will be a `string array option` containing the values in order of select.
         It will have the value of `Some row` if the record is found, `None` otherwise. *)
      let () =
        match row_opt with
        | Some row ->
          print_endline row.(0); (* outputs Bobby *)
          print_endline row.(1); (* outputs 19 *)
        | None -> failwith "Record not found!"
      in

      (* Run a query returning multiple result. You may provide optional ~params. *)
      all
        ~query:"SELECT name, age FROM person"
        pool >>= fun rows ->

      (* `rows` will be a `string array array` (array of entries). *)
      print_endline (string_of_int @@ Array.length rows); (* outputs 1 *)

      Lwt_result.return () in

    (* Handling of errors. `operation_result` has the type `('a, Postgresql.error) result`. *)
    match operation_result with
    | Ok () -> print_endline "Operations were successful!" |> Lwt.return
    | Error e -> print_endline "An error occurred." |> Lwt.return
  )
```

### Transactions

```ocaml
let () =
  let open Lwt_result.Infix in

  let open Ezpostgresql.Transaction in

  Lwt_main.run (
    let%lwt operation_result =

      (* Given that we have a connection... *)
      Ezpostgresql.connect ~conninfo:"host=localhost" () >>= fun conn ->

      (* Begin the transaction block. *)
      begin_ conn >>= fun trx ->

      (* Issue multiple commands. You can also use `one` or `all`. *)
      command
        ~query:"INSERT INTO person VALUES ($1, $2)"
        ~params:[| "Bobby"; (string_of_int 19) |]
        trx >>= fun () ->

      command
        ~query:"INSERT INTO person VALUES ($1, $2)"
        ~params:[| "Bobby"; (string_of_int 19) |]
        trx >>= fun () ->

      (* Commit the transaction. *)
      commit trx

      (* You can rollback using
          rollback trx
        and all commands issued with trx will be canceled. *)

      (* If you want to use pool, rather than `begin_` you may use
          Pool.begin_ pool
        the rest of the commands are the same. *)
    in

    (* Handling of errors. *)
    match operation_result with
    | Ok () -> print_endline "Operations were successful!" |> Lwt.return
    | Error e -> print_endline "An error occurred." |> Lwt.return
  )
```
