module Make
    (Signals_transport  : Bus.S)
    (Events_transport   : Bus.S)
    (Commands_transport : Bus.S) = struct
  let _signals  = Signals_transport.create  ()
  let _events   = Events_transport.create   ()
  let _commands = Commands_transport.create ()
  let signals  () : 'a Signals_transport.t  = Obj.magic _signals
  let events   () : 'a Events_transport.t   = Obj.magic _events
  let commands () : 'a Commands_transport.t = Obj.magic _commands
  let unsubscribe_all () =
    Signals_transport.clear  _signals;
    Events_transport.clear   _events;
    Commands_transport.clear _commands
end

module Default = Make(Single_bus)(Double_bus)(Single_bus)
