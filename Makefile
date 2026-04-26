.PHONY: test autopilot-help

test:
	python3 -m unittest discover -s tests

autopilot-help:
	@scripts/project_autopilot_supervisor.py --help
