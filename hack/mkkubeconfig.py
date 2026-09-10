#!/usr/bin/env python3
"""Write a kubeconfig that authenticates to the cluster through pocket-id.

For someone who has just been added to a `k8s-*` group. See
docs/how-to/log-in-with-kubectl.md.

Everything except the CA comes out of metal/group_vars/k3s.yml -- issuer,
client ID and the kube-vip address -- so this cannot disagree with what the API
server is actually configured to accept, and no copy of those values has to be
maintained in the documentation.

The CA is fetched at run time rather than published, because it is a trust
anchor: keeping it secret is pointless (the API server hands it to every
unauthenticated TLS client) but keeping it *correct* is what stops kubectl
trusting an impostor and handing over a bearer token. Two ways to get it:

  - default: from the TLS handshake, trust-on-first-use. Fine on the house
    network, and the SHA-256 fingerprint is printed so it can be confirmed out
    of band with someone who already has access.
  - `-n <node>`: over SSH from a control-plane node, which is authoritative and
    needs no such confirmation. Requires node access, so this is the admin path.
"""

import argparse
import base64
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
VARS = ROOT / "metal" / "group_vars" / "k3s.yml"
DEFAULT_OUT = pathlib.Path.home() / ".kube" / "clusters" / "ankhmorpork-oidc"

CERT = re.compile(
    r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\n", re.S
)


def die(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def run(*cmd, stdin=""):
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True)


def read_oidc_settings():
    """issuer, client ID and VIP from the Ansible group_vars.

    Read with yq rather than a YAML library: nothing else under hack/ needs a
    non-stdlib import, and keeping it that way is what lets any python3 run
    these scripts.
    """
    if not os.access(VARS, os.R_OK):
        die(f"cannot read {VARS} -- run this from a checkout of the repository")
    out = run("yq", "-o=json", "-I0",
              '{"issuer": .k3s_oidc_issuer_url, '
              '"client_id": .k3s_oidc_client_id, '
              '"vip": .kube_vip_ip}', str(VARS))
    if out.returncode != 0:
        die(f"could not read the OIDC settings from {VARS}")
    settings = json.loads(out.stdout)
    missing = [k for k, v in settings.items() if not v]
    if missing:
        die(f"{VARS} is missing or has empty: {', '.join(sorted(missing))}")
    return settings


def ca_from_node(node):
    print(f"Reading the CA from {node} (authoritative)...")
    out = run("ssh", "-o", "ConnectTimeout=10", node,
              "sudo cat /var/lib/rancher/k3s/server/tls/server-ca.crt")
    if out.returncode != 0 or not out.stdout.strip():
        die(f"could not read the CA from {node}")
    return out.stdout


def ca_from_tls(server, workdir):
    hostport = server.removeprefix("https://")
    print(f"Fetching the CA from {hostport} over TLS (trust-on-first-use)...")
    out = run("openssl", "s_client", "-showcerts", "-connect", hostport)
    certs = CERT.findall(out.stdout)
    if not certs:
        die(f"no certificates offered by {hostport} -- wrong address, "
            "or not reachable from here")

    # The API server sends leaf then CA. Split them so the chain can be checked
    # rather than assumed: a single-cert chain means the CA was not offered, and
    # guessing would hand back the leaf as a trust anchor.
    if len(certs) < 2:
        die(f"the API server offered {len(certs)} certificate(s); the CA was "
            "not among them -- use -n <node>")

    leaf, ca = workdir / "leaf.pem", workdir / "ca.pem"
    leaf.write_text(certs[0])
    ca.write_text(certs[-1])
    if run("openssl", "verify", "-CAfile", str(ca), str(leaf)).returncode != 0:
        die("the API server's certificate does not verify against the CA it "
            "offered -- do not trust this connection")
    return certs[-1]


