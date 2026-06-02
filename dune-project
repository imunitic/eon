(lang dune 3.15)
(name eon)
(generate_opam_files true)

(package
 (name eon-ecs)
 (synopsis "Entity Component System core for Eon engine")
 (description "Eon ECS is a minimal, data-oriented ECS library for OCaml.")
 (depends
  ocaml
  dune
  (alcotest :with-test)
  (bechamel :with-test)
  (mtime :with-test)
  (qcheck :with-test)
  (qcheck-alcotest :with-test)
  (bisect_ppx :with-test)))

 (package
  (name eon-engine)
  (synopsis "Game engine layer built on top of Eon ECS")
  (description "Eon Engine provides prefab loading, pipelines, systems, assets, and backends.")
  (depends ocaml dune eon-ecs))
