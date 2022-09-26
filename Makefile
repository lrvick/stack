DEBUG := false
OUT_DIR := out
SRC_DIR := src
TARGET := generic
CACHE_DIR := cache
CONFIG_DIR := config
IMAGES_DIR := images
USER := $(shell id -g):$(shell id -g)
CPUS := $(shell nproc)
ARCH := x86_64
ENVIRONMENT := production
NAMESPACE := personal
PATH := $(PATH):$(PWD)/tools
SHELL := env PATH=$(PATH) /bin/bash
REGION := sfo3
include $(PWD)/config/global.env

export TF_VAR_talosos-image := ../../cache/archives/digital-ocean-amd64.raw.gz
export TF_VAR_talosos-version := $(TALOSOS_VERSION)
export TF_VAR_region := $(REGION)
export TF_VAR_environment := $(ENVIRONMENT)
export TF_VAR_namespace := $(NAMESPACE)

.DEFAULT_GOAL := default
.PHONY: default
default: tools

.PHONY: clean
clean:
	rm -rf images/*.tar cache out
	docker image rm -f local/$(NAME)-build

.PHONY: toolchain-shell
toolchain-shell: images/toolchain.tar
	$(call toolchain,$(USER),bash)

.PHONY: toolchain-update
toolchain-update:
	docker run \
		--rm \
		--env LOCAL_USER=$(USER) \
		--platform=linux/$(ARCH) \
		--volume $(PWD)/config:/config \
		--volume $(PWD)/images/toolchain/scripts:/usr/local/bin \
		--env GNUPGHOME=/cache/.gnupg \
		--env ARCH=$(ARCH) \
		--interactive \
		--tty \
		debian@sha256:$(DEBIAN_HASH) \
		bash -c /usr/local/bin/packages-update

.PHONY: infra
infra: \
	tools/terraform \
	config/$(ENVIRONMENT).tfbackend \
	cache/plaintext/$(ENVIRONMENT).env \
	cache/archives/digital-ocean-amd64.raw.gz
	source cache/plaintext/$(ENVIRONMENT).env \
	&& cd infra/main \
	&& terraform init \
		-backend-config="../../config/$(ENVIRONMENT).tfbackend" \
	&& terraform apply

cache/secrets/%.env:: secrets/%.env.asc
	gpg --decrypt $^ > $@

cache/archives/digital-ocean-amd64.raw.gz:
	mkdir -p $(@D)
	$(call download,$(TALOSOS_URL)/$(TALOSOS_VERSION)/$(@F),$@,$(TALOSOS_HASH))

config/$(ENVIRONMENT).tfbackend: \
	tools/terraform \
	cache/plaintext/$(ENVIRONMENT).env
	mkdir -p config/$(ENVIRONMENT)
	source cache/plaintext/$(ENVIRONMENT).env \
	&& cd infra/backend \
	&& terraform init \
	&& terraform apply \
	&& terraform output \
		> $(PWD)/config/$(ENVIRONMENT).tfbackend

images/toolchain.tar:
	DOCKER_BUILDKIT=1 \
	docker build \
		--tag local/$(NAME)-build \
		--build-arg DEBIAN_HASH=$(DEBIAN_HASH) \
		--build-arg CONFIG_DIR=config \
		--build-arg SCRIPTS_DIR=images/toolchain/scripts \
		-f images/toolchain/Dockerfile \
		.
	docker save "local/$(NAME)-build" -o "$@"

tools/doctl: images/toolchain.tar
	$(call git_clone,doctl,$(DOCTL_URL),$(DOCTL_REF))
	$(call toolchain,$(USER)," \
		cd /cache/doctl; \
		make build; \
		cp /cache/doctl/builds/doctl /tools/doctl; \
	")

tools/talosctl: images/toolchain.tar
	$(call git_clone,talos,$(TALOS_URL),$(TALOS_REF))
	$(call toolchain,$(USER)," \
		cd /cache/talos/cmd/talosctl; \
		CGO_ENABLED=0 \
		GOCACHE=/cache \
		GOPATH=/cache/go \
		go build \
		-ldflags="-extldflags=-static" \
		-o /tools/; \
	")

tools/kubectl: images/toolchain.tar
	$(call git_clone,kubernetes,$(KUBERNETES_URL),$(KUBERNETES_REF))
	$(call toolchain,$(USER)," \
		cd /cache/kubernetes; \
		make kubectl; \
		cp _output/bin/kubectl /tools/; \
	")

tools/terraform: images/toolchain.tar
	$(call git_clone,terraform,$(TERRAFORM_URL),$(TERRAFORM_REF))
	$(call toolchain,$(USER)," \
		cd /cache/terraform; \
		CGO_ENABLED=0 \
		GOCACHE=/cache \
		GOPATH=/cache/go \
		go build \
		-ldflags="-extldflags=-static" \
		-o /tools/; \
	")

tools/sops: images/toolchain.tar
	$(call git_clone,sops,$(SOPS_URL),$(SOPS_REF))
	$(call toolchain,$(USER)," \
		cd /cache/sops; \
		CGO_ENABLED=0 \
		GOCACHE=/cache \
		GOPATH=/cache/go \
		go build \
		-ldflags="-extldflags=-static" \
		-o /tools/ \
		go.mozilla.org/sops/v3/cmd/sops \
	")

define toolchain
	docker load -i images/toolchain.tar
	docker run \
		--rm \
		--tty \
		--interactive \
		--user=$(1) \
		--platform=linux/$(ARCH) \
		--volume $(PWD)/config:/config \
		--volume $(PWD)/cache:/cache \
		--volume $(PWD)/cache:/home/build/.cache \
		--volume $(PWD)/tools:/tools \
		--volume $(PWD)/images:/images \
		--env ARCH=$(ARCH) \
		local/$(NAME)-build \
		bash -c $(2)
endef

define git_clone
	[ -d cache/$(1) ] || git clone $(2) cache/$(1)
	git -C cache/$(1) checkout $(3)
	git -C cache/$(1) rev-parse --verify HEAD | grep -q $(3) || { \
		echo 'Error: Git ref/branch collision.'; exit 1; \
	};
endef

define download
	curl -s -S -L -f $(1) -z $(2) -o $(2)
	openssl dgst -sha256 -r $(2) | grep -q $(3) || { \
		echo 'Error: File $(2) did not match expected hash'; exit 1; \
	};
endef
