.PHONY: check lint test test-pty

# Runs every pass even when an earlier one fails, as CI does, so a failure in
# one does not hide the result of the next. Fails if any pass failed.
check:
	@rc=0; \
	$(MAKE) lint || rc=1; \
	$(MAKE) test || rc=1; \
	$(MAKE) test-pty || rc=1; \
	exit $$rc

# A syntax check on the script, the pty runner and the benchmark scripts, a check that the version
# the script reports is the one the plugin manifest declares, and — when the
# claude CLI is on PATH — a strict validation of the plugin and marketplace
# manifests. CI has no claude CLI, so the last check runs only locally.
lint:
	@command -v jq >/dev/null 2>&1 || { echo "lint: needs jq on PATH" >&2; exit 1; }
	zsh -n gh-comments
	python3 -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' tests/run-pty.py bench/*.py
	for f in bench/*.zsh; do zsh -n "$$f" || exit 1; done
	@v=$$(sed -n 's/^VERSION=//p' gh-comments); m=$$(jq -r .version .claude-plugin/plugin.json); \
	if [ "$$v" != "$$m" ]; then \
	  echo "lint: version mismatch: gh-comments says $$v, .claude-plugin/plugin.json says $$m" >&2; exit 1; \
	fi; echo "version $$v"
	@if command -v claude >/dev/null 2>&1; then claude plugin validate --strict .; \
	else echo "lint: claude CLI not on PATH, plugin manifests not validated" >&2; fi

# The offline suite: goldens over saved API payloads, plus a stubbed gh for
# the fetch paths.
test:
	zsh tests/run.zsh

# The same suite under a real controlling terminal.
test-pty:
	python3 tests/run-pty.py
