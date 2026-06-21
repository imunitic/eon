(** Generic directed acyclic graph with topological sort.

    Nodes are compared with structural equality [(=)].
    Edges declare ordering constraints; [topo_sort] linearises the graph
    respecting those constraints.

    The result of [topo_sort] is cached internally and reused on subsequent
    calls until [add_node] or [before] introduces a structural change. *)

type 'node t

val create   : unit -> 'node t

(** [add_node n g] adds [n] to [g]. No-op if [n] is already present. *)
val add_node : 'node -> 'node t -> 'node t

(** [before ~earlier ~later g] records that [earlier] must precede [later].
    No-op if the edge already exists. *)
val before   : earlier:'node -> later:'node -> 'node t -> 'node t

(** [after ~later ~earlier g] is [before ~earlier ~later g]. *)
val after    : later:'node -> earlier:'node -> 'node t -> 'node t

(** Return all nodes in topological order.
    Raises [Invalid_argument] if a cycle is detected.
    The result is cached; repeated calls with no structural change return
    the cached list without recomputation. *)
val topo_sort : 'node t -> 'node list

(** [true] if [topo_sort] has been called and no structural change has
    occurred since (i.e. the cache is valid). *)
val is_clean  : 'node t -> bool
