# SHELL defines bash so all the inline scripts here will work as expected.
SHELL := /bin/bash

OPERATOR_NAME := machine-deletion-remediation

## Tool versions
# OPERATOR_SDK versions at github.com/operator-framework/operator-sdk/releases
OPERATOR_SDK_VERSION ?= v1.25.1

# OPM versions at https://github.com/operator-framework/operator-registry/releases
OPM_VERSION = v1.15.1

# CONTROLLER_GEN versions at https://github.com/kubernetes-sigs/controller-tools/releases
CONTROLLER_GEN_VERSION = v0.9.2

# KUSTOMIZE versions at https://github.com/kubernetes-sigs/kustomize/releases
# note: update KUSTOMIZE_VERSION and KUSTOMIZE_API_VERSION accordingly.
KUSTOMIZE_API_VERSION = v4
KUSTOMIZE_VERSION = v4.5.7

# ENVTEST has no tagged versions yet
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_VERSION = v0.0.0-20230208013708-22718275bffe
ENVTEST_K8S_VERSION = 1.23

# GoImports versions at https://pkg.go.dev/golang.org/x/tools/cmd/goimports?tab=versions
GOIMPORTS_VERSION ?= v0.6.0

# Sort-imports versions at https://github.com/slintes/sort-imports/releases
SORT_IMPORTS_VERSION = v0.2.1

# VERSION defines the project version for the bundle. 
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
DEFAULT_VERSION := 0.0.1
VERSION ?= $(DEFAULT_VERSION)
export VERSION

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "preview,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=preview,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="preview,fast,stable")
CHANNELS ?= candidate
export CHANNELS

ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
DEFAULT_CHANNEL ?= candidate
export DEFAULT_CHANNEL

ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# IMAGE_REGISTRY used to indicate the registery/group for the operator, bundle and catalog
IMAGE_REGISTRY ?= quay.io/medik8s
export IMAGE_REGISTRY

# When no version is set, use latest as image tags
ifeq ($(VERSION), $(DEFAULT_VERSION))
IMAGE_TAG = latest
else
IMAGE_TAG = v$(VERSION)
endif
export IMAGE_TAG

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# medik8s/machine-deletion-remediation-bundle:$(IMAGE_TAG) and medik8s/machine-deletion-remediation-catalog:$(IMAGE_TAG).
IMAGE_TAG_BASE ?= $(IMAGE_REGISTRY)/$(OPERATOR_NAME)

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG ?= $(IMAGE_TAG_BASE)-operator-catalog:$(IMAGE_TAG)

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG ?= $(IMAGE_TAG_BASE)-operator-bundle:$(IMAGE_TAG)

# Image URL to use all building/pushing image targets
export IMG ?= $(IMAGE_TAG_BASE)-operator:$(IMAGE_TAG)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

.PHONY: all
all: manager

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

# Generate manifests e.g. CRD, RBAC etc.
.PHONY: manifests
manifests: controller-gen
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# Generate code
.PHONY: generate
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: goimports ## Run go goimports against code - goimports = go fmt + fixing imports.
	$(GOIMPORTS) -w  ./main.go ./api ./controllers ./e2e

# Run go vet against code
.PHONY: vet
vet:
	go vet ./...

.PHONY: test-imports
test-imports: sort-imports ## Check for sorted imports
	$(SORT_IMPORTS) .

.PHONY: fix-imports
fix-imports: sort-imports ## Sort imports
	$(SORT_IMPORTS) -w .

.PHONY: verify-no-changes
verify-no-changes: ## verify no there are no un-staged changes
	./hack/verify-diff.sh

.PHONY: fetch-mutation
fetch-mutation: ## fetch mutation package.
	GO111MODULE=off go get -t -v github.com/mshitrit/go-mutesting/...

# Run tests
test: manifests generate test-imports fmt vet envtest 
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) -p path  --bin-dir $(PROJECT_DIR)/testbin)" \
		go test ./controllers/... -coverprofile cover.out -ginkgo.vv -ginkgo.focus "machine associated to worker node fails deletion"

test-mutation: verify-no-changes fetch-mutation ## Run mutation tests in manual mode.
	echo -e "## Verifying diff ## \n##Mutations tests actually changes the code while running - this is a safeguard in order to be able to easily revert mutation tests changes (in case mutation tests have not completed properly)##"
	./hack/test-mutation.sh

test-mutation-ci: fetch-mutation ## Run mutation tests as part of auto build process.
	./hack/test-mutation.sh

.PHONY: test-e2e
test-e2e: ## Run end to end tests
	# KUBECONFIG must be set to the cluster, and MDR needs to be deployed already
	@test -n "${KUBECONFIG}" -o -r ${HOME}/.kube/config || (echo "Failed to find kubeconfig in ~/.kube/config or no KUBECONFIG set"; exit 1)
	go test ./e2e -coverprofile cover.out -v -timeout 25m -ginkgo.vv

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager main.go

run: manifests generate fmt vet ## Run a controller from your host.
	go run ./main.go

docker-build: test ## Build docker image with the manager.
	docker build -t ${IMG} .

docker-push: ## Push docker image with the manager.
	docker push ${IMG}

##@ Deployment

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
.PHONY: uninstall
uninstall: manifests kustomize
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
.PHONY: deploy
deploy: manifests kustomize
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

# UnDeploy controller from the configured Kubernetes cluster in ~/.kube/config
.PHONY: undeploy
undeploy:
	$(KUSTOMIZE) build config/default | kubectl delete -f -


