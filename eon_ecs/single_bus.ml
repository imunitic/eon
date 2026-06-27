include (struct
type 'msg t = {
    queue: 'msg Queue.t;
    subscribers : ('msg -> unit) list ref;
  }

let create () : 'msg t =
  { queue = Queue.create (); subscribers = ref []; }

let on (bus : 'msg t) (cb : 'msg -> unit) : unit =
  bus.subscribers := cb :: !(bus.subscribers)

let clear (bus : 'msg t) : unit =
  bus.subscribers := []

let emit (bus: 'msg t) (msg: 'msg) : unit =
  Queue.add msg bus.queue

let collect (bus: 'msg t) : unit =
  while not (Queue.is_empty bus.queue) do
    let msg = Queue.take bus.queue in
    List.iter (fun cb -> cb msg) !(bus.subscribers)
  done

let drain = collect
end : Bus.S)
