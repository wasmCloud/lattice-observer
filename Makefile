.PHONY: setup-buildx buildx-image

PLATFORM ?= linux/amd64 # Should be linux/amd64,linux/arm64/v8

setup-buildx:
	docker buildx create --name multiarch --driver docker-container --use
	docker buildx inspect --bootstrap

buildx-image: ## Example showing segfault
	docker buildx build $(BASE_ARGS) \
		--platform $(PLATFORM) \
		--build-arg BUILDER_IMAGE=elixir:1.14.4-slim  \
		-t lattice_observer:latest \
		.