def kubeconfig(server, issuer, client_id, ca_pem):
    ca = base64.b64encode(ca_pem.encode()).decode()
    return {
        "apiVersion": "v1",
        "kind": "Config",
        "current-context": "ankhmorpork",
        "clusters": [{"name": "ankhmorpork",
                      "cluster": {"server": server,
                                  "certificate-authority-data": ca}}],
        "users": [{"name": "pocket-id", "user": {"exec": {
            "apiVersion": "client.authentication.k8s.io/v1",
            "command": "kubectl",
            "args": ["oidc-login", "get-token",
                     f"--oidc-issuer-url={issuer}",
                     f"--oidc-client-id={client_id}",
                     "--oidc-extra-scope=email",
                     "--oidc-extra-scope=groups",
                     "--oidc-extra-scope=offline_access",
                     "--oidc-pkce-method=S256"],
            "interactiveMode": "IfAvailable",
            "provideClusterInfo": False,
        }}}],
        "contexts": [{"name": "ankhmorpork",
                      "context": {"cluster": "ankhmorpork",
                                  "user": "pocket-id"}}],
        "preferences": {},
    }


def write_kubeconfig(config, out):
    """Serialise through yq, but open the file here, so the mode is set before
    anything is written to it rather than after."""
    yaml = run("yq", "-P", ".", stdin=json.dumps(config))
    if yaml.returncode != 0 or not yaml.stdout.strip():
        die(f"failed to render {out}")
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
                     stat.S_IRUSR | stat.S_IWUSR)
        with os.fdopen(fd, "w") as f:
            f.write(yaml.stdout)
    except OSError as err:
        die(f"failed to write {out}: {err}")


def verify(out):
    if shutil.which("kubectl") is None:
        print("\nkubectl not found; skipping verification.")
        return 0
    if run("kubectl", "oidc-login", "--help").returncode != 0:
        print("\nThe oidc-login plugin is missing: kubectl krew install oidc-login")
        return 1
    print("\nVerifying (a browser will open for the passkey)...")
    return subprocess.run(["kubectl", "auth", "whoami"],
                          env={**os.environ, "KUBECONFIG": str(out)}).returncode


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("-o", dest="out", type=pathlib.Path, default=DEFAULT_OUT,
                        help=f"where to write it (default: {DEFAULT_OUT})")
    parser.add_argument("-s", dest="server",
                        help="API server URL (default: the kube-vip address)")
    parser.add_argument("-n", dest="node",
                        help="read the CA over SSH from this control-plane node")
    parser.add_argument("-f", dest="force", action="store_true",
                        help="overwrite an existing file")
    parser.add_argument("--no-verify", dest="verify", action="store_false",
                        help="skip the kubectl auth whoami check at the end")
    args = parser.parse_args()

    if shutil.which("openssl") is None:
        die("openssl is required")

    settings = read_oidc_settings()
    server = args.server or f"https://{settings['vip']}:6443"

    if args.out.exists() and not args.force:
        die(f"{args.out} exists; pass -f to overwrite")

    with tempfile.TemporaryDirectory() as tmp:
        workdir = pathlib.Path(tmp)
        if args.node:
            ca_pem = ca_from_node(args.node)
        else:
            ca_pem = ca_from_tls(server, workdir)

        ca_file = workdir / "ca.pem"
        ca_file.write_text(ca_pem)

        text = run("openssl", "x509", "-in", str(ca_file), "-noout", "-text")
        if "CA:TRUE" not in text.stdout:
            die("the certificate obtained is not a CA")

        printed = run("openssl", "x509", "-in", str(ca_file), "-noout",
                      "-fingerprint", "-sha256")
        fingerprint = printed.stdout.strip().partition("=")[2]

    write_kubeconfig(
        kubeconfig(server, settings["issuer"], settings["client_id"], ca_pem),
        args.out,
    )

    print()
    print(f"Wrote {args.out}")
    print(f"  server      {server}")
    print(f"  issuer      {settings['issuer']}")
    print(f"  CA SHA-256  {fingerprint}")
    if not args.node:
        print()
        print("Confirm that fingerprint with someone who already has cluster access")
        print("before using this on a network you do not control.")

    if args.verify:
        sys.exit(verify(args.out))


if __name__ == "__main__":
    main()
