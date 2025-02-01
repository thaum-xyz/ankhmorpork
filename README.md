# Ankhmorpork

<!-- [![document](https://img.shields.io/website?label=document&logo=gitbook&logoColor=white&url=https%3A%2F%2Fdocs.thaum.xyz)](https://docs.thaum.xyz) -->
[![license](https://img.shields.io/github/license/thaum-xyz/ankhmorpork?logo=mit&logoColor=white)](https://github.com/thaum-xyz/ankhmorpork/blob/master/LICENSE)
[![kubescape](https://github.com/thaum-xyz/ankhmorpork/actions/workflows/kubescape.yml/badge.svg)](https://github.com/thaum-xyz/ankhmorpork/actions/workflows/kubescape.yml)

## 📖 Overview

This is a mono repository for [@paulfantom](https://github.com/paulfantom) home infrastructure and Kubernetes cluster.
Project utilizes [Infrastructure as Code](https://en.wikipedia.org/wiki/Infrastructure_as_code) to automate provisioning, operating, and updating self-hosted services.

## ⛵ Kubernetes

### Installation

Cluster is [k3s](https://k3s.io/) provisioned on bare-metal hosts with latest LTS Ubuntu OS using a modified version of [Ansible](https://www.ansible.com/) role [provided by k3s project](https://github.com/k3s-io/k3s-ansible).

🔸 _[Click here](./metal/) to see Ansible playbooks and roles._

### Components

<table>
  <tr>
    <th>Logo</th>
    <th>Name</th>
    <th>Description</th>
  </tr>
  <tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/44036562?s=200&v=4"></td>
    <td><a href="https://github.com/features/actions">GitHub Actions</a></td>
    <td>CI system</td>
  </tr>
  <tr>
    <td><img width="32" src="https://simpleicons.org/icons/ansible.svg"></td>
    <td><a href="https://www.ansible.com">Ansible</a></td>
    <td>Automate bare metal provisioning and configuration</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/canonicalubuntu.svg"></td>
    <td><a href="https://ubuntu.com">Ubuntu</a></td>
    <td>Base OS for Kubernetes nodes</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/k3s.svg"></td>
    <td><a href="https://k3s.io">K3s</a></td>
    <td>Lightweight distribution of Kubernetes</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/kubernetes.svg"></td>
    <td><a href="https://kubernetes.io">Kubernetes</a></td>
    <td>Container-orchestration system, the backbone of this project</td>
  </tr>
  <tr>
    <td><img width="32" src="https://kured.dev/img/kured.png"></td>
    <td><a href="https://github.com/weaveworks/kured">kured</a></td>
    <td>Kubernetes Reboot Daemon</td>
  </tr>
  <!--<tr>
    <td><img width="32" src="https://raw.githubusercontent.com/kubernetes-sigs/descheduler/master/assets/logo/descheduler-stacked-color.png"></td>
    <td><a href="https://sigs.k8s.io/descheduler">descheduler</a></td>
    <td>Kubernetes Descheduler</td>
  </tr>-->
  <tr>
    <td><img width="32" src="https://github.com/topolvm/topolvm/raw/main/docs/img/TopoLVM_logo.svg"></td>
    <td><a href="https://github.com/topolvm/topolvm">TopoLVM</a></td>
    <td>Local storage based on LVM</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/longhorn.svg"></td>
    <td><a href="https://longhorn.io/">Longhorn</a></td>
    <td>Distributed block storage</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/minio.svg"></td>
    <td><a href="https://min.io">Minio</a></td>
    <td>S3 storage</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/flux/icon/color/flux-icon-color.svg"></td>
    <td><a href="https://fluxcd.io/">Flux</a></td>
    <td>GitOps tool built to deploy applications to Kubernetes</td>
  </tr>
  <tr>
    <td><img width="32" src="https://raw.githubusercontent.com/external-secrets/external-secrets/main/assets/eso-logo-medium.png"></td>
    <td><a href="https://external-secrets.io/">ExternalSecrets</a></td>
    <td>Secrets and encryption management system</td>
  </tr>
  <tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/60239468?s=200&v=4"></td>
    <td><a href="https://metallb.org">MetalLB</a></td>
    <td>Bare metal load-balancer for Kubernetes</td>
  </tr>
  <tr>
    <td><img width="32" src="https://github.com/jetstack/cert-manager/raw/master/logo/logo.png"></td>
    <td><a href="https://cert-manager.io">cert-manager</a></td>
    <td>Cloud native certificate management</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/cloudflare.svg"></td>
    <td><a href="https://www.cloudflare.com">Cloudflare</a></td>
    <td>DNS</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/traefik-proxy.svg"></td>
    <td><a href="https://github.com/traefik/traefik">Traefik</a></td>
    <td>Kubernetes Ingress Controller</td>
  </tr>
  <tr>
    <td><img width="32" src="https://raw.githubusercontent.com/oauth2-proxy/oauth2-proxy/master/docs/static/img/logos/OAuth2_Proxy_horizontal.svg"></td>
    <td><a href="https://oauth2-proxy.github.io/oauth2-proxy/">oauth2-proxy</a></td>
    <td>Authentication proxy</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/prometheus.svg"></td>
    <td><a href="https://prometheus.io">Prometheus</a></td>
    <td>Systems monitoring and alerting toolkit</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/thanos/icon/color/thanos-icon-color.svg"></td>
    <td><a href="https://thanos.io">Thanos</a></td>
    <td>Metrics datalake</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/grafana.svg"></td>
    <td><a href="https://grafana.com">Grafana</a></td>
    <td>Operational dashboards</td>
  </tr>
  <!--<tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/86306284?s=200&v=4"></td>
    <td><a href="https://parca.dev">Parca</a></td>
    <td>Continuous profiling</td>
  </tr>-->
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/grafanaloki.svg"></td>
    <td><a href="https://grafana.com/oss/loki">Loki</a></td>
    <td>Log aggregation system</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cloudnative-pg.io/images/hero_image.svg"></td>
    <td><a href="https://cloudnative-pg.io/">Cloudnative-pg</a></td>
    <td>Postgres Controller</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/homer.svg"></td>
    <td><a href="https://github.com/bastienwirtz/homer">Homer</a></td>
    <td>Portal Site</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/homeassistant-small.svg"></td>
    <td><a href="https://www.home-assistant.io/">HomeAssistant</a></td>
    <td>Home Automation System</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/esphome.svg"></td>
    <td><a href="https://esphome.io/">ESPhome</a></td>
    <td>Microcontrollers Management</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/mealie.svg"></td>
    <td><a href="https://tandoor.dev/">Mealie</a></td>
    <td>Cookbook</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/immich.svg"></td>
    <td><a href="https://photoprism.app/">Immich</a></td>
    <td>Photo Management</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/paperlessng.svg"></td>
    <td><a href="https://paperless-ngx.readthedocs.io/en/latest/">Paperless-ngx</a></td>
    <td>Document Management</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/changedetection.svg"></td>
    <td><a href="https://changedetection.io">Changedetection</a></td>
    <td>Monitoring website changes</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/jellyfin.svg"></td>
    <td><a href="https://jellyfin.org/">Jellyfin</a></td>
    <td>Multimedia System</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.jsdelivr.net/npm/@loganmarchione/homelab-svg-assets@latest/assets/steam.svg"></td>
    <td><a href="https://github.com/lloesche/valheim-server-docker">Game Server</a></td>
    <td>Valheim Game Server</td>
  </tr>
  <tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/122059230?s=200&v=4"></td>
    <td><a href="https://atuin.sh/">Atuin</a></td>
    <td>Shell History</td>
  </tr>
  <tr>
    <td>AND</td>
    <td>MANY</td>
    <td>OTHERS</td>
  </tr>
</table>

### GitOps

[Flux](https://github.com/fluxcd/flux2) watches `manifests/` subdirectories in `base` and `apps` top-level directories and makes changes based on YAML manifests.

## 🌐 DNS

### Internal DNS

[AdGuard Home](https://adguard.com/en/adguard-home/overview.html) is deployed out of k8s cluster and provides an internal resolution of ingress addresses as well as ad blocking.

### Dynamic DNS

My home IP can change at any given time and in order to keep my WAN IP address up to date on Cloudflare I have configured DDNS on Unifi Dream Machine Pro.

## 💽 Network Attached Storage

QNAP NAS TS-451DeU is used to manage NFS shares and backup them to B2 cloud using HBS.

## 🔧 Hardware

| Device                   | Count | RAM   | Storage                          | Connectivity       | Purpose         |
|--------------------------|-------|-------|----------------------------------|--------------------|-----------------|
| Unifi Dream Machine Pro  | 1     | N/A   | N/A                              | 8x GbE + 2xSFP+    | Router          |
| Unifi US-16-PoE switch   | 1     | N/A   | N/A                              | 16x GbE + 2xSFP    | Main Switch     |
| QNAP TS-451DeU           | 1     | 16GB  | 2x240GB NVMe RAID1 + 4x6TB RAID5 | 2x 2.5GbE LACP     | NAS             |
| Raspberry Pi             | 1     | ----- | -----                            | 1x GbE             | DNS Server      |
| HP EliteDesk G2 800 mini | 2     | 32GB  | 240GB M2 SSD + 500GB SSD         | 1x GbE             | K3S Node        |
| Lenovo X1 Laptop         | 1     | 48GB  | 480GB NVMe + 1x 480GB SSD        | 1x GbE             | K3S Node        |
| Custom-built Server      | 1     | 64GB  | 480GB NVMe + 1TB SSD             | 2x GbE LACP + 1GbE | K3S Node w/GPU  |
| Custom-built Server      | 1     | 64GB  | ???                              | 1x GbE             | K3S Node (spot) |

## ✨ Features

Project status: **Alpha**

- [x] Common applications: Plex, Nextcloud, HomeAssistant, Ghost...
- [x] Automated Kubernetes installation and management
- [x] Monitoring and alerting
- [x] Modular architecture, easy to add or remove features/components
- [x] Automated certificate management
- [x] Installing and managing applications using GitOps
- [x] CI/CD platform
- [x] Distributed storage
- [x] Automatically update DNS records for exposed services
<!--TODO
- [ ] Automated bare metal provisioning with PXE boot 🚧
- [ ] Support multiple environments (dev, stag, prod) 🚧
- [ ] Automated in-cluster offsite backups 🚧
- [ ] Single sign-on 🚧
-->

## 🤝 Contributing

Any contributions you make, either big or small, are greatly appreciated.

## 🔏 Security

If you find any security issue please ping me using email (paulfantom+security@gmail.com)

## Acknowledgements

- Icons are provided by [homelab-svg-assets](https://github.com/loganmarchione/homelab-svg-assets).

## 🏛️ License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for more information.
