local homepage = (import 'apps/homepage.libsonnet');


local configYAML = (importstr '../settings.yaml');

// Join multiple configuration sources
local config = std.parseYaml(configYAML)[0] {
  configData: {
    // Reading as YAML to validate yaml syntax
    // Converting to string as content is passed to a ConfigMap
    'bookmarks.yaml': std.toString(std.parseYaml(importstr '../configs.yaml')[0]),
    'docker.yaml': std.toString(std.parseYaml(importstr '../configs.yaml')[1]),
    'kubernetes.yaml': std.toString(std.parseYaml(importstr '../configs.yaml')[2]),
    'services.yaml': std.toString(std.parseYaml(importstr '../configs.yaml')[3]),
    'settings.yaml': std.toString(std.parseYaml(importstr '../configs.yaml')[4]),
    'widgets.yaml': std.toString(std.parseYaml(importstr '../configs.yaml')[5]),
  },
};

local all = homepage(config) + {
};

{ [name + '.yaml']: std.manifestYamlDoc(all[name]) for name in std.objectFields(all) }
