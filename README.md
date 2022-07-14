# Ankhmorpork

<!-- [![document](https://img.shields.io/website?label=document&logo=gitbook&logoColor=white&style=flat-square&url=https%3A%2F%2Fdocs.thaum.xyz)](https://docs.thaum.xyz) -->
[![license](https://img.shields.io/github/license/thaum-xyz/ankhmorpork?style=flat-square&logo=mit&logoColor=white)](https://github.com/thaum-xyz/ankhmorpork/blob/master/LICENSE)

## 📖 Overview

This is a mono repository for [@paulfantom](https://github.com/paulfantom) home infrastructure and Kubernetes cluster.
Project utilizes [Infrastructure as Code](https://en.wikipedia.org/wiki/Infrastructure_as_code) to automate provisioning, operating, and updating self-hosted services.

## ⛵ Kubernetes

### Installation

Cluster is [k3s](https://k3s.io/) provisioned on bare-metal Ubuntu 20.04 using a modified version of [Ansible](https://www.ansible.com/) role [provided by k3s project](https://github.com/k3s-io/k3s-ansible).

🔸 _[Click here](./metal/) to see my Ansible playbooks and roles._

### Components

<table>
  <tr>
    <th>Logo</th>
    <th>Name</th>
    <th>Description</th>
  </tr>
  <tr>
    <td><img width="32" src="https://jsonnet.org/img/isologo.svg"></td>
    <td><a href="https://jsonnet.org">Jsonnet</a></td>
    <td>Data templating language</td>
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
    <td><img width="32" src="https://upload.wikimedia.org/wikipedia/commons/a/ab/Logo-ubuntu_cof-orange-hex.svg"></td>
    <td><a href="https://ubuntu.com">Ubuntu</a></td>
    <td>Base OS for Kubernetes nodes</td>
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
    <td><img width="32" src="https://github.com/weaveworks/kured/raw/main/img/logo.png"></td>
    <td><a href="https://github.com/weaveworks/kured">kured</a></td>
    <td>Kubernetes Reboot Daemon</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/flux/icon/color/flux-icon-color.svg"></td>
    <td><a href="https://fluxcd.io/">Flux</a></td>
    <td>GitOps tool built to deploy applications to Kubernetes</td>
  </tr>
  <tr>
    <td></td>
    <td><a href="https://github.com/bitnami-labs/sealed-secrets">SealedSecrets</a></td>
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
    <td><img width="32" src="https://avatars.githubusercontent.com/u/314135?s=200&v=4"></td>
    <td><a href="https://www.cloudflare.com">Cloudflare</a></td>
    <td>DNS</td>
  </tr>
  <tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/1412239?s=200&v=4"></td>
    <td><a href="https://www.nginx.com">NGINX</a></td>
    <td>Kubernetes Ingress Controller</td>
  </tr>
  <tr>
    <td><img width="32" src="https://raw.githubusercontent.com/oauth2-proxy/oauth2-proxy/master/docs/static/img/logos/OAuth2_Proxy_horizontal.svg"></td>
    <td><a href="https://oauth2-proxy.github.io/oauth2-proxy/">oauth2-proxy</a></td>
    <td>Authentication proxy</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/prometheus/icon/color/prometheus-icon-color.svg"></td>
    <td><a href="https://prometheus.io">Prometheus</a></td>
    <td>Systems monitoring and alerting toolkit</td>
  </tr>
  <tr>
    <td><img width="32" src="https://grafana.com/static/img/menu/grafana2.svg"></td>
    <td><a href="https://grafana.com">Grafana</a></td>
    <td>Operational dashboards</td>
  </tr>
  <tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/86306284?s=200&v=4"></td>
    <td><a href="https://parca.dev">Parca</a></td>
    <td>Continuous profiling</td>
  </tr>
  <tr>
    <td><img width="32" src="https://github.com/grafana/loki/blob/main/docs/sources/logo.png?raw=true"></td>
    <td><a href="https://grafana.com/oss/loki">Loki</a></td>
    <td>Log aggregation system</td>
  </tr>
  <tr>
    <td><img width="32" src="https://raw.githubusercontent.com//bastienwirtz/homer/main/public/logo.png"></td>
    <td><a href="https://github.com/bastienwirtz/homer">Homer</a></td>
    <td>Portal Site</td>
  </tr>
  <tr>
    <td><img width="32" src="https://upload.wikimedia.org/wikipedia/commons/6/6e/Home_Assistant_Logo.svg"></td>
    <td><a href="https://www.home-assistant.io/">HomeAssistant</a></td>
    <td>Home Automation System</td>
  </tr>
  <tr>
    <td><img width="32" src="https://esphome.io/_images/logo.png"></td>
    <td><a href="https://esphome.io/">ESPhome</a></td>
    <td>Microcontrollers Management</td>
  </tr>
  <tr>
    <td><img width="32" src="https://cdn.statically.io/gh/KakersUK/docker-templates/master/KakersUK/images/Mealie.png"></td>
    <td><a href="https://hay-kot.github.io/mealie/">Mealie</a></td>
    <td>Cookbook</td>
  </tr>
  <tr>
    <td><img width="32" src="https://avatars.githubusercontent.com/u/32436079?s=400&v=4"></td>
    <td><a href="https://photoprism.app/">Photoprism</a></td>
    <td>Photo Management</td>
  </tr>
  <tr>
    <td><img width="32" src="https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/paperless-ngx-logo.png"></td>
    <td><a href="https://paperless-ngx.readthedocs.io/en/latest/">Paperless-ngx</a></td>
    <td>Document Management</td>
  </tr>
  <tr>
    <td>AND</td>
    <td>MANY</td>
    <td>OTHERS</td>
  </tr>
</table>

### GitOps

[Flux](https://github.com/fluxcd/flux2) watches `manifests/` subdirectories in `base` and `apps` top-level directories and makes changes based on YAML manifests. Where possible YAML manifests are generated from [jsonnet](https://jsonnet.org/) code.

## 🌐 DNS

### Ingress Controller

Over WAN, I have port forwarded ports `80` and `443` to the load balancer IP of my ingress controller that's running in my Kubernetes cluster.

### Internal DNS

[CoreDNS](https://github.com/coredns/coredns) is deployed in a cluster and provides an internal resolution of ingress addresses as well as a proxy to [NextDNS](https://nextdns.io/) used for AdBlocking.

### Dynamic DNS

My home IP can change at any given time and in order to keep my WAN IP address up to date on Cloudflare I have configured DDNS on Unifi Dream Machine Pro.

## 💽 Network Attached Storage

QNAP NAS TS-431DeU is used to manage NFS shares and backup them to B2 cloud using HBS.

## 🔧 Hardware

| Device                  | Count | RAM   | Storage                       | Connectivity       | Purpose        |
|-------------------------|-------|-------|-------------------------------|--------------------|----------------|
| Unifi Dream Machine Pro | 1     | N/A   | N/A                           | 8x GbE + 2xSFP+    | Router/NVR     |
| Unifi US-16-PoE switch  | 1     | N/A   | N/A                           | 16x GbE + 2xSFP    | Main Switch    |
| QNAP TS-431DeU          | 1     | 16GB  | 2x240NVMe RAID1 + 4x3TB RAID5 | 2x 2.5GbE LACP     | NAS            |
| Raspberry Pi 4B         | 3     | 4GB   | 64GB SSD + 32GB SD Card       | 1x GbE             | K8S Node       |
| Raspberry Pi 3B+        | 2     | 1GB   | 16GB SD Card                  | 1x GbE             | K8S Node       |
| Custom-built Server     | 1     | 64GB  | 240NVMe + 1TB SSD             | 2x GbE LACP + 1GbE | K8S Node w/GPU |

## ✨ Features

Project status: **Alpha**

- [x] Common applications: Plex, Nextcloud, HomeAssistant, Ghost...
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

## 🤝 Contributing

Any contributions you make, either big or small, are greatly appreciated.

## 🔏 Security

If you find any security issue please ping me using one of following contact mediums:
- twitter DM (@paulfantom)
- kubernetes slack (@paulfantom)
- freenode IRC (@paulfantom)
- email (paulfantom+security@gmail.com)

## 🏛️ License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for more information.
