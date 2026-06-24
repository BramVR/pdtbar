.PHONY: docs-list test

docs-list:
	node Scripts/docs-list.mjs

test:
	./Scripts/test.sh
