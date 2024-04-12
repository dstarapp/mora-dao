# Read each SNS canister id using dfx
# GOVERNANCE_CANISTER_ID=$(dfx -qq canister --network $NETWORK id sns_governance)
# INDEX_CANISTER_ID=$(dfx -qq canister --network $NETWORK id sns_index)
# LEDGER_CANISTER_ID=$(dfx -qq canister --network $NETWORK id sns_ledger)
# ROOT_CANISTER_ID=$(dfx -qq canister --network $NETWORK id sns_root)
# SWAP_CANISTER_ID=$(dfx -qq canister --network $NETWORK id sns_swap)

GOVERNANCE_CANISTER_ID="b6pbx-maaaa-aaaaq-aac7a-cai"
INDEX_CANISTER_ID="kaztj-xiaaa-aaaaq-aadaq-cai"
LEDGER_CANISTER_ID="bzohd-byaaa-aaaaq-aac7q-cai"
ROOT_CANISTER_ID="bxmkl-2iaaa-aaaaq-aac6q-cai"
SWAP_CANISTER_ID="khyv5-2qaaa-aaaaq-aadaa-cai"

# Write the json to stdout
echo "{"
echo "  \"dapp_canister_id_list\": [],"
echo "  \"governance_canister_id\": \"$GOVERNANCE_CANISTER_ID\","
echo "  \"index_canister_id\": \"$INDEX_CANISTER_ID\","
echo "  \"ledger_canister_id\": \"$LEDGER_CANISTER_ID\","
echo "  \"root_canister_id\": \"$ROOT_CANISTER_ID\","
echo "  \"swap_canister_id\": \"$SWAP_CANISTER_ID\""
echo "}"