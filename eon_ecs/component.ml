type 'a component = {
  id   : int;
  name : string;
  mutable data : 'a Sparse_set.t;
}
type any_component = Component : 'a component -> any_component

let make id name =
  {id; name; data = Sparse_set.create () }

let name (Component c) = c.name
let id (Component c) = c.id
