// This is a generated Motoko binding.
// Please use `import service "ic:canister_id"` instead to call canisters on the IC if possible.

module {
  public type InviteCodeActor = actor {
    verify_code : shared (Text, Principal) -> async Bool;
  };
  public type Self = (Principal, Principal) -> async InviteCodeActor;
};
