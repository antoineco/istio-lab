#!/usr/bin/env bash

# Create a Kubernetes namespace.
function kubernetes::namespace::create {
	local cluster_name=$1
	local namespace=$2

	kubectl apply \
		--context="kind-${cluster_name}" \
		-f - <<-EOM >/dev/null
			apiVersion: v1
			kind: Namespace
			metadata:
			  name: ${namespace}
		EOM
}

# Delete a Kubernetes namespace.
function kubernetes::namespace::delete {
	local cluster_name=$1
	local namespace=$2

	kubectl delete "ns/${namespace}" \
		--context="kind-${cluster_name}" \
		>/dev/null
}
