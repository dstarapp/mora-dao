import Array "mo:base/Array";
import AccountIdentifier "mo:principal/blob/AccountIdentifier";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Result "mo:base/Result";

module {

  /// Ledger Types
  public type Memo = Nat64;
  public type Token = {
    e8s : Nat64;
  };
  public type TimeStamp = {
    timestamp_nanos : Nat64;
  };
  public type AccountIdentifier = Blob;
  public type SubAccount = Blob;
  public type BlockIndex = Nat64;
  public type TransferError = {
    #BadFee : {
      expected_fee : Token;
    };
    #InsufficientFunds : {
      balance : Token;
    };
    #TxTooOld : {
      allowed_window_nanos : Nat64;
    };
    #TxCreatedInFuture;
    #TxDuplicate : {
      duplicate_of : BlockIndex;
    };
  };
  public type TransferArgs = {
    memo : Memo;
    amount : Token;
    fee : Token;
    from_subaccount : ?SubAccount;
    to : AccountIdentifier;
    created_at_time : ?TimeStamp;
  };
  public type TransferResult = {
    #Ok : BlockIndex;
    #Err : TransferError;
  };
  public type Address = Blob;
  public type AccountBalanceArgs = {
    account : Address;
  };

  public type NotifyCanisterArgs = {
    // The of the block to send a notification about.
    block_height : BlockIndex;
    // Max fee, should be 10000 e8s.
    max_fee : Token;
    // Subaccount the payment came from.
    from_subaccount : ?SubAccount;
    // Canister that received the payment.
    to_canister : Principal;
    // Subaccount that received the payment.
    to_subaccount : ?SubAccount;
  };

  public type Ledger = actor {
    transfer : TransferArgs -> async TransferResult;
    account_balance : query AccountBalanceArgs -> async Token;
    notify_dfx : NotifyCanisterArgs -> async ();
  };

  /// CMC Types
  public type NotifyError = {
    #Refunded : {
      reason : Text;
      block_index : ?BlockIndex;
    };
    #Processing;
    #TransactionTooOld : BlockIndex;
    #InvalidTransaction : Text;
    #Other : { error_code : Nat64; error_message : Text };
  };

  public type NotifyTopUpResult = {
    #Ok : Nat;
    #Err : NotifyError;
  };

  public type NotifyTopUpArg = {
    block_index : BlockIndex;
    canister_id : Principal;
  };

  public type NotifyCreateCanisterResult = {
    #Ok : Principal;
    #Err : NotifyError;
  };

  public type NotifyCreateCanisterArg = {
    block_index : Nat64;
    controller : Principal;
  };

  public type CMC = actor {
    notify_top_up : (NotifyTopUpArg) -> async (NotifyTopUpResult);
    notify_create_canister : (NotifyCreateCanisterArg) -> async (NotifyCreateCanisterResult);
  };

  public func cross_create_canister(pid : Principal, amount : Nat64) : async Result.Result<Principal, Text> {
    let CYCLE_MINTING_CANISTER = Principal.fromText("rkp4c-7iaaa-aaaaa-aaaca-cai");
    let CREATE_CANISTER_MEMO = 0x41455243 : Nat64;
    let cmc : CMC = actor ("rkp4c-7iaaa-aaaaa-aaaca-cai");
    let ledger : Ledger = actor ("ryjl3-tyaaa-aaaaa-aaaba-cai");

    let cycle_subaccount = principalToSubAccount(pid);
    let cycle_create_account = AccountIdentifier.fromPrincipal(CYCLE_MINTING_CANISTER, ?cycle_subaccount);
    let args : TransferArgs = {
      to = cycle_create_account;
      fee = { e8s = 10_000 };
      memo = CREATE_CANISTER_MEMO;
      from_subaccount = null;
      amount = { e8s = amount };
      created_at_time = null;
    };
    switch (await ledger.transfer(args)) {
      case (#Ok(block_height)) {
        switch (await cmc.notify_create_canister({ block_index = block_height; controller = pid })) {
          case (#Ok(id)) {
            #ok(id);
          };
          case (#Err(e)) {
            #err("Notify Create Canister Failed, " # ", Error : " #debug_show (e));
          };
        };
      };
      case (#Err(e)) {
        #err("Transfer Create Canister Fee Failed, " # ", Error : " #debug_show (e));
      };
    };
  };

  // Convert principal id to subaccount id.
  // sub account = [sun_account_id_size, principal_blob, 0,0,···]
  public func principalToSubAccount(id : Principal) : [Nat8] {
    let p = Blob.toArray(Principal.toBlob(id));
    Array.tabulate(
      32,
      func(i : Nat) : Nat8 {
        if (i >= p.size() + 1) 0 else if (i == 0) (Nat8.fromNat(p.size())) else (p[i - 1]);
      },
    );
  };
};
