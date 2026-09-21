# homelab-gitops

![GitHub branch status](https://img.shields.io/github/checks-status/mosher-labs/homelab-gitops/main)
![GitHub Issues](https://img.shields.io/github/issues/mosher-labs/homelab-gitops)
![GitHub last commit](https://img.shields.io/github/last-commit/mosher-labs/homelab-gitops)
![GitHub repo size](https://img.shields.io/github/repo-size/mosher-labs/homelab-gitops)
![Libraries.io dependency status for GitHub repo](https://img.shields.io/librariesio/github/mosher-labs/homelab-gitops)
![GitHub License](https://img.shields.io/github/license/mosher-labs/homelab-gitops)
![GitHub Sponsors](https://img.shields.io/github/sponsors/mosher-labs)

## Introduction

This repository contains the complete Infrastructure as Code (IaC)
for the Mosher Labs homelab Kubernetes cluster, managed via GitOps
principles using ArgoCD.

## 🏗️ Architecture

- **Cluster**: 3-node k3s cluster
- **GitOps Tool**: ArgoCD
- **Package Manager**: Helm
- **Ingress**: Cloudflare Tunnels (*.benniemosher.dev)
- **Storage**: NFS (Drobo)

## 📁 Repository Structure

```text
homelab-gitops/
├── bootstrap/          # ArgoCD installation and self-management
│   └── argocd/
├── infrastructure/     # Core cluster services
│   ├── cert-manager/
│   └── ingress-nginx/
└── apps/              # Applications
    ├── hello-world/
    ├── pihole/
    ├── homebridge/
    └── jellyfin/
```

## 🚀 Bootstrap Process

1. Install ArgoCD via Helm (one-time bootstrap)
1. Apply ArgoCD Application to manage itself from this repo
1. All subsequent changes via Git commits

## 📊 Applications

| App | Purpose | Status |
| ----- | --------- | -------- |
| ArgoCD | GitOps CD tool | ✅ Active |
| hello-world | Testing | 🚧 In Progress |
| PiHole | DNS/Ad-blocking | 📋 Planned |
| Homebridge | HomeKit automation | 📋 Planned |
| Jellyfin | Media server | 📋 Planned |

## 🔧 Local Development

```bash
# Set your kubeconfig
export KUBECONFIG=~/k3s.yaml

# Watch ArgoCD apps
k9s

# Check ArgoCD status
argocd app list
```

## 📚 References

- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Mosher Labs Helm Charts](https://github.com/Mosher-Labs/helm-charts)

## 🔰 Contributing

Upon first clone, install the pre-commit hooks.

```bash
pre-commit install
```

To run pre-commit hooks locally, without a git commit.

```bash
pre-commit run -a --all-files
```

To update pre-commit hooks, this ideally should be ran before a pull request is merged.

```bash
pre-commit autoupdate
```