##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

.PHONY: controller-gen
CONTROLLER_GEN = $(LOCALBIN)/controller-gen
controller-gen: ## Download controller-gen locally if necessary
	$(call go-install-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_GEN_VERSION))


.PHONY: kustomize
KUSTOMIZE = $(LOCALBIN)/kustomize
kustomize: ## Download kustomize locally if necessary
	$(call go-install-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/$(KUSTOMIZE_API_VERSION)@$(KUSTOMIZE_VERSION))

.PHONY: envtest
ENVTEST = $(LOCALBIN)/setup-envtest
envtest: ## Download envtest-setup locally if necessary.
	$(call go-install-tool,$(ENVTEST),sigs.k8s.io/controller-runtime/tools/setup-envtest@$(ENVTEST_VERSION))

.PHONY: goimports
GOIMPORTS = $(LOCALBIN)/goimports
goimports: ## Download goimports locally if necessary.
	$(call go-install-tool,$(GOIMPORTS),golang.org/x/tools/cmd/goimports@$(GOIMPORTS_VERSION))

.PHONY: sort-imports
SORT_IMPORTS = $(LOCALBIN)/sort-imports
sort-imports: ## Download sort-imports locally if necessary.
	$(call go-install-tool,$(SORT_IMPORTS),github.com/slintes/sort-imports@$(SORT_IMPORTS_VERSION))

# go-install-tool will 'go install' any package $2 and install it to $1.
PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
define go-install-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
GOBIN=$(PROJECT_DIR)/bin GOFLAGS='' go install $(2) ;\
rm -rf $$TMP_DIR ;\
}
endef

.PHONY: bundle
bundle: manifests kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)
	$(MAKE) bundle-validate

##@ Bundle Creation Addition
## Some addition to bundle creation in the bundle
.PHONY: bundle-update
bundle-update: ## Update containerImage and createdAt
	sed -r -i "s|containerImage: .*|containerImage: $(IMG)|;" ./bundle/manifests/$(OPERATOR_NAME).clusterserviceversion.yaml
	sed -r -i "s|createdAt: .*|createdAt: \"`date '+%Y-%m-%d %T'`\"|;" ./bundle/manifests/$(OPERATOR_NAME).clusterserviceversion.yaml
	$(MAKE) bundle-validate

.PHONY: bundle-validate
bundle-validate: operator-sdk ## Validate the bundle directory with additional validators (suite=operatorframework), such as Kubernetes deprecated APIs (https://kubernetes.io/docs/reference/using-api/deprecation-guide/) based on bundle.CSV.Spec.MinKubeVersion
	$(OPERATOR_SDK) bundle validate ./bundle --select-optional suite=operatorframework
	
# Build the bundle image.
.PHONY: bundle-build
bundle-build: bundle bundle-update ## Build the bundle image.
	docker build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

# Push the bundle image
.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)

# Run bundle image
.PHONY: bundle-run
bundle-run: operator-sdk
	$(OPERATOR_SDK) -n openshift-operators run bundle $(BUNDLE_IMG)

.PHONY: opm
OPM_DIR = $(LOCALBIN)/opm
OPM = $(OPM_DIR)/$(OPM_VERSION)/opm
opm: ## Download opm locally if necessary.
	$(call operator-framework-tool, $(OPM), $(OPM_DIR),https://github.com/operator-framework/operator-registry/releases/download/$(OPM_VERSION)/$${OS}-$${ARCH}-opm )

.PHONY: operator-sdk
OPERATOR_SDK_DIR ?= $(LOCALBIN)/operator-sdk
OPERATOR_SDK = $(OPERATOR_SDK_DIR)/$(OPERATOR_SDK_VERSION)/operator-sdk
operator-sdk: ## Download operator-sdk locally if necessary.
	$(call operator-framework-tool, $(OPERATOR_SDK), $(OPERATOR_SDK_DIR),github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_$${OS}_$${ARCH})

# operator-framework-tool will delete old package $2, then download $3 to $1.
define operator-framework-tool
@[ -f $(1) ] || { \
	set -e ;\
	rm -rf $(2) ;\
	mkdir -p $(dir $(1)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	echo "Downloading $(3)" ;\
	curl -sSLo $(1) $(3) ;\
	chmod +x $(1) ;\
	}
endef

# A comma-separated list of bundle images (e.g. make catalog-build BUNDLE_IMGS=example.com/operator-bundle:v0.1.0,example.com/operator-bundle:v0.2.0).
# These images MUST exist in a registry and be pull-able.
BUNDLE_IMGS ?= $(BUNDLE_IMG)

# Set CATALOG_BASE_IMG to an existing catalog image tag to add $BUNDLE_IMGS to that image.
ifneq ($(origin CATALOG_BASE_IMG), undefined)
FROM_INDEX_OPT := --from-index $(CATALOG_BASE_IMG)
endif

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-build
catalog-build: opm ## Build a catalog image.
	$(OPM) index add --container-tool docker --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT)

.PHONY: catalog-push
catalog-push: ## Push a catalog image.
	$(MAKE) docker-push IMG=$(CATALOG_IMG)

##@ Targets used by CI

.PHONY: container-build
container-build: ## Build containers
	make docker-build bundle-build

.PHONY: container-push
container-push:  ## Push containers (NOTE: catalog can't be build before bundle was pushed)
	make docker-push bundle-push catalog-build catalog-push
