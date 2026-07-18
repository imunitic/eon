type 'msg t = { inner : 'msg Eon_ecs.Bus.Double.t; mutex : Mutex.t }

let create () = { inner = Eon_ecs.Bus.Double.create (); mutex = Mutex.create () }

let emit t msg = Mutex.protect t.mutex (fun () -> Eon_ecs.Bus.Double.emit t.inner msg)

let on t h    = Eon_ecs.Bus.Double.on t.inner h
let clear t   = Eon_ecs.Bus.Double.clear t.inner
let collect t = Eon_ecs.Bus.Double.collect t.inner
let drain t   = Eon_ecs.Bus.Double.drain t.inner
