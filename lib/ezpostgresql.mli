(** Lwt-friendly wrapper for postgresql-ocaml which supports connection pooling. *)

(** Interface for queryable entities, for example a connection, a pool, or a transaction. *)
module type QUERYABLE = sig

  (** The queryable entity. *)
  type t

  (** Run a query that expects a single row result. *)
  val one : query:string -> ?params:string array -> t -> string array Lwt.t

  (** Run a query that expects multiple row result. *)
  val all : query:string -> ?params:string array -> t -> string array array Lwt.t

  (** Run a command (e.g. insert, update, delete) that expects no result. *)
  val command : query:string -> ?params:string array -> t -> unit Lwt.t

  (** Run a command (e.g. insert, update, delete) that uses RETURNING clause. *)
  val command_returning : query:string -> ?params:string array -> t -> string array array Lwt.t

end



(** The database connection. This is just an alias to [Postgresql.connection]. *)
type connection = Postgresql.connection



(** A connection is queryable. *)
include QUERYABLE with type t = connection

(** Connect to a database. [conninfo] is the usual Postgresql conninfo. *)
val connect : conninfo:string -> unit -> connection Lwt.t

(** Close a connection (must be called after [connect]). *)
val finish : connection -> unit Lwt.t



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
  val begin_ : (t -> unit Lwt.t) -> connection -> unit Lwt.t

  (** Commit an ongoing transaction (must be called after [begin_]). *)
  val commit : t -> unit Lwt.t

  (** Rollback an ongoing transaction (must be called after [begin_]). *)
  val rollback : t -> unit Lwt.t

  (** Module to work with transactions using connection pools. For queries and commands, we can reuse
      the functions on [Transaction] module. *)
  module Pool : sig

    (** Begin the transaction on a pool. *)
    val begin_ : (t -> unit Lwt.t) -> Pool.t -> unit Lwt.t

  end

end
