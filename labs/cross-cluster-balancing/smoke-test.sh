#!/usr/bin/env bash

# Performs a smoke test of Istio's cross-cluster load-balancing capabilities.

set -eu
set -o pipefail

source "${BASH_SOURCE[0]%/*}"/../../lib/logging.sh


cluster_remote1=remote1
cluster_remote2=remote2

# Deploy the hello-world application.
function helloapp::deploy {
	local cluster_name=$1
	local version=$2

	istio::namespace::create "${cluster_name}" hello

	# Copied and adapted from
	#   samples/helloworld/helloworld.yaml
	kubectl apply \
		--context="kind-${cluster_name}" \
		-n hello \
		-f - <<-EOM >/dev/null
			apiVersion: v1
			kind: Service
			metadata:
			  name: helloworld
			  labels:
			    app: helloworld
			spec:
			  ports:
			  - name: http
			    port: 80
			    targetPort: http
			  selector:
			    app: helloworld
			---
			apiVersion: apps/v1
			kind: Deployment
			metadata:
			  name: helloworld-${version}
			  labels:
			    app: helloworld
			    version: ${version}
			spec:
			  replicas: 1
			  selector:
			    matchLabels:
			      app: helloworld
			      version: ${version}
			  template:
			    metadata:
			      labels:
			        app: helloworld
			        version: ${version}
			    spec:
			      containers:
			      - name: helloworld
			        image: antoineco/http-echo@sha256:c969f8b4a129e2eb6ea611d2f63b78a600127135daa0a7036efdacd868e72198  # tag:latest
			        args:
			        - -text
			        - helloworld ${version} on pod \$(POD_NAME)
			        env:
			        - name: POD_NAME
			          valueFrom:
			            fieldRef:
			              fieldPath: metadata.name
			        ports:
			        - name: http
			          containerPort: 5678
			        startupProbe:
			          httpGet:
			            path: /health
			            port: http
			          periodSeconds: 1
			          failureThreshold: 20
			        readinessProbe:
			          httpGet:
			            path: /health
			            port: http
		EOM

	kubectl wait deployments.apps \
		--context="kind-${cluster_name}" \
		-n hello \
		--timeout=1m \
		--for=condition=Available \
		-l app=helloworld \
		>/dev/null

	log::submsg "[${cluster_name}] Hello app deployed"
}

# Terminate the hello-world application.
function helloapp::terminate {
	local cluster_name=$1

	istio::namespace::delete "${cluster_name}" hello

	log::submsg "[${cluster_name}] Hello app terminated"
}

# Smoke test the hello-world application.
function helloapp::smoke_test {
	local cluster_name=$1
	local namespace=$2

	kubectl wait pod \
		--context="kind-${cluster_name}" \
		-n ${namespace} \
		--for=delete \
		--timeout=10s \
		poke-hello \
		>/dev/null

	# Sleep before sending HTTP requests to give kubectl enough time to
	# attach and avoid missing some output.
	while IFS= read -r line; do
		log::submsg "${line}"
	done < <(kubectl run \
		--context="kind-${cluster_name}" \
		-n ${namespace} \
		--attach \
		--image=curlimages/curl@sha256:9fab1b73f45e06df9506d947616062d7e8319009257d3a05d970b0de80a41ec5 `# tag:7.85.0` \
		--rm \
		poke-hello -- \
		sh -c '
			sleep 2;
			for _ in $(seq 1 5);
				do curl -s http://helloworld.hello.svc.cluster.local;
			done
		' \
		2>/dev/null
	)
}

# Create a Kubernetes namespace with Istio sidecar injection.
function istio::namespace::create {
	local cluster_name=$1
	local namespace=$2

	# Adapted from
	#   https://istio.io/v1.15/docs/setup/install/multicluster/verify/#deploy-the-helloworld-service
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

# Delete a Kubernetes namespace.
function istio::namespace::delete {
	local cluster_name=$1
	local namespace=$2

	kubectl delete "ns/${namespace}" \
		--context="kind-${cluster_name}" \
		>/dev/null
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

log::msg "Deploying hello app inside remote clusters"
helloapp::deploy "${cluster_remote1}" v1 &
helloapp::deploy "${cluster_remote2}" v2 &
wait

log::msg "Printing Envoy endpoints for hello app in ${cluster_remote1}"
istio::proxy::endpoints "${cluster_remote1}" hello helloworld 'outbound|80||helloworld.hello.svc.cluster.local'
log::msg "Printing Envoy endpoints for hello app in ${cluster_remote2}"
istio::proxy::endpoints "${cluster_remote2}" hello helloworld 'outbound|80||helloworld.hello.svc.cluster.local'

log::msg "Smoke testing hello app from ${cluster_remote1}"
istio::namespace::create "${cluster_remote1}" hello-consumer
helloapp::smoke_test "${cluster_remote1}" hello-consumer
istio::namespace::delete "${cluster_remote1}" hello-consumer &
log::msg "Smoke testing hello app from ${cluster_remote2}"
istio::namespace::create "${cluster_remote2}" hello-consumer
helloapp::smoke_test "${cluster_remote2}" hello-consumer
istio::namespace::delete "${cluster_remote2}" hello-consumer &

log::msg "Terminating hello app inside remote clusters"
helloapp::terminate "${cluster_remote1}" &
helloapp::terminate "${cluster_remote2}" &
wait
