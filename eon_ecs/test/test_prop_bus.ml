module Double_bus = Eon_ecs__Double_bus

type op =
  | Emit of int
  | Collect
  | Drain

type model = {
  current : int list;
  next : int list;
  delivered : int list;
}

let pp_op = function
  | Emit v -> Printf.sprintf "emit(%d)" v
  | Collect -> "collect"
  | Drain -> "drain"

let gen_op =
  let open QCheck.Gen in
  frequency
    [
      (6, map (fun v -> Emit v) int);
      (2, pure Collect);
      (2, pure Drain);
    ]

let arb_ops =
  QCheck.make
    ~print:(QCheck.Print.list pp_op)
    (QCheck.Gen.list_size (QCheck.Gen.int_bound 300) gen_op)

let model_init = { current = []; next = []; delivered = [] }

let model_collect model =
  { model with current = []; delivered = model.delivered @ model.current }

let model_drain model =
  let after_collect = model_collect model in
  { current = after_collect.next; next = []; delivered = after_collect.delivered }

let model_step model = function
  | Emit v -> { model with next = model.next @ [ v ] }
  | Collect -> model_collect model
  | Drain -> model_drain model

let prop_double_bus_collect_drain_guarantees =
  let test_fn ops =
    let bus = Double_bus.create () in
    let delivered = ref [] in
    Double_bus.on bus (fun msg -> delivered := !delivered @ [ msg ]);
    let rec loop model = function
      | [] ->
          !delivered = model.delivered
      | op :: tl ->
          begin
            match op with
            | Emit v -> Double_bus.emit bus v
            | Collect -> Double_bus.collect bus
            | Drain -> Double_bus.drain bus
          end;
          let model' = model_step model op in
          if !delivered = model'.delivered then loop model' tl else false
    in
    loop model_init ops
  in
  QCheck.Test.make
    ~name:"Double_bus collect/drain delivery guarantees"
    ~count:1_000
    arb_ops
    test_fn

let tests =
  [ QCheck_alcotest.to_alcotest prop_double_bus_collect_drain_guarantees ]
