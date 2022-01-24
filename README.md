# Ankhmorpork

<!-- [![document](https://img.shields.io/website?label=document&logo=gitbook&logoColor=white&style=flat-square&url=https%3A%2F%2Fdocs.thaum.xyz)](https://docs.thaum.xyz) -->
[![license](https://img.shields.io/github/license/thaum-xyz/ankhmorpork?style=flat-square&logo=mit&logoColor=white)](https://github.com/thaum-xyz/ankhmorpork/blob/master/LICENSE)

This project utilizes [Infrastructure as Code](https://en.wikipedia.org/wiki/Infrastructure_as_code) to automate provisioning, operating, and updating self-hosted services in [@paulfantom](https://github.com/paulfantom) homelab.

## Overview

This section provides a high level overview of the project.
For further information, please see the [documentation](https://homelab.khuedoan.com).

### Hardware

<!-- ![Hardware](link-to-photo) -->

- 2 × Raspberry Pi 4B:
  - CPU:  `Broadcom BCM2711 64-bit 1.5GHz quad core`
  - RAM:  `4GB`
  - Disk: `50GB SSD`
- 2 x Raspberry Pi 3B+:
  - CPU:  `Broadcom BCM2837 64-bit 1.4GHz quad core`
  - RAM:  `1GB`
  - Disk: `32GB SD card`
- 1 x Custom-built Server
  - CPU: `AMD Ryzen 5 3600`
  - RAM: `64GB`
  - Disk: `120GB NVMe + 1x 500GB SSD`
  - GPU: `Palit GeForce GTX 1050Ti KalmX`
- QNAP TS-431DeU
  - Main storage: `4x HDD in RAID 5`
  - Storage cache: `2x SSD in RAID 1`
- Unifi US-16-PoE switch:
  - Ports: `16` GbE + `2` SFP
  - Speed: `1000Mbps`
- Unifi Dream Machine Pro
  - Ports: `8` GbE + `2` SFP+

### Features

Project status: **Alpha**

- [x] Common applications: Gitea, Seafile, Jellyfin, Paperless...
- [x] Automated Kubernetes installation and management
- [x] Monitoring and alerting
- [x] Modular architecture, easy to add or remove features/components
- [x] Automated certificate management
- [x] Installing and managing applications using GitOps
- [x] CI/CD platform
- [ ] Automatically update DNS records for exposed services 🚧
- [ ] Distributed storage 🚧
- [ ] Automated bare metal provisioning with PXE boot 🚧
- [ ] Support multiple environments (dev, stag, prod) 🚧
- [ ] Automated offsite backups 🚧
- [ ] Single sign-on 🚧

Screenshots of some user-facing applications are shown here, I will update them before each release.
They can't capture all of the project's features, but they are sufficient to get a concept of it.

### Tech stack

<table>
  <tr>
    <th>Logo</th>
    <th>Name</th>
    <th>Description</th>
  </tr>
  <tr>
    <td><img width="32" src="https://simpleicons.org/icons/ansible.svg"></td>
    <td><a href="https://www.ansible.com">Ansible</a></td>
    <td>Automate bare metal provisioning and configuration</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/flux/icon/color/flux-icon-color.svg"></td>
    <td><a href="https://fluxcd.io/">Flux</a></td>
    <td>GitOps tool built to deploy applications to Kubernetes</td>
  </tr>
  <tr>
    <td><img width="32" src="https://github.com/jetstack/cert-manager/raw/master/logo/logo.png"></td>
    <td><a href="https://cert-manager.io">cert-manager</a></td>
    <td>Cloud native certificate management</td>
  </tr>
  <tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/314135?s=200&v=4"></td>
    <td><a href="https://www.cloudflare.com">Cloudflare</a></td>
    <td>DNS</td>
  </tr>
  <tr>
    <td><img width="32" src="https://grafana.com/static/img/menu/grafana2.svg"></td>
    <td><a href="https://grafana.com">Grafana</a></td>
    <td>Operational dashboards</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/prometheus/icon/color/prometheus-icon-color.svg"></td>
    <td><a href="https://prometheus.io">Prometheus</a></td>
    <td>Infrastructure monitoring</td>
  </tr>
  <tr>
    <td><img width="32" src="https://www.parca.dev/img/logo.svg"></td>
    <td><a href="https://parca.dev">Parca</a></td>
    <td>Continuous profiling</td>
  </tr>
  <tr>
    <td><img width="32" src="https://jsonnet.org/img/isologo.svg"></td>
    <td><a href="https://jsonnet.org">Jsonnet</a></td>
    <td>Data templating language</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/k3s/icon/color/k3s-icon-color.svg"></td>
    <td><a href="https://k3s.io">K3s</a></td>
    <td>Lightweight distribution of Kubernetes</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/kubernetes/icon/color/kubernetes-icon-color.svg"></td>
    <td><a href="https://kubernetes.io">Kubernetes</a></td>
    <td>Container-orchestration system, the backbone of this project</td>
  </tr>
  <tr>
    <td><img width="32" src="https://github.com/grafana/loki/blob/main/docs/sources/logo.png?raw=true"></td>
    <td><a href="https://grafana.com/oss/loki">Loki</a></td>
    <td>Log aggregation system</td>
  </tr>
  <tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/60239468?s=200&v=4"></td>
    <td><a href="https://metallb.org">MetalLB</a></td>
    <td>Bare metal load-balancer for Kubernetes</td>
  </tr>
  <tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/1412239?s=200&v=4"></td>
    <td><a href="https://www.nginx.com">NGINX</a></td>
    <td>Kubernetes Ingress Controller</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/prometheus/icon/color/prometheus-icon-color.svg"></td>
    <td><a href="https://prometheus.io">Prometheus</a></td>
    <td>Systems monitoring and alerting toolkit</td>
  </tr>
  <tr>
    <td><img width="32" src="https://upload.wikimedia.org/wikipedia/commons/a/ab/Logo-ubuntu_cof-orange-hex.svg"></td>
    <td><a href="https://ubuntu.com">Ubuntu</a></td>
    <td>Base OS for Kubernetes nodes</td>
  </tr>
  <tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/44036562?s=200&v=4"></td>
    <td><a href="https://github.com/features/actions">GitHub Actions</a></td>
    <td>CI system</td>
  </tr>
  <tr>
    <td></td>
    <td><a href="https://github.com/bitnami-labs/sealed-secrets">SealedSecrets</a></td>
    <td>Secrets and encryption management system</td>
  </tr>
  <tr>
    <td><img width="32" src="https://github.com/weaveworks/kured/raw/main/img/logo.png"></td>
    <td><a href="https://github.com/weaveworks/kured">kured</a></td>
    <td>Kubernetes Reboot Daemon</td>
  </tr>
</table>

## Contributing

Any contributions you make, either big or small, are greatly appreciated.

## Security

If you find any security issue please ping me using one of following contact mediums:
- twitter DM (@paulfantom)
- kubernetes slack (@paulfantom)
- freenode IRC (@paulfantom)
- email (paulfantom+security@gmail.com)

## License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for more information.

## Acknowledgements

- [Repository structure from similar project by @kuedoan](https://github.com/khuedoan/homelab)
- [README template](https://github.com/othneildrew/Best-README-Template)
<!-- - [Run the same Cloudflare Tunnel across many `cloudflared` processes](https://developers.cloudflare.com/cloudflare-one/tutorials/many-cfd-one-tunnel)
- [MAC address environment variable in GRUB config](https://askubuntu.com/questions/1272400/how-do-i-automate-network-installation-of-many-ubuntu-18-04-systems-with-efi-and)
- [Official k3s systemd service file](https://github.com/k3s-io/k3s/blob/master/k3s.service)
- [Official Cloudflare Tunnel examples](https://github.com/cloudflare/argo-tunnel-examples)
-->