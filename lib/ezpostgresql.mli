(** Lwt-friendly wrapper for postgresql-ocaml which supports connection pooling. *)

(** The database connection. This is just an alias to [Postgresql.connection]. *)
type connection = Postgresql.connection

(** Connect to a database. [conninfo] is the usual Postgresql conninfo. *)
val connect : conninfo:string -> unit -> connection Lwt.t

(** Run a query that expects a single row result. *)
val one : query:string -> ?params:string array -> connection -> string array Lwt.t

(** Run a query that expects multiple row result. *)
val all : query:string -> ?params:string array -> connection -> string array array Lwt.t

(** Run a command (e.g. insert, update, delete) that expects no result. *)
val command : query:string -> ?params:string array -> connection -> unit Lwt.t

(** Close a connection (must be called after [connect]). *)
val finish : connection -> unit Lwt.t


(** Module to work with connection pools. *)
module Pool : sig

  (** A pool of connections. *)
  type t = connection Lwt_pool.t

  (** Create a connection pool. *)
  val create : conninfo:string -> size:int -> unit -> t

  (** Run a query that expects a single row result using the pool. *)
  val one : query:string -> ?params:string array -> t -> string array Lwt.t

  (** Run a query that expects multiple row result using the pool. *)
  val all : query:string -> ?params:string array -> t -> string array array Lwt.t

  (** Run a command (e.g. insert, update, delete) that expects no result using the pool. *)
  val command : query:string -> ?params:string array -> t -> unit Lwt.t
end


(** Module to work with database transactions. *)
module Transaction : sig

  (** A database transaction. *)
  type t

  (** Begin a transaction. *)
  val begin_ : (t -> unit Lwt.t) -> connection -> unit Lwt.t

  (** Commit an ongoing transaction (must be called after [begin_]). *)
  val commit : t -> unit Lwt.t

  (** Rollback an ongoing transaction (must be called after [begin_]). *)
  val rollback : t -> unit Lwt.t

  (** Run a query that expects a single row result inside the transaction block. *)
  val one : query:string -> ?params:string array -> t -> string array Lwt.t

  (** Run a query that expects multiple row result inside the transaction block. *)
  val all : query:string -> ?params:string array -> t -> string array array Lwt.t

  (** Run a command (e.g. insert, update, delete) that expects no result inside the transaction block. *)
  val command : query:string -> ?params:string array -> t -> unit Lwt.t


  (** Module to work with transactions using connection pools. For queries and commands, we can reuse
      the functions on [Transaction] module. *)
  module Pool : sig

    (** Begin the transaction on a pool. *)
    val begin_ : (t -> unit Lwt.t) -> Pool.t -> unit Lwt.t

  end

end
