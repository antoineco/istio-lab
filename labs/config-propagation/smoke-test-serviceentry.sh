#!/usr/bin/env bash

# Performs a smoke test of Istio's configuration propagation of ServiceEntry objects
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

log::msg "Creating ServiceEntry for 'example.com' exported to hello1 only"
istio::serviceentry::create "${cluster_primary}" hello1
sleep 2

log::msg "Printing Envoy endpoints for 'example.com' in hello1 namespace"
istio::proxy::endpoints "${cluster_remote}" hello1 helloworld 'outbound|443||example.com'
log::msg "Printing Envoy endpoints for 'example.com' in hello2 namespace"
istio::proxy::endpoints "${cluster_remote}" hello2 helloworld 'outbound|443||example.com'

log::msg "Deleting ServiceEntry for 'example.com'"
istio::serviceentry::delete "${cluster_primary}"

log::msg "Terminating hello app inside remote clusters"
helloapp::terminate "${cluster_remote}" hello1 &
helloapp::terminate "${cluster_remote}" hello2 &
wait
