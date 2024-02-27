#!/usr/bin/make -f

# For `. .env` to work, even if /bin/sh is Dash:
SHELL=/bin/bash

NETWORK=local
FOUNDER = $(shell dfx identity get-principal)

BACKEND_CANISTERS = backend order personhood payments pst CanDBIndex NacDBIndex ic_eth 			#internet_identity

setup-mops:
	sudo npm i -g ic-mops
	sudo mops i

setup-cargo:
	sudo curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
	source "$HOME/.cargo/env"
	sudo cargo install cargo-audit

start-dfx:
		dfx start --background --clean
		
init-setup: setup-mops setup-cargo configure  deploy-frontend init deploy-backend

start-dev: configure deploy-frontend init

git:
	@git add .
ifdef m
	@git commit -a -m "$(m)"
else
	@git commit -a
endif
ifdef origin
	@git push $(origin)
else
	@git push
endif


.PHONY: deploy
deploy: deploy-frontend

.PHONY: build
build: build-frontend

.PHONY: configure
configure:
	for i in $(BACKEND_CANISTERS); do \
	  dfx canister create --network $(NETWORK) $$i; \
	done
	dfx canister create --network $(NETWORK) frontend
	env -i scripts/read-env.sh
	dfx build internet_identity
	dfx deploy --network $(NETWORK) backend
	dfx generate

.PHONY: install-backend
install-backend:
	for i in $(BACKEND_CANISTERS); do \
	  dfx canister install --network $(NETWORK) --mode=auto $$i; \
	done

.PHONY: install-frontend
install-frontend: install-backend
	dfx canister install --network $(NETWORK) --mode=auto frontend

.PHONY: build-backend
build-backend: do-build-backend CanDBPartition.wasm NacDBPartition.wasm

.PHONY: build-frontend
build-frontend: do-build-frontend CanDBPartition.wasm NacDBPartition.wasm

.PHONY: do-build-backend
do-build-backend:
	dfx build backend

.PHONY: do-build-frontend
do-build-frontend:
	dfx build frontend

.PHONY: CanDBPartition.wasm
CanDBPartition.wasm: do-build-backend
	. .env && moc `mops sources` --actor-idl $$PWD/.dfx/local/lsp --actor-alias ic_eth $$CANISTER_ID_ic_eth src/storage/CanDBPartition.mo
#	. .env && moc `mops sources` --actor-idl src/ic_eth --actor-alias ic_eth $$CANISTER_ID_ic_eth src/storage/CanDBPartition.mo

.PHONY: NacDBPartition.wasm
NacDBPartition.wasm:
	moc `mops sources` src/storage/NacDBPartition.mo

.PHONY: deploy-backend
deploy-backend: build-backend install-backend upgrade-partitions

.PHONY: deploy-frontend
deploy-frontend: build-frontend install-frontend upgrade-partitions

.PHONY: upgrade-partitions
upgrade-partitions:
	npx ts-node scripts/upgrade-candb.ts
	npx ts-node scripts/upgrade-nacdb.ts

.PHONY: init
init:
	dfx ledger fabricate-cycles --amount 1000000000 --canister backend
	dfx canister --network $(NETWORK) call backend init '()'
	. .env && dfx canister call --network $(NETWORK) payments init "(vec { principal \"$(FOUNDER)\"; principal \"$$CANISTER_MAIN\" })"
	. .env && dfx canister call --network $(NETWORK) CanDBIndex init "(vec { principal \"$(FOUNDER)\"; principal \"$$CANISTER_ID_MAIN\"; principal \"$$CANISTER_ID_ORDER\"; principal \"$$CANISTER_ID_PERSONHOOD\" })"
	. .env && dfx canister call --network $(NETWORK) NacDBIndex init "(vec { principal \"$(FOUNDER)\"; principal \"$$CANISTER_ID_MAIN\"; principal \"$$CANISTER_ID_ORDER\" })"
	. .env && dfx canister call --network $(NETWORK) order init "(vec { principal \"$(FOUNDER)\"; principal \"$$CANISTER_ID_MAIN\"; principal \"$$CANISTER_ID_ORDER\" })"
	mainItem=`dfx canister call --network $(NETWORK) backend createItemData \
	  '(record { price = 0.0; locale = "en"; title = "The homepage"; description = ""; details = variant { communalFolder = null } })'`; \
	  dfx canister call --network $(NETWORK) backend setRootItem "$$mainItem"
