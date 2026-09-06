(lang dune 3.15)
(name eon)
(generate_opam_files true)

(package
 (name eon-ecs)
 (synopsis "Entity Component System core for Eon engine")
 (description "Eon ECS is a minimal, data-oriented ECS library for OCaml.")
 (license MIT)
 (authors "Ivica Munitić <imunitic@gmail.com>")
 (maintainers "Ivica Munitić <imunitic@gmail.com>")
 (source (github imunitic/eon))
 (depends
  ocaml
  dune
  notty-community
  (alcotest :with-test)
  (bechamel :with-test)
  (mtime :with-test)
  (qcheck :with-test)
  (qcheck-alcotest :with-test)))

 (package
  (name eon-edn)
  (synopsis "Standalone EDN parser library using OCaml 5 algebraic effects")
  (description "Eon EDN is a minimal, extensible EDN reader for OCaml, built on algebraic effects. Knows nothing about eon-ecs or eon-engine.")
  (license MIT)
  (authors "Ivica Munitić <imunitic@gmail.com>")
  (maintainers "Ivica Munitić <imunitic@gmail.com>")
  (source (github imunitic/eon))
  (depends
   ocaml
   dune
   (alcotest :with-test)
   (bechamel :with-test)
   (qcheck :with-test)
   (qcheck-alcotest :with-test)))

 (package
  (name eon-engine)
  (synopsis "Game engine layer built on top of Eon ECS")
  (description "Eon Engine provides prefab loading, pipelines, systems, assets, and backends.")
  (license MIT)
  (authors "Ivica Munitić <imunitic@gmail.com>")
  (maintainers "Ivica Munitić <imunitic@gmail.com>")
  (source (github imunitic/eon))
  (depends ocaml dune eon-ecs eon-edn))
