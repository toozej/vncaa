# Set sane defaults for Make
SHELL = bash
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

# Set default goal such that `make` runs `make help`
.DEFAULT_GOAL := help

# Build info
BUILDER = $(shell whoami)@$(shell hostname)
NOW = $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# Version control
VERSION = $(shell git describe --tags --dirty --always)
COMMIT = $(shell git rev-parse --short HEAD)
BRANCH = $(shell git rev-parse --abbrev-ref HEAD)
	
# Define the repository URL
REPO_URL := https://github.com/toozej/vncaa

# Detect the OS and architecture
OS := $(shell uname -s)
ARCH := $(shell uname -m)

ifeq ($(OS), Linux)
	OPENER=xdg-open
else
	OPENER=open
endif

.PHONY: all test build run up down local local-vet local-test pre-commit-install pre-commit-run pre-commit pre-reqs clean help

all: pre-commit clean build run ## Run default workflow via Docker
local: local-update-deps local-vet pre-commit clean local-test local-build ## Run default workflow using locally installed Golang toolchain
pre-reqs: pre-commit-install ## Install pre-commit hooks and necessary binaries

build: ## Build Docker image, including running tests
	docker build -f $(CURDIR)/Dockerfile -t toozej/vncaa:latest .

test: ## Run tests inside Docker container
	docker build -f $(CURDIR)/Dockerfile -t toozej/vncaa:test .

run: ## Run built Docker image
	docker run --rm --name vncaa toozej/vncaa:latest

up: test build ## Run Docker Compose project with build Docker image
	docker compose -f docker-compose.yml down --remove-orphans
	docker compose -f docker-compose.yml pull
	docker compose -f docker-compose.yml up -d

down: ## Stop running Docker Compose project
	docker compose -f docker-compose.yml down --remove-orphans

local-update-deps: ## Run `cargo update` to update Rust dependencies
	cargo update --verbose

local-vet: ## Run `cargo fmt and cargo clippy` using locally installed Rust toolchain
	cargo fmt --all --
	cargo clippy -- -D warnings

local-test: ## Run `cargo test` using locally installed Rust toolchain
	cargo test --all --verbose -- --nocapture

local-build: ## Run `cargo build` using locally installed Rust toolchain
	cargo build --verbose

pre-commit: pre-commit-install pre-commit-run ## Install and run pre-commit hooks

pre-commit-install: ## Install pre-commit hooks and necessary binaries
	command -v apt && apt-get update || echo "package manager not apt"
	# rust + cargo
	command -v cargo || brew install rust || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
	command -v cargo || export PATH="$${HOME}/.cargo/bin:$${PATH}"
	# shellcheck
	command -v shellcheck || brew install shellcheck || apt install -y shellcheck || sudo dnf install -y ShellCheck || sudo apt install -y shellcheck
	# checkmake
	go install github.com/checkmake/checkmake/cmd/checkmake@latest
	# actionlint
	command -v actionlint || brew install actionlint || go install github.com/rhysd/actionlint/cmd/actionlint@latest
	# syft
	command -v syft || curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
	# graphviz for dot
	command -v dot || brew install graphviz || sudo apt install -y graphviz || sudo dnf install -y graphviz
	# install and update pre-commits
	# determine if on Debian 12 and if so use pip to install more modern pre-commit version
	grep --silent "VERSION=\"12 (bookworm)\"" /etc/os-release && apt install -y --no-install-recommends python3-pip && python3 -m pip install --break-system-packages --upgrade pre-commit || echo "OS is not Debian 12 bookworm"
	command -v pre-commit || brew install pre-commit || sudo dnf install -y pre-commit || sudo apt install -y pre-commit
	pre-commit install
	pre-commit autoupdate

pre-commit-run: ## Run pre-commit hooks against all files
	pre-commit run --all-files
	# manually run the following checks since their pre-commits aren't working or don't exist

clean: ## Remove any locally compiled binaries and Docker images
	rm -rf $(CURDIR)/target/
	docker rmi toozej/vncaa

help: ## Display help text
	@grep -E '^[a-zA-Z_-]+ ?:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
