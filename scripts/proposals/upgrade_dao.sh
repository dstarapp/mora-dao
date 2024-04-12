#!/bin/bash

VERSION=$1
CHANGELOG_PATH=$2

TITLE="Upgrade SubDao canister to $VERSION"
CHANGELOG=`cat $CHANGELOG_PATH`
FUNCTION_ID=3
CANISTER_NAME=dao

# Set current directory to the scripts root
SCRIPT=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT")
cd $SCRIPT_DIR/..

echo $CHANGELOG
./build.sh $CANISTER_NAME || exit 1

# Submit the proposal
./make_upgrade_canister.sh $FUNCTION_ID $CANISTER_NAME "$VERSION" "$TITLE" "$CHANGELOG"