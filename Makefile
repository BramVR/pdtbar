.PHONY: docs-list start restart stop build test check

docs-list:
	node Scripts/docs-list.mjs

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
