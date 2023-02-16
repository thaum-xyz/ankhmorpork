{
  addArgs(args, name, containers): std.map(
    function(c)
      if c.name == name then
        c {
          args+: args,
        }
      else c,
    containers,
  ),

  addContainerParameter(parameter, value, name, containers): std.map(
    function(c)
      if c.name == name then
        c {
          [parameter]+: value,
        }
      else c,
    containers,
  ),
}
