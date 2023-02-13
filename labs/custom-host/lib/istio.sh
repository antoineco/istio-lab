#!/usr/bin/env bash

source "${BASH_SOURCE[0]%/*}"/../../../lib/logging.sh


# Create a Kubernetes namespace with Istio sidecar injection.
function istio::namespace::create {
	local cluster_name=$1
	local namespace=$2

	kubectl apply \
		--context="kind-${cluster_name}" \
		-f - <<-EOM >/dev/null
			apiVersion: v1
			kind: Namespace
			metadata:
			  name: ${namespace}
			  labels:
			    istio-injection: enabled
		EOM
}

# Create a mesh-internal ServiceEntry for a custom host name.
function istio::serviceentry::create {
	local cluster_name=$1
	local namespace=$2
	local hostname=$3
	local export_to="'"'*'"'"
	if (($#==4)); then
	  export_to=$4
	fi

	kubectl apply \
		--context="kind-${cluster_name}" \
		-n "${namespace}" \
		-f - <<-EOM >/dev/null
			apiVersion: networking.istio.io/v1beta1
			kind: ServiceEntry
			metadata:
			  name: internal-custom-host
			spec:
			  exportTo:
			  - ${export_to}
			  hosts:
			  - ${hostname}
			  location: MESH_INTERNAL
			  ports:
			  - name: http
			    number: 80
			    protocol: HTTP
			  resolution: STATIC
			  workloadSelector:
			    labels:
			      app: helloworld
		EOM

	log::submsg "[${cluster_name}] ServiceEntry created"
}

# Create a Sidecar with a HTTP_PROXY egress listener.
function istio::sidecar::create_http_proxy {
	local cluster_name=$1
	local namespace=$2
	local hello_namespace=$3

	# This Sidecar exists so that requests from applications to "fake" host
	# names declared via ServiceEntry objects can be routed without
	# requiring the application to resolve these host names.
	# In such setup, the application must communicate directly with the
	# proxy, either by addressing it by ip:port and setting appropriate
	# 'Host' HTTP headers, or by configuring 'http_proxy'.
	# By default, Istio doesn't configure the sidecar to bind to any
	# ip:port suitable for the purpose explained above, so we need to
	# enable such binding manually.
	kubectl apply \
		--context="kind-${cluster_name}" \
		-n "${namespace}" \
		-f - <<-EOM >/dev/null
			apiVersion: networking.istio.io/v1beta1
			kind: Sidecar
			metadata:
			  name: http-proxy
			spec:
			  egress:
			  - port:
			      name: http-proxy
			      number: 1080  # socks
			      protocol: http_proxy
			    hosts:
			    - ${hello_namespace}/*
			    captureMode: NONE
		EOM

	log::submsg "[${cluster_name}] Sidecar for http_proxy created"
}

# Print the Envoy endpoints from an Istio proxy.
function istio::proxy::endpoints {
	local cluster_name=$1
	local namespace=$2
	local app_name=$3

	local proxy_name
	proxy_name="$(istio::proxy_name ${cluster_name} ${namespace} ${app_name})"

	declare -a pc_args
	if (($#==4)); then
		local envoy_cluster=$4
		pc_args+=(
			--cluster
			"${envoy_cluster}"
		)
	fi

	while IFS= read -r line; do
		log::submsg "${line}"
	done < <(istioctl \
		--context "kind-${cluster_name}" \
		proxy-config endpoints \
		"${proxy_name}" \
		"${pc_args[@]}"
	)
}

# Print the Envoy clusters from an Istio proxy.
function istio::proxy::clusters {
	local cluster_name=$1
	local namespace=$2
	local app_name=$3

	local proxy_name
	proxy_name="$(istio::proxy_name ${cluster_name} ${namespace} ${app_name})"

	declare -a pc_args
	if (($#==4)); then
		local fqdn=$4
		pc_args+=(
			--fqdn
			"${fqdn}"
		)
	fi

	while IFS= read -r line; do
		log::submsg "${line}"
	done < <(istioctl \
		--context "kind-${cluster_name}" \
		proxy-config clusters \
		"${proxy_name}" \
		"${pc_args[@]}"
	)
}

# Return the Istio proxy name (pod.namespace) of the given app.
function istio::proxy_name {
	local cluster_name=$1
	local namespace=$2
	local app_name=$3

	local proxy_name
	proxy_name="$(kubectl get pod \
		--context="kind-${cluster_name}" \
		-n "${namespace}" \
		-l app="${app_name}" \
		-o jsonpath='{.items[].metadata.name}.{.items[].metadata.namespace}'
	)"

	echo "${proxy_name}"
}
