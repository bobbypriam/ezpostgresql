(** Lwt-friendly wrapper for postgresql-ocaml which supports connection pooling. *)


(** The database connection. This is just an alias to [Postgresql.connection]. *)
type connection = Postgresql.connection

(** Database related errors. This is just an alias to [Postgresql.error]. *)
type error = Postgresql.error



(** Interface for queryable entities, for example a connection, a pool, or a transaction. *)
module type QUERYABLE = sig

  (** The queryable entity. *)
  type t

  (** Run a query that expects a single row result. *)
  val one : query:string -> ?params:string array -> t -> (string array option, error) result Lwt.t

  (** Run a query that expects multiple row result. *)
  val all : query:string -> ?params:string array -> t -> (string array array, error) result Lwt.t

  (** Run a command (e.g. insert, update, delete) that expects no result. *)
  val command : query:string -> ?params:string array -> t -> (unit, error) result Lwt.t

  (** Run a command (e.g. insert, update, delete) that uses RETURNING clause. *)
  val command_returning : query:string -> ?params:string array -> t -> (string array array, error) result Lwt.t

end



(** A connection is queryable. *)
include QUERYABLE with type t = connection

(** Connect to a database. [conninfo] is the usual Postgresql conninfo. *)
val connect : conninfo:string -> unit -> (connection, error) result Lwt.t

(** Close a connection (must be called after [connect]). *)
val finish : connection -> (unit, error) result Lwt.t



(** Module to work with connection pools. *)
module Pool : sig

  (** A connection pool is queryable. *)
  include QUERYABLE with type t = connection Lwt_pool.t

  (** Create a connection pool. *)
  val create : conninfo:string -> size:int -> unit -> connection Lwt_pool.t

end



(** Module to work with database transactions. *)
module Transaction : sig

  (** A transaction is queryable with an abstract type. *)
  include QUERYABLE

  (** Begin a transaction. *)
  val begin_ : connection -> (t, error) result Lwt.t

  (** Commit an ongoing transaction (must be called after [begin_]). *)
  val commit : t -> (unit, error) result Lwt.t

  (** Rollback an ongoing transaction (must be called after [begin_]). *)
  val rollback : t -> (unit, error) result Lwt.t

  (** Module to work with transactions using connection pools. For queries and commands, we can reuse
      the functions on [Transaction] module. *)
  module Pool : sig

    (** Begin the transaction on a pool. *)
    val begin_ : Pool.t -> (t, error) result Lwt.t

  end

end
