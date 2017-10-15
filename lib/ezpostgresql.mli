type connection = Postgresql.connection

val connect : conninfo:string -> unit -> connection Lwt.t

val finish : connection -> unit Lwt.t

val one : query:string -> ?params:string array -> connection -> string array Lwt.t

val all : query:string -> ?params:string array -> connection -> string array array Lwt.t

val command : query:string -> ?params:string array -> connection -> unit Lwt.t


module Pool : sig
  type t = connection Lwt_pool.t

  val create : conninfo:string -> size:int -> unit -> t

  val one : query:string -> ?params:string array -> t -> string array Lwt.t

  val all : query:string -> ?params:string array -> t -> string array array Lwt.t

  val command : query:string -> ?params:string array -> t -> unit Lwt.t
end


module Transaction : sig
  type t

  val begin_ : (t -> unit Lwt.t) -> connection -> unit Lwt.t

  val commit : t -> unit Lwt.t

  val rollback : t -> unit Lwt.t

  val one : query:string -> ?params:string array -> t -> string array Lwt.t

  val all : query:string -> ?params:string array -> t -> string array array Lwt.t

  val command : query:string -> ?params:string array -> t -> unit Lwt.t

  module Pool : sig

    val begin_ : (t -> unit Lwt.t) -> Pool.t -> unit Lwt.t

  end
end
