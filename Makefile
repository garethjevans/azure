

VARFILE=.azure-terraform.json
TERRAFORM=./scripts/terraform
# Grab our configured prefix from the .azure-terraform.json file
TF_VAR_PREFIX:=$(shell python -c "import json; print(json.load(open('.azure-terraform.json'))['prefix'])")
# Directory to use for local preparatory state
TFSTATE_PREPARE_DIR=.tf-prepare

check: validate generate
	@python -c "import sys; sys.exit(0) if sys.version_info > (3,0) else sys.exit('\n\nPython 3 required \n\n')"

refresh: init
	$(TERRAFORM) refresh -var-file=$(VARFILE) plans

terraform: init refresh
	$(TERRAFORM) plan -var-file=$(VARFILE) plans

validate: init
	$(TERRAFORM) validate plans

generate:
	$(MAKE) -C arm_templates

destroy: refresh
	$(TERRAFORM) destroy -var-file=$(VARFILE) plans

deploy: init refresh
	$(TERRAFORM) apply -var-file=$(VARFILE) -auto-approve=true plans

init: prepare generate
	echo "Initializing terraform"
	@$(TERRAFORM) init \
		-backend-config="storage_account_name=$(TF_VAR_PREFIX)tfstate" \
		-backend-config="container_name=tfstate" \
		-backend-config="key=terraform.tfstate" \
		-backend-config="access_key=$(shell sh -c "cd $(TFSTATE_PREPARE_DIR) && ../$(TERRAFORM) output tfstate_primary_access_key")" \
		-force-copy \
		plans

test_fmt:
	$(TERRAFORM) fmt --recursive --check=true

fmt:
	$(TERRAFORM) fmt --write=true --diff=true --recursive

tfsec:
	./scripts/tfsec

clean:
	$(MAKE) -C arm_templates clean
	rm -Rf ${TFSTATE_PREPARE_DIR}
	rm -Rf .terraform/

.PHONY: terraform deploy init clean validate generate prepare

prepare:
	# Before using azure backend, we first have to be sure that
	# remote_tfstate is correctly configured and we must to do it in an other
	# directory as the global directory is already configured to use azure backend.
	mkdir $(TFSTATE_PREPARE_DIR) || true
	cd $(TFSTATE_PREPARE_DIR) && ../$(TERRAFORM) init
	cp $(VARFILE) $(TFSTATE_PREPARE_DIR)/$(VARFILE)
	for file in variables provider remote-state; do \
		cp plans/$$file.tf $(TFSTATE_PREPARE_DIR); \
	done;
	cd $(TFSTATE_PREPARE_DIR) && ../$(TERRAFORM) init &&  ../$(TERRAFORM) apply -var-file=$(VARFILE) -auto-approve=true -refresh=true || true
	sleep 90

