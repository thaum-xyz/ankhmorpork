# Ankhmorpork

## What is it?

This is a part of [@paulfantom](https://github.com/paulfantom) personal homelab. It is on purpose made public to be used as:
- a configuration example
- a proof that cluster configuration can live in the open and be secure

## How dos it work?

Configuration is divided into three directories and is managed in two ways - either by ansible or by flux.

#### Ansible

Ansible is used to manage services which were easier to operate out of kubernetes cluster or putting them into a cluster
would cause a circular dependency issue. Most of ansible code is related to hardening base operating system, setting up
storage and bootstraping a k3s cluster.

#### Base

Directory contains all base application of k3s cluster. Initial bootstrap should be done manually with kubectl and after
that updates are performed by flux.

Additionally it is a place where flux apps and projects are stored.

#### Apps

Every other service that is installed into a cluster goes into `apps/` directory which should be governed by flux.

## Security

If you find any security issue please ping me using one of following contact mediums:
- twitter DM (@paulfantom)
- kubernetes slack (@paulfantom)
- freenode IRC (@paulfantom)
- email (paulfantom+security@gmail.com)
