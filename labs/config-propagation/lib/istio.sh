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

# Create a ServiceEntry for example.com.
function istio::serviceentry::create {
	local cluster_name=$1
	local export_to="'"'*'"'"
	if (($#==2)); then
	  export_to=$2
	fi

	kubectl apply \
		--context="kind-${cluster_name}" \
		-n istio-system \
		-f - <<-EOM >/dev/null
			apiVersion: networking.istio.io/v1beta1
			kind: ServiceEntry
			metadata:
			  name: external-example-com
			spec:
			  exportTo:
			  - ${export_to}
			  hosts:
			  - example.com
			  location: MESH_EXTERNAL
			  ports:
			  - name: https
			    number: 443
			    protocol: TLS
			  resolution: STATIC
			  endpoints:
			  # TEST-NET-1
			  # https://datatracker.ietf.org/doc/html/rfc5737
			  - address: 192.0.2.42
		EOM

	log::submsg "[${cluster_name}] ServiceEntry created"
}

# Delete the ServiceEntry for example.com.
function istio::serviceentry::delete {
	local cluster_name=$1

	kubectl delete serviceentries.networking.istio.io/external-example-com \
		--context="kind-${cluster_name}" \
		-n istio-system \
		>/dev/null

	log::submsg "[${cluster_name}] ServiceEntry deleted"
}

# Create a Sidecar with restricted egress hosts.
function istio::sidecar::create {
	local cluster_name=$1
	local namespace=$2

	kubectl apply \
		--context="kind-${cluster_name}" \
		-n "${namespace}" \
		-f - <<-EOM >/dev/null
			apiVersion: networking.istio.io/v1beta1
			kind: Sidecar
			metadata:
			  name: system-only
			spec:
			  #outboundTrafficPolicy:
			  #  mode: REGISTRY_ONLY
			  egress:
			  - hosts:
			    - istio-system/*
		EOM

	log::submsg "[${cluster_name}] Sidecar created"
}

# Delete the Sidecar with restricted egress hosts.
function istio::sidecar::delete {
	local cluster_name=$1
	local namespace=$2

	kubectl delete sidecars.networking.istio.io/system-only \
		--context="kind-${cluster_name}" \
		-n "${namespace}" \
		>/dev/null

	log::submsg "[${cluster_name}] Sidecar deleted"
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

# Print the Envoy routes from an Istio proxy.
function istio::proxy::routes {
	local cluster_name=$1
	local namespace=$2
	local app_name=$3

	local proxy_name
	proxy_name="$(istio::proxy_name ${cluster_name} ${namespace} ${app_name})"

	declare -a pc_args
	if (($#==4)); then
		local route_name=$4
		pc_args+=(
			--name
			"${route_name}"
		)
	fi

	while IFS= read -r line; do
		log::submsg "${line}"
	done < <(istioctl \
		--context "kind-${cluster_name}" \
		proxy-config routes \
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
