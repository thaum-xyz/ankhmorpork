rule {
  match {
    kind = "alerting"
  }
/*
  annotation "summary" {
    severity = "warning"
    required = true
  }
*/
/*
  annotation "description" {
    severity = "warning"
    required = true
  }
*/

/*
  annotation "runbook_url" {
    severity = "warning"
    required = true
  }

  annotation "dashboard_url" {
    severity = "warning"
    required = true
  }
*/

  label "severity" {
    severity = "bug"
    value    = "warning|critical|info|none"
    required = true
  }
}

checks {
  disabled = [
    "alerts/template",
    "promql/regexp"
  ]
}

ci {
  include = [ "tmp/rules/(.*)" ]
  baseBranch = "master"
}
