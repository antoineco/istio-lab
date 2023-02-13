# Istio Lab

My personal lab to experiment with multi-cluster Istio installations (primary-remote).

## Requirements

- Linux OS(\*)
- [Docker](https://docs.docker.com/)
- [KinD](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/)
- [istioctl](https://istio.io/latest/docs/setup/install/istioctl/)

(\*) On macOS, spin up a [Lima](https://lima-vm.io/) VM using the provided `lima-istio-dev.yaml` template:

```console
$ limactl start --name=default ./lima-istio-dev.yaml
INFO[0001] SSH Local Port: 60022
...
INFO[0173] READY. Run `lima` to open the shell.
INFO[0173] Message from the instance "default":         
To run `docker` on the host, run the following commands:
------
docker context create lima-default --docker "host=unix:///Users/myuser/.lima/default/sock/docker.sock"
docker context use lima-default
------
```

## Set Up

Run the `setup-clusters.sh` script. It creates three KinD clusters:

- One Istio primary (`primary1`)
- Two Istio remotes (`remote1`, `remote2`)

`kubectl` contexts are named respectively:

- `kind-primary1`
- `kind-remote1`
- `kind-remote2`

All three clusters are in a single Istio network `network1`.

The control plane manages the mesh ID `mesh1`.

Istiod (pilot), in the primary cluster, is exposed to remote clusters over an Istio east-west gateway backed by a
Kubernetes Service of type LoadBalancer.
The IP address of this Service is assigned and advertised by [MetalLB](https://metallb.universe.tf/) (L2 mode).
