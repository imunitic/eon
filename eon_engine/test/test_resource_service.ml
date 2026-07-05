open Eon_engine

(* ------------------------------------------------------------------ *)
(* Resource.S — hand-written                                           *)
(* ------------------------------------------------------------------ *)

module Int_resource = struct
  type t = int
  let key = `Test_int_resource
  let fetch world = match World.get_data world key with Some v -> v | None -> raise Not_found
  let store world v = World.set_data world key v
end

(* ------------------------------------------------------------------ *)
(* Resource.Make                                                        *)
(* ------------------------------------------------------------------ *)

module Float_resource = Resource.Make(struct
  type t = float
  let key = Resource.key `Test_float_resource
end)

let test_resource_make_store_fetch () =
  let world = World.create () in
  Float_resource.store world 3.14;
  Alcotest.(check (float 1e-9)) "Make round-trip" 3.14 (Float_resource.fetch world)

let test_resource_make_fetch_raises () =
  let world = World.create () in
  Alcotest.check_raises "Make raises Not_found" Not_found
    (fun () -> ignore (Float_resource.fetch world))

let test_resource_store_fetch_roundtrip () =
  let world = World.create () in
  Int_resource.store world 42;
  Alcotest.(check int) "round-trip" 42 (Int_resource.fetch world)

let test_resource_fetch_raises_if_absent () =
  let world = World.create () in
  Alcotest.check_raises "raises Not_found" Not_found
    (fun () -> ignore (Int_resource.fetch world))

let test_resource_store_overwrites () =
  let world = World.create () in
  Int_resource.store world 1;
  Int_resource.store world 99;
  Alcotest.(check int) "overwritten" 99 (Int_resource.fetch world)

let test_resource_ro_can_fetch () =
  let world_rw = World.create () in
  Int_resource.store world_rw 7;
  let world_ro = World.readonly world_rw in
  Alcotest.(check int) "ro fetch" 7 (Int_resource.fetch world_ro)


(* ------------------------------------------------------------------ *)
(* Service.S                                                           *)
(* ------------------------------------------------------------------ *)

module String_service = struct
  type t = string
  let key = `Test_string_service
  let fetch world = match World.get_service world key with Some v -> v | None -> raise Not_found
  let register world v = World.add_service world key v
end

(* ------------------------------------------------------------------ *)
(* Service.Make                                                         *)
(* ------------------------------------------------------------------ *)

module Bool_service = Service.Make(struct
  type t = bool
  let key = Service.key `Test_bool_service
end)

let test_service_make_register_fetch () =
  let world = World.create () in
  Bool_service.register world true;
  Alcotest.(check bool) "Make round-trip" true (Bool_service.fetch world)

let test_service_make_fetch_raises () =
  let world = World.create () in
  Alcotest.check_raises "Make raises Not_found" Not_found
    (fun () -> ignore (Bool_service.fetch world))

let test_service_register_fetch_roundtrip () =
  let world = World.create () in
  String_service.register world "hello";
  Alcotest.(check string) "round-trip" "hello" (String_service.fetch world)

let test_service_fetch_raises_if_absent () =
  let world = World.create () in
  Alcotest.check_raises "raises Not_found" Not_found
    (fun () -> ignore (String_service.fetch world))

let test_service_ro_can_fetch () =
  let world_rw = World.create () in
  String_service.register world_rw "svc";
  let world_ro = World.readonly world_rw in
  Alcotest.(check string) "ro fetch" "svc" (String_service.fetch world_ro)


(* ------------------------------------------------------------------ *)
(* Namespace                                                           *)
(* ------------------------------------------------------------------ *)

let test_namespace_attach_named_roundtrip () =
  let ns    = Namespace.create () in
  let world = World.create () in
  Namespace.attach ns "game" world;
  let w = Namespace.named "game" ns in
  Int_resource.store w 99;
  Alcotest.(check int) "cross-ns fetch" 99 (Int_resource.fetch world)

let test_namespace_named_raises_unknown () =
  let ns = Namespace.create () in
  Alcotest.check_raises "Unknown_namespace"
    (Namespace.Unknown_namespace "missing")
    (fun () -> ignore (Namespace.named "missing" ns))

let test_namespace_named_returns_rw () =
  let ns    = Namespace.create () in
  let world = World.create () in
  Namespace.attach ns "global" world;
  let w = Namespace.named "global" ns in
  Int_resource.store w 5;
  Alcotest.(check int) "rw world" 5 (Int_resource.fetch world)

let test_namespace_multiple_worlds () =
  let ns = Namespace.create () in
  let w1 = World.create () in
  let w2 = World.create () in
  Namespace.attach ns "a" w1;
  Namespace.attach ns "b" w2;
  Int_resource.store w1 1;
  Int_resource.store w2 2;
  Alcotest.(check int) "w1" 1 (Int_resource.fetch (Namespace.named "a" ns));
  Alcotest.(check int) "w2" 2 (Int_resource.fetch (Namespace.named "b" ns))

let test_namespace_compose_with_resource () =
  let ns    = Namespace.create () in
  let world = World.create () in
  Namespace.attach ns default_global_ns world;
  Int_resource.store (Namespace.named default_global_ns ns) 77;
  let v = Int_resource.fetch (Namespace.named default_global_ns ns) in
  Alcotest.(check int) "compose namespace + resource" 77 v

(* ------------------------------------------------------------------ *)
(* Suite                                                               *)
(* ------------------------------------------------------------------ *)

let tests = [
  "Resource — store/fetch round-trip",          `Quick, test_resource_store_fetch_roundtrip;
  "Resource — fetch raises if absent",           `Quick, test_resource_fetch_raises_if_absent;
  "Resource — store overwrites",                 `Quick, test_resource_store_overwrites;
  "Resource — ro world can fetch",               `Quick, test_resource_ro_can_fetch;
  "Resource.Make — store/fetch round-trip",      `Quick, test_resource_make_store_fetch;
  "Resource.Make — fetch raises if absent",      `Quick, test_resource_make_fetch_raises;
  "Service — register/fetch round-trip",         `Quick, test_service_register_fetch_roundtrip;
  "Service — fetch raises if not registered",    `Quick, test_service_fetch_raises_if_absent;
  "Service — ro world can fetch",                `Quick, test_service_ro_can_fetch;
  "Service.Make — register/fetch round-trip",    `Quick, test_service_make_register_fetch;
  "Service.Make — fetch raises if absent",       `Quick, test_service_make_fetch_raises;
  "Namespace — attach/named round-trip",         `Quick, test_namespace_attach_named_roundtrip;
  "Namespace — named raises Unknown_namespace",  `Quick, test_namespace_named_raises_unknown;
  "Namespace — named returns rw world",          `Quick, test_namespace_named_returns_rw;
  "Namespace — multiple worlds isolated",        `Quick, test_namespace_multiple_worlds;
  "Namespace — compose with Resource helpers",   `Quick, test_namespace_compose_with_resource;
]
