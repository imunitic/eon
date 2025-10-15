(** Messaging — unified interface for signals, events, and commands.
    Each bus has a specific temporal semantics:
    - Signals: same-frame (Single_bus)
    - Events:  next-frame (Double_bus)
    - Commands: same-frame (Single_bus)
*)

module Signals  = Single_bus
module Events   = Double_bus
module Commands = Single_bus
