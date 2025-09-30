# Define variables
SHELLCHECK = shellcheck
BATS = bats
BPkg = bpkg

# Directories
SRC_DIR = ./
TEST_DIR = tests

# Targets
.PHONY: all lint test install_deps clean docs

# install_deps:
# 	@echo "Installing dependencies with bpkg..."
# 	@$(BPkg) install -g shellcheck || echo "shellcheck already installed"
# 	@$(BPkg) install -g bats-core/bats-core || echo "bats already installed"

format:
	@echo "Formatting scripts..."
	@shfmt -l -w *.sh
	@bashate *.sh --ignore E002,E003,E006

clean:
	@echo "Cleaning up..."
	@rm -rf $(TEST_DIR)/tmp

# Quality control

lint:
	@echo "Running shellcheck on all scripts..."
	@$(SHELLCHECK) -x $(SRC_DIR)/*.sh

test:
    # bats isopod_shell_test.bats
	@echo "Running bats tests..."
	@$(BATS) $(TEST_DIR)

# Dependency installation

install_bpkg:
	@echo "Installing bpkg..."
	@curl -sLo- "https://get.bpkg.sh" | bash

pipx_installs:
	@echo "Installing pipx packages..."
    # dev support
	@pipx install shelldoc
	@pipx install md-to-html
	@pipx install bashate

winget_installs:
	@echo "Installing winget packages..."
	@winget install jqlang.jq
	@winget install --id koalaman.shellcheck

npm_installs:
	@echo "Installing npm packages..."
	@npm install -g bats
	@npm install --save-dev https://github.com/ztombol/bats-support
	@npm install --save-dev https://github.com/ztombol/bats-assert


go_installs:
	@echo "Installing go packages..."
	@go install mvdan.cc/sh/v3/cmd/shfmt@latest

# Generate documentation

docs:
	@shelldoc -f *.sh
	@for FILE in ./docs/*.md; do md-to-html --input "$$FILE" --output "$$FILE".html; done

open_docs:
	if [ "$$(uname)" = "Linux" ]; then \
	    xdg-open ./docs/*.html; \
	elif [ "$$(uname)" = "Darwin" ]; then \
	    open ./docs/*.html; \
	elif [ "$$(uname | grep -i 'mingw\|msys\|cygwin')" ]; then \
	    start ./docs/*.html; \
	else \
	    echo "Unsupported OS"; \
	fi

check: format lint test docs

# pipx install codespell
# cargo install typos-cli
# npm i markdown-spellcheck -g
# These checks aren't very strict because of the high false positive rate of spell checking source code.
spellcheck:
	codespell *.sh tests/*.sh README.md
	typos README.md tests
	mdspell README.md --report