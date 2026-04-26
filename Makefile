.PHONY: test smoke autopilot-help

test:
	python3 -m unittest discover -s tests

smoke:
	scripts/bootstrap_smoke.sh

autopilot-help:
	@scripts/project_autopilot_supervisor.py --help
