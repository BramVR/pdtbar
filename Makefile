.PHONY: docs-list docs-site docs-site-test docs-site-clean start restart stop build test check

docs-list:
	node Scripts/docs-list.mjs

docs-site:
	node Scripts/build-docs-site.mjs

docs-site-test:
	node --test Scripts/build-docs-site.test.mjs

docs-site-clean:
	rm -rf dist/docs-site

start:
	./Scripts/compile_and_run.sh

restart: start

stop:
	./Scripts/stop.sh

build:
	swift build --product pdtbar

test:
	./Scripts/test.sh

check:
	./Scripts/check.sh
