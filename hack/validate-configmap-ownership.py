import subprocess, pathlib, json, collections, sys
paths = subprocess.run(["bash","-c",
  "git ls-files 'k8s/flux/*' 'k8s/bootstrap/*' | xargs -I{} yq -r 'select(.kind==\"Kustomization\") | .spec.path' {} 2>/dev/null | sed 's|^\\./||' | sort -u"],
  capture_output=True, text=True).stdout.split()
owner = collections.defaultdict(set)
for d in paths:
    if not pathlib.Path(d).is_dir(): continue
    out = subprocess.run(["kustomize","build",d], capture_output=True, text=True).stdout
    if not out.strip(): continue
    js = subprocess.run(["yq","ea","-o=json",'[.]',"-"], input=out, capture_output=True, text=True).stdout
    try: docs = json.loads(js)
    except Exception: continue
    for o in docs:
        if not isinstance(o, dict) or o.get("kind") != "ConfigMap": continue
        md = o.get("metadata") or {}
        owner[(md.get("namespace"), md.get("name"))].add(d)
clashes = {k: v for k, v in owner.items() if len(v) > 1}
print(f"  distinct ConfigMaps across all Kustomizations: {len(owner)}")
if clashes:
    print("  CLAIMED BY MORE THAN ONE KUSTOMIZATION:")
    for (ns, n), ds in sorted(clashes.items()):
        print(f"    {ns}/{n}")
        for d in sorted(ds): print(f"        {d}")
    sys.exit(1)
print("  no ConfigMap is produced by two Kustomizations")
