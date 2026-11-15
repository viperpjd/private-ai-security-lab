.PHONY: bootstrap check tree hooks

bootstrap:
	@chmod +x scripts/*.sh
	./scripts/bootstrap-dev.sh

check:
	@chmod +x scripts/*.sh
	./scripts/check.sh

hooks:
	.venv/bin/pre-commit install

tree:
	tree -a -I '.git|.venv|__pycache__' --dirsfirst
