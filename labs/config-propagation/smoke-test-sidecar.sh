#!/usr/bin/env bash

# Performs a smoke test of Istio's configuration propagation of Sidecar objects
# from the control plane to the data plane.

set -eu
set -o pipefail

source "${BASH_SOURCE[0]%/*}"/../../lib/logging.sh
source "${BASH_SOURCE[0]%/*}"/lib/helloapp.sh
source "${BASH_SOURCE[0]%/*}"/lib/istio.sh
source "${BASH_SOURCE[0]%/*}"/lib/kubernetes.sh


# ---- Definitions: clusters ---------

cluster_primary=primary1
cluster_remote=remote1

#--------------------------------------

log::msg "Deploying hello apps inside remote cluster"
helloapp::deploy "${cluster_remote}" hello1 &
helloapp::deploy "${cluster_remote}" hello2 &
wait

log::msg "Smoke testing hello apps"
istio::namespace::create "${cluster_remote}" hello-consumer
helloapp::smoke_test "${cluster_remote}" hello-consumer hello1 &
helloapp::smoke_test "${cluster_remote}" hello-consumer hello2 &
wait
kubernetes::namespace::delete "${cluster_remote}" hello-consumer &

log::msg "Creating Sidecar with restricted egress hosts in hello2 namespace"
kubernetes::namespace::create "${cluster_primary}" hello2
istio::sidecar::create "${cluster_primary}" hello2
sleep 2

log::msg "Printing Envoy clusters for 'helloworld.hello*' in hello1 namespace"
istio::proxy::clusters "${cluster_remote}" hello1 helloworld 'helloworld.hello'
log::msg "Printing Envoy clusters for 'helloworld.hello*' in hello2 namespace"
istio::proxy::clusters "${cluster_remote}" hello2 helloworld 'helloworld.hello'

log::msg "Printing Envoy routes '80' in hello1 namespace"
istio::proxy::routes "${cluster_remote}" hello1 helloworld '80'
log::msg "Printing Envoy routes '80' in hello2 namespace"
istio::proxy::routes "${cluster_remote}" hello2 helloworld '80'

# NOTE: despite the absence of clusters and routes to 'hello*' namespaces,
# requests from the hello2 namespace will succeed.
# A glance at Envoy's access logs reveals that outbound requests are sent to
# the PassthroughCluster, which connects to the destination directly.
#
# Traffic to external services can be blocked by setting the
# outboundTrafficPolicy to REGISTRY_ONLY inside the Sidecar object.
#
# References:
#   https://istio.io/v1.15/docs/tasks/traffic-management/egress/egress-control/#envoy-passthrough-to-external-services
#   https://istio.io/blog/2019/monitoring-external-service-traffic/
#   https://istio.io/v1.15/docs/reference/config/networking/sidecar/#OutboundTrafficPolicy
log::msg "Smoke testing hello apps from hello1 namespace"
helloapp::smoke_test "${cluster_remote}" hello1 hello1 &
helloapp::smoke_test "${cluster_remote}" hello1 hello2 &
wait
log::msg "Smoke testing hello apps from hello2 namespace"
helloapp::smoke_test "${cluster_remote}" hello2 hello1 &
helloapp::smoke_test "${cluster_remote}" hello2 hello2 &
wait

log::msg "Deleting Sidecar with restricted egress hosts from hello2 namespace"
istio::sidecar::delete "${cluster_primary}" hello2
kubernetes::namespace::delete "${cluster_primary}" hello2 &

log::msg "Terminating hello app inside remote clusters"
helloapp::terminate "${cluster_remote}" hello1 &
helloapp::terminate "${cluster_remote}" hello2 &
wait
