type 'msg t = { inner : 'msg Eon_ecs.Signals.t; mutex : Mutex.t }

let create () = { inner = Eon_ecs.Signals.create (); mutex = Mutex.create () }

let emit t msg =
  Mutex.lock t.mutex;
  Eon_ecs.Signals.emit t.inner msg;
  Mutex.unlock t.mutex

let on t h     = Eon_ecs.Signals.on t.inner h
let collect t  = Eon_ecs.Signals.collect t.inner
let drain      = collect
