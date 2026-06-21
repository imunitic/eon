type 'msg t = { inner : 'msg Eon_ecs.Events.t; mutex : Mutex.t }

let create () = { inner = Eon_ecs.Events.create (); mutex = Mutex.create () }

let emit t msg =
  Mutex.lock t.mutex;
  Eon_ecs.Events.emit t.inner msg;
  Mutex.unlock t.mutex

let on t h    = Eon_ecs.Events.on t.inner h
let collect t = Eon_ecs.Events.collect t.inner
let drain t   = Eon_ecs.Events.drain t.inner
