open Component

module Registry = struct
  type t = (string, any_component) Hashtbl.t

  let create () = Hashtbl.create 32

  let register reg  ~name ~id : 'a component =
    if Hashtbl.mem reg name then
      failwith ("Component already registered: " ^ name);
    let comp = make id name in
    Hashtbl.add reg name (Component comp);
    comp

  let find reg ~name : 'a component option =
    match Hashtbl.find_opt reg name with
    | Some (Component c) -> Some (Obj.magic c)
    | None -> None

  let iter f (reg : t) =
    Hashtbl.iter (fun _ comp -> f comp) reg

  let count reg = Hashtbl.length reg 
end

type t = Registry.t
let create = Registry.create
let register = Registry.register
let find = Registry.find
let iter = Registry.iter
let count = Registry.count
