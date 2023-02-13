#!/usr/bin/env bash

source "${BASH_SOURCE[0]%/*}"/../../../lib/logging.sh
source "${BASH_SOURCE[0]%/*}"/istio.sh
source "${BASH_SOURCE[0]%/*}"/kubernetes.sh


# Deploy the hello-world application.
function helloapp::deploy {
	local cluster_name=$1
	local namespace=$2

	istio::namespace::create "${cluster_name}" "${namespace}"

	# Copied and adapted from
	#   samples/helloworld/helloworld.yaml
	kubectl apply \
		--context="kind-${cluster_name}" \
		-n "${namespace}" \
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
			  name: helloworld
			  labels:
			    app: helloworld
			spec:
			  replicas: 1
			  selector:
			    matchLabels:
			      app: helloworld
			  template:
			    metadata:
			      labels:
			        app: helloworld
			    spec:
			      containers:
			      - name: helloworld
			        image: antoineco/http-echo@sha256:c969f8b4a129e2eb6ea611d2f63b78a600127135daa0a7036efdacd868e72198  # tag:latest
			        args:
			        - -text
			        - helloworld on pod \$(POD_NAME) in namespace \$(POD_NAMESPACE)
			        env:
			        - name: POD_NAMESPACE
			          valueFrom:
			            fieldRef:
			              fieldPath: metadata.namespace
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
		-n "${namespace}" \
		--timeout=1m \
		--for=condition=Available \
		-l app=helloworld \
		>/dev/null

	log::submsg "[${cluster_name}] Hello app deployed to namespace ${namespace}"
}

# Terminate the hello-world application.
function helloapp::terminate {
	local cluster_name=$1
	local namespace=$2

	kubernetes::namespace::delete "${cluster_name}" "${namespace}"

	log::submsg "[${cluster_name}] Hello app terminated in namespace ${namespace}"
}

# Smoke test the hello-world application.
function helloapp::smoke_test {
	local cluster_name=$1
	local namespace=$2
	local hello_namespace=$3

	kubectl wait pod \
		--context="kind-${cluster_name}" \
		-n ${namespace} \
		--for=delete \
		--timeout=10s \
		"poke-${hello_namespace}" \
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
		"poke-${hello_namespace}" -- \
		sh -c '
			sleep 3;
			curl -s http://helloworld.'"${hello_namespace}"'.svc.cluster.local
		' \
		2>/dev/null
	)
}
