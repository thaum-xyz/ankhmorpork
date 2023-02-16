{
  removeAlerts(alerts, groupName, groups): std.map(
    function(g) if g.name == groupName then
      g {
        rules: std.filter(function(rule) !std.member(alerts, rule.alert), g.rules),
      }
    else g,
    groups,
  ),
}
