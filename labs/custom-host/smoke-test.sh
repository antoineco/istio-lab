#!/usr/bin/env bash

# Performs a smoke test of addressing a mesh endpoint with a custom host name
# declared using an Istio ServiceEntry.

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

log::msg "Deploying hello app inside remote cluster"
helloapp::deploy "${cluster_remote}" hello

log::msg "Smoke testing hello app"
istio::namespace::create "${cluster_remote}" hello-consumer
helloapp::smoke_test "${cluster_remote}" hello-consumer hello

log::msg "Creating hello app namespaces inside primary cluster"
kubernetes::namespace::create "${cluster_primary}" hello
kubernetes::namespace::create "${cluster_primary}" hello-consumer
log::msg "Creating ServiceEntry for 'helloworld.service'"
istio::serviceentry::create "${cluster_primary}" hello helloworld.service
log::msg "Creating Sidecar to enable http_proxy"
istio::sidecar::create_http_proxy "${cluster_primary}" hello-consumer hello
sleep 2

log::msg "Printing Envoy clusters for 'helloworld.service'"
istio::proxy::clusters "${cluster_remote}" hello helloworld helloworld.service
log::msg "Printing Envoy endpoints for 'helloworld.service'"
istio::proxy::endpoints "${cluster_remote}" hello helloworld 'outbound|80||helloworld.service'

log::msg "Smoke testing hello app using 'helloworld.service' host name"
helloapp::smoke_test_hostname "${cluster_remote}" hello-consumer helloworld.service

log::msg "Deleting hello app namespaces inside primary cluster"
kubernetes::namespace::delete "${cluster_primary}" hello &
kubernetes::namespace::delete "${cluster_primary}" hello-consumer &

log::msg "Terminating hello app inside remote cluster"
helloapp::terminate "${cluster_remote}" hello &
wait
