#!/bin/bash

# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

REPO_ROOT=$(dirname "${BASH_SOURCE}")/..
RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-""}
LOCATION=${LOCATION:-""}

#Check for variables is initialized or not
SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-""}
CLIENT_ID=${CLIENT_ID:-""}
CLIENT_SECRET=${CLIENT_SECRET:-""}
TENANT_ID=${TENANT_ID:-""}
USE_CSI_DEFAULT_STORAGECLASS=${USE_CSI_DEFAULT_STORAGECLASS:-""}
ENABLE_AVAILABILITY_ZONE=${ENABLE_AVAILABILITY_ZONE:-""}

# Check for variables is initialized or not
if [ -z "$LOCATION" ] || [ -z "${SUBSCRIPTION_ID}" ] || [ -z "${CLIENT_ID}" ] || [ -z "${CLIENT_SECRET}" ] || [ -z "${TENANT_ID}" ] || [ -z "${USE_CSI_DEFAULT_STORAGECLASS}" ]; then
  echo "SUBSCRIPTION_ID, CLIENT_ID, TENANT_ID, CLIENT_SECRET ,LOCATION and USE_CSI_DEFAULT_STORAGECLASS must be specified"
  exit 1
fi
if [ -z "$IMAGE" ] || [ -z "${HYPERKUBE_IMAGE}" ]; then
  echo "Please deploy the cluster by running 'IMAGE_REGISTRY=<your-registry> make deploy'."
  exit 1
fi

if [ "$RESOURCE_GROUP_NAME" = "" ]
then
echo "RESOURCE GROUP NAME must be specified"
exit 1
fi

# Check for commands which would be used in following steps.
if ! [ -x "$(command -v jq)" ]; then
  echo 'Error: jq is not installed. Please follow https://stedolan.github.io/jq/ to install it.'
  exit 1
fi
if ! [ -x "$(command -v aks-engine)" ]; then
  echo 'Error: aks-engine is not installed. Please follow https://github.com/Azure/aks-engine to install it.'
  exit 1
fi

# Initialize variables
manifest_file=$(mktemp)
if [ -z "$RESOURCE_GROUP_NAME" ]; then
  UUID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
  RESOURCE_GROUP_NAME="k8s-$UUID"
fi

# Add handler for cleanup
function cleanup() {
  rm -f ${manifest_file}
}
trap cleanup EXIT

base_manifest=${REPO_ROOT}/examples/aks-engine.json
if [ ! -z "$ENABLE_AVAILABILITY_ZONE" ]; then
    base_manifest=${REPO_ROOT}/examples/az.json
fi

# Configure the manifests for aks-engine
cat $base_manifest | \
  jq ".properties.orchestratorProfile.kubernetesConfig.customCcmImage=\"${IMAGE}\"" | \
  jq ".properties.orchestratorProfile.kubernetesConfig.customHyperkubeImage=\"${HYPERKUBE_IMAGE}\"" | \
  jq ".properties.servicePrincipalProfile.clientID=\"${CLIENT_ID}\"" | \
  jq ".properties.servicePrincipalProfile.secret=\"${CLIENT_SECRET}\"" \
  > ${manifest_file}

# Deploy the cluster
echo "Deploying kubernetes cluster to resource group ${RESOURCE_GROUP_NAME}..."
aks-engine deploy --subscription-id ${SUBSCRIPTION_ID} \
  --auth-method client_secret \
  --auto-suffix \
  --resource-group ${RESOURCE_GROUP_NAME} \
  --location ${LOCATION} \
  --api-model ${manifest_file} \
  --client-id ${CLIENT_ID} \
  --client-secret ${CLIENT_SECRET}
echo "Kubernetes cluster deployed. Please find the kubeconfig for it in _output/"

export KUBECONFIG=_output/$(ls -t _output | head -n 1)/kubeconfig/kubeconfig.$LOCATION.json
echo "Kubernetes cluster deployed. Please find the kubeconfig at $KUBECONFIG"

# Deploy AzureDisk CSI Plugin
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/crd-csi-driver-registry.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/crd-csi-node-info.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/rbac-csi-attacher.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/rbac-csi-driver-registrar.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/rbac-csi-provisioner.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/rbac-csi-snapshotter.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/csi-azuredisk-provisioner.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/csi-azuredisk-attacher.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/azuredisk-csi-driver.yaml
# create storage class.
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/example/storageclass-azuredisk-csi.yaml

# Deploy AzureFile CSI Plugin
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/crd-csi-driver-registry.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/crd-csi-node-info.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/rbac-csi-attacher.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/rbac-csi-driver-registrar.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/rbac-csi-provisioner.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/rbac-csi-snapshotter.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/csi-azurefile-provisioner.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/csi-azurefile-attacher.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/azurefile-csi-driver.yaml
# create storage class.
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/example/storageclass-azurefile-csi.yaml

if [ $USE_CSI_DEFAULT_STORAGECLASS = "Yes" ]
then
kubectl delete storageclass default
cat <<EOF | kubectl apply -f-
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    storageclass.beta.kubernetes.io/is-default-class: "true"
  name: default
provisioner: disk.csi.azure.com
parameters:
  skuname: Standard_LRS # available values: Standard_LRS, Premium_LRS, StandardSSD_LRS and UltraSSD_LRS
  kind: managed         # value "dedicated", "shared" are deprecated since it's using unmanaged disk
  cachingMode: ReadOnly
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
fi
