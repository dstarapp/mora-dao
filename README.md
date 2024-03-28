# MORA DAO

## Introduction

Mora DAO is Mora's launchtrail submiter, It manages all the planets canister install/upgrade.

The planet's agreepayee is also this canister account.

It will become the governance of mora in the future!

## Used WASM Source

Planet wasm: bin/planet_ic.wasm.gz

[Planet Source](https://github.com/dstarapp/mora-planet)

```ic-repl
#!ic-repl
import helper = "dao canister id";
let wasm = file("./bin/planet_ic.wasm.gz");
call helper.setWasm(wasm);
```

Launchtrail wasm: bin/launchtrail_ic.wasm.gz

[Launchtrail Source](https://github.com/dstarapp/launchtrail)

```ic-repl
#!ic-repl
import helper = "dao canister id";
let trailWasm = file("./bin/launchtrail_ic.wasm.gz");
call helper.setTrailWasm(trailWasm);
```

## Mora Users

the mora users canister source is [here](https://github.com/dstarapp/mora-users)

## Mora Frontend

the frontend [mora.app](https://mora.app), frontend source is [here](https://github.com/dstarapp/mora-frontend)

## Help

If you want to start working on your project right away, you might want to try the following commands:

```bash
dfx help
dfx config --help
```

## Running the project locally

If you want to test your project locally, you can use the following commands:

```bash
# Starts the replica, running in the background
dfx start --background

# Deploys your canisters to the replica and generates your candid interface
dfx deploy
```
