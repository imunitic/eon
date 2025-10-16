include (struct
type 'msg t = {
  mutable current : 'msg Queue.t;
  mutable next : 'msg Queue.t;
  subscribers : ('msg -> unit) list ref;
}

let create () : 'msg t =
  { current = Queue.create (); next = Queue.create (); subscribers = ref [] }

let on (bus : 'msg t) (cb : 'msg -> unit) : unit =
  bus.subscribers := cb :: !(bus.subscribers)

let emit (bus : 'msg t) (msg : 'msg) : unit =
  Queue.add msg bus.next

let collect (bus : 'msg t) : unit =
  while not (Queue.is_empty bus.current) do
    let msg = Queue.take bus.current in
    List.iter (fun cb -> cb msg) !(bus.subscribers)
  done

let drain (bus : 'msg t) : unit =
  collect bus;
  let tmp = bus.current in
  bus.current <- bus.next;
  bus.next <- tmp;
  Queue.clear bus.next
end : Bus.BUS)
