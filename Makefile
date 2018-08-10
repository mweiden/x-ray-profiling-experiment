default: build

.PHONY: install
install:
	virtualenv -p python3 venv
	. venv/bin/activate && pip install -r requirements.txt

.PHONY: clean
clean:
	rm -rf target

.PHONY: target
target:
	mkdir -p target

.PHONY: test
test:
	. venv/bin/activate && python -m unittest discover -s test -p 'test_*.py'

.PHONY: build
build:
	. venv/bin/activate && pip install -r requirements.txt -t target/ --upgrade
	cp app.py target/

terraform-%:
	. venv/bin/activate && terraform $(*) \
		-var "aws_profile=$(AWS_PROFILE)" \
		$(shell bash -c '[[ "$(*)" == "apply" ]] && echo "-auto-approve" || echo ""')

.PHONY: deploy
deploy: terraform-apply
