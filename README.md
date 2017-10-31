# Ezpostgresql [![Build Status](https://travis-ci.org/bobbypriambodo/ezpostgresql.svg?branch=master)](https://travis-ci.org/bobbypriambodo/ezpostgresql)

[Lwt](https://github.com/ocsigen/lwt)-friendly wrapper for postgresql-ocaml which supports connection pooling.

## Motivation

### Problem

Using databases (in particular, postgresql) in OCaml is not straightforward.

Some libraries, such as the popular [PG'OCaml](https://github.com/darioteixeira/pgocaml), implements sophisticated compile-time type-safety while hiding the cruft in a now-deprecated camlp4 syntax extension. Others, such as [postgresql-ocaml](https://github.com/mmottl/postgresql-ocaml) goes even lower as a wrapper for libpq, the C client lib for postgres. To use it, one must be familiar with how libpq works, which means reading the docs with examples written in C.

Another problem that usually comes when building apps that comunicates with databases is to have a pooled DB connections. Most libraries don't give this support out of the box, and there doesn't seem to be any generic resource pool library for OCaml that I'm aware of except for Lwt_pool from Lwt, and the example of its usage is less documented.

### Solution

This library is a wrapper to the low-level postgresql-ocaml lib that aims to give users a friendlier interface in using postgres database by making them non-blocking (via Lwt). By friendlier, it means that we give up many points of type safety that other libs provide and stick with writing SQL query strings with params and returning string arrays, in plain OCaml (without any syntax extension). This enables a consistent and easy-to-grasp API.

This lib also provides an easy way of using pools of postgres connections powered by `Lwt_pool`. The API of using pooled connection is analogous to the one for single connection.

If you want more type safety, then this lib is most likely not for you.

The name was inspired by the awesome [Ezjsonm](https://github.com/mirage/ezjsonm) library.

## Features

* Non-blocking, lwt-friendly interface
* Transactions
* Pooled connections

## Usage

_This library is still a work in progress! Consider yourself warned for breaking changes._

To use this library, install via opam:

```
opam pin add ezpostgresql git+https://github.com/bobbypriambodo/ezpostgresql.git
```

## Examples

### Single connection

```ocaml
let () =
  let open Ezpostgresql in
  Lwt_main.run (
    (* Connect to a database. `conninfo` is the usual postgres conninfo string. *)
    let%lwt conn = connect ~conninfo:"host=localhost" () in

    (* Run a command. The passed ~params is guaranteed to be escaped. *)
    let%lwt () =
      command
        ~query:"INSERT INTO person (name, age) VALUES ($1, $2)"
        ~params:[| "Bobby"; (string_of_int 19) |]
        conn in

    (* Run a query returning one result. *)
    let%lwt res =
      one
        ~query:"SELECT name, age FROM person WHERE name = $1"
        ~params:[| "Bobby" |]
        conn in

    (* `res` will be a `string array` containing the values in order of select. *)
    print_endline res.(0); (* outputs Bobby *)
    print_endline res.(1); (* outputs 19 *)

    (* Run a query returning multiple result. ~params is optional. *)
    let%lwt res =
      all
        ~query:"SELECT name, age FROM person"
        conn in

    (* `res` will be a `string array array` (array of entries). *)
    print_endline (string_of_int @@ Array.length res); (* outputs 1 *)

    (* Close the connection. *)
    finish conn
  )
```

### Pooled connections

```ocaml
let () =
  let open Ezpostgresql.Pool in
  Lwt_main.run (
    (* Create a pool of DB connections with size 10. *)
    let pool = create ~conninfo:"host=localhost" ~size:10 () in

    (* Run a command using pool. *)
    let%lwt () =
      command
        ~query:"INSERT INTO person (name, age) VALUES ($1, $2)"
        ~params:[| "Bobby"; (string_of_int 19) |]
        pool in

    (* Run a query returning one result using pool. *)
    let%lwt res =
      one
        ~query:"SELECT name, age FROM person WHERE name = $1"
        ~params:[| "Bobby" |]
        pool in

    (* `res` will be a `string array` containing the values in order of select. *)
    print_endline res.(0); (* outputs Bobby *)
    print_endline res.(1); (* outputs 19 *)

    (* Run a query returning multiple result. ~params is optional. *)
    let%lwt res =
      all
        ~query:"SELECT name, age FROM person"
        pool in

    (* `res` will be a `string array array` (array of entries). *)
    print_endline (string_of_int @@ Array.length res); (* outputs 1 *)

    Lwt.return ()
  )
```

### Transactions

```ocaml
let () =
  Lwt_main.run (
    (* Given that we have a connection... *)
    let%lwt conn = Ezpostgresql.connect ~conninfo () in

    let open Ezpostgresql.Transaction in

    (* Begin the transaction block. *)
    conn |> begin_ (fun trx ->
        (* Issue multiple commands. You can also use `one` or `all`. *)
        let%lwt () =
          command
            ~query:"INSERT INTO person VALUES ($1, $2)"
            ~params:[| "Bobby"; (string_of_int 19) |]
            trx in
        let%lwt () =
          command
            ~query:"INSERT INTO person VALUES ($1, $2)"
            ~params:[| "Bobby"; (string_of_int 19) |]
            trx in

        (* Commit the transaction. *)
        commit trx

       (* You can also rollback using
            rollback trx
          and all commands issued with trx will be canceled. *)

       (* If you want to use pool, rather than `begin_` you may use
            pool |> Pool.begin_
          the rest of the commands are the same. *)
      )
  )
```
