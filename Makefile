.PHONY: test smoke check autopilot-help

test:
	python3 -m unittest discover -s tests

smoke:
	scripts/bootstrap_smoke.sh
	scripts/stdout_smoke.sh
	scripts/stdin_smoke.sh

check: test smoke

autopilot-help:
	@scripts/project_autopilot_supervisor.py --help
