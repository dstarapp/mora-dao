#!/bin/bash

# cd into the folder containing this script
SCRIPT=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT")
cd $SCRIPT_DIR/..

CANISTER_NAME=$1

# Set env variables based on .env file
set -o allexport; source .env; set +o allexport

echo NETWORK=$NETWORK
echo PEM_FILE=$PEM_FILE
dfx build --network $NETWORK $CANISTER_NAME

echo Compressing wasm
mkdir -p wasms
gzip -fckn .dfx/${NETWORK}/canisters/${CANISTER_NAME}/${CANISTER_NAME}.wasm > ./wasms/$CANISTER_NAME.wasm.gz
echo ${CANISTER_NAME}_wasm_sha256=$(sha256 ./wasms/$CANISTER_NAME.wasm.gz)