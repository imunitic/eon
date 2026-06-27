type 'msg t = { inner : 'msg Eon_ecs.Bus.Single.t; mutex : Mutex.t }

let create () = { inner = Eon_ecs.Bus.Single.create (); mutex = Mutex.create () }

let emit t msg = Mutex.protect t.mutex (fun () -> Eon_ecs.Bus.Single.emit t.inner msg)

let on t h     = Eon_ecs.Bus.Single.on t.inner h
let clear t    = Eon_ecs.Bus.Single.clear t.inner
let collect t  = Eon_ecs.Bus.Single.collect t.inner
let drain      = collect
