module type S = sig
  val run_all : (unit -> unit) list -> unit
end

module Sequential = struct
  let run_all jobs = List.iter (fun f -> f ()) jobs
end

module Domain_pool = struct
  let recommended_size () =
    max 1 (Domain.recommended_domain_count () - 1)

  type pool = {
    mutex     : Mutex.t;
    not_empty : Condition.t;
    all_done  : Condition.t;
    queue     : (unit -> unit) Queue.t;
    pending   : int ref;
    exns      : exn list ref;
    shutdown  : bool ref;
  }

  let make_pool () = {
    mutex     = Mutex.create ();
    not_empty = Condition.create ();
    all_done  = Condition.create ();
    queue     = Queue.create ();
    pending   = ref 0;
    exns      = ref [];
    shutdown  = ref false;
  }

  let worker_loop pool =
    let rec loop () =
      let job =
        Mutex.protect pool.mutex (fun () ->
          while Queue.is_empty pool.queue && not !(pool.shutdown) do
            Condition.wait pool.not_empty pool.mutex
          done;
          if !(pool.shutdown) && Queue.is_empty pool.queue then None
          else Some (Queue.pop pool.queue))
      in
      match job with
      | None -> ()
      | Some f ->
        (try f ()
         with e ->
           Mutex.protect pool.mutex (fun () ->
             pool.exns := e :: !(pool.exns)));
        Mutex.protect pool.mutex (fun () ->
          decr pool.pending;
          if !(pool.pending) = 0 then Condition.signal pool.all_done);
        loop ()
    in
    loop ()

  let run_pool pool jobs =
    match jobs with
    | [] -> ()
    | _ ->
      Mutex.protect pool.mutex (fun () ->
        pool.pending := List.length jobs;
        List.iter (fun f -> Queue.push f pool.queue) jobs;
        List.iter (fun _ -> Condition.signal pool.not_empty) jobs);
      Mutex.protect pool.mutex (fun () ->
        while !(pool.pending) > 0 do
          Condition.wait pool.all_done pool.mutex
        done;
        match !(pool.exns) with
        | []     -> ()
        | e :: _ -> pool.exns := []; raise e)

  module Make (Config : sig val size : int end) : S = struct
    let pool = make_pool ()
    let () =
      for _ = 1 to Config.size do
        ignore (Domain.spawn (fun () -> worker_loop pool))
      done
    let run_all jobs = run_pool pool jobs
  end
end
