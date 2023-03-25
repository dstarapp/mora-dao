// This is a generated Motoko binding.
// Please use `import service "ic:canister_id"` instead to call canisters on the IC if possible.

module {
  public type Action = {
    url : Text;
    method : Text;
    activates : Schedule;
    sha256 : ?Text;
    expires : Schedule;
    revokers : ?[Principal];
    canister : Principal;
    executors : ?[Principal];
    requires : [Nat64];
    payment : Nat;
  };
  public type Config = {
    revokers : [Principal];
    submitters : [Principal];
    min_schedule : Nat64;
  };
  public type ExecuteArgs = { args : [Nat8]; index : Nat64 };
  public type ExecuteError = {
    #Inactive;
    #NotFoundOrExpired;
    #InvalidChecksum;
    #CapacityFull;
    #Unauthorized;
    #RequiresNotOk : Nat64;
    #ChecksumMismatch;
    #Expired;
  };
  public type InitialConfig = {
    bucket_size : Nat64;
    config : Config;
    max_buckets : Nat64;
  };
  public type Item = {
    #Error : (Nat64, Int32, Text);
    #Action : Action;
    #Response : (Nat64, [Nat8]);
  };
  public type Record = { item : Item; time : Nat64; caller : ?Principal };
  public type Result = { #Ok : [Nat8]; #Err : (Int32, Text) };
  public type RevokeArgs = { index : Nat64; reason : Text };
  public type RevokeError = {
    #NotFoundOrExpired;
    #CapacityFull;
    #Unauthorized;
    #Expired;
  };
  public type Schedule = { #At : Nat64; #In : Nat64 };
  public type Stats = {
    number_of_entries : Nat64;
    first_in_memory_index : Nat64;
    total_bytes_used : Nat64;
    current_time : Nat64;
    scheduled_actions : Nat64;
    config : Config;
    max_entries_allowed : Nat64;
    active_actions : Nat64;
    max_view_range : Nat64;
  };
  public type SubmitError = {
    #ActivatesTooSoon;
    #InvalidChecksum;
    #InvalidRequires : Nat64;
    #CapacityFull;
    #InvalidExpires;
    #Unauthorized;
  };
  public type Self = actor {
    configure : shared Config -> async ();
    execute : shared ExecuteArgs -> async { #Ok : Result; #Err : ExecuteError };
    records : shared query (Nat64, Nat64) -> async [Record];
    revoke : shared RevokeArgs -> async { #Ok; #Err : RevokeError };
    stats : shared query () -> async Stats;
    submit : shared Action -> async { #Ok : Nat64; #Err : SubmitError };
  }
}
