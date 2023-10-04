#!/usr/bin/make -f

# For `. .env` to work, even if /bin/sh is Dash:
SHELL=/bin/bash

FOUNDER = $(shell dfx identity get-principal)

.PHONY: build
build:

.PHONY: deploy
deploy: deploy-frontend

.PHONY: build
build:
	dfx build main

.PHONY: deploy-backend
deploy-backend:
	dfx deploy main
#	npx ts-node scripts/upgrade-candb.ts
#	npx ts-node scripts/upgrade-nacdb.ts

.PHONY: deploy-frontend
deploy-frontend:
	dfx deploy frontend

.PHONY: init
init:
	dfx ledger fabricate-cycles --amount 1000000000 --canister main
	dfx canister call main init '()'
	dfx canister call payments init '()'
	. .env && dfx canister call CanDBIndex init "(vec { principal \"$(FOUNDER)\"; principal \"$$CANISTER_ID_MAIN\"; principal \"$$CANISTER_ID_ORDER\" })"
	. .env && dfx canister call NacDBIndex init "(vec { principal \"$(FOUNDER)\"; principal \"$$CANISTER_ID_MAIN\"; principal \"$$CANISTER_ID_ORDER\" })"
	mainItem=`dfx canister call main createItemData \
	  '(record { price = 0.0; locale = "en"; title = "The homepage"; description = ""; details = variant { communalCategory = null } })'`; \
	  dfx canister call main setRootItem "$$mainItem"
