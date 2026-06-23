let collect () =
  Single_bus.collect (Buses.Default.signals ());
  Double_bus.collect (Buses.Default.events ());
  Single_bus.collect (Buses.Default.commands ())

let drain () =
  Single_bus.drain  (Buses.Default.signals ());
  Single_bus.drain  (Buses.Default.commands ());
  Double_bus.drain  (Buses.Default.events ())
