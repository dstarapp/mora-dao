import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Hex "mo:encoding/Hex";
import IcManager "./icmanager";
import Launchtrail "./launchtrail";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Queue "mo:mutable-queue/Queue";
import Sha2 "mo:sha2";
import Text "mo:base/Text";
import Time "mo:base/Time";
import AccountIdentifier "mo:principal/blob/AccountIdentifier";
import Invitecode "./invitecode";
import Prelude "mo:base/Prelude";

shared ({ caller = initowner }) actor class MoraDAO() = this {
  private stable var owner : Principal = initowner;
  private stable var wasm : Blob = Blob.fromArray([]);
  private stable var wasmHash : Blob = Blob.fromArray([]);
  private stable var launchTrail : Principal = Principal.fromText("aaaaa-aa");
  private stable var userRouter : Principal = Principal.fromText("aaaaa-aa");
  private stable var inviter : Principal = Principal.fromText("aaaaa-aa");
  // private stable
  private stable var cyclesToken : Nat = 200_000_000_000;
  // 0.2 trillion cycles for each token canister
  private stable var argeePayee : Blob = Blob.fromArray([]);

  type Canister = {
    id : Principal;
    launchTrail : Principal;
    initArgs : Blob;
    var owner : Principal;
    var moduleHash : Blob;
  };
  private stable var canisters : Queue.Queue<Canister> = Queue.empty();

  type Version = {
    wasm : Blob;
    wasmHash : Blob;
    created : Int;
  };
  private stable var versions : Queue.Queue<Version> = Queue.empty();

  type CreatePlanetSetting = {
    owner : Principal;
    name : Text;
    avatar : Text;
    desc : Text;
    code : Text; // invite code
  };

  type CreatePlanetResp = {
    #Ok : { id : Principal };
    #Err : Text;
  };

  public shared ({ caller }) func setOwner(p : Principal) {
    assert (Principal.equal(caller, owner));
    owner := owner;
  };

  public shared ({ caller }) func setWasm(blob : Blob) {
    assert (Principal.equal(caller, owner));
    if (not checkWasm()) {
      ignore Queue.pushBack(
        versions,
        { wasm = wasm; wasmHash = wasmHash; created = Time.now() },
      );
    };
    wasm := blob;
    wasmHash := Sha2.fromBlob(#sha256, wasm);
  };

  public shared ({ caller }) func setLaunch(p : Principal) {
    assert (Principal.equal(caller, owner));
    launchTrail := p;
  };

  public shared ({ caller }) func setUserRouter(p : Principal) {
    assert (Principal.equal(caller, owner));
    userRouter := p;
  };

  public shared ({ caller }) func setInviter(p : Principal) {
    assert (Principal.equal(caller, owner));
    inviter := p;
  };

  public shared ({ caller }) func setAgreePayee(p : Blob) {
    assert (Principal.equal(caller, owner));
    argeePayee := p;
  };

  public query func queryWasmHash() : async Text {
    return Hex.encode(Blob.toArray(wasmHash));
  };

  public query func queryAgreePayee() : async Text {
    AccountIdentifier.toText(selfAgreePayee());
  };

  public query func canisterAccount() : async Text {
    AccountIdentifier.toText(accountId(null));
  };

  type CanisterInfo = {
    id : Principal;
    launchTrail : Principal;
    initArgs : Blob;
    owner : Principal;
    moduleHash : Blob;
  };
  public query ({ caller }) func queryCanisters() : async [CanisterInfo] {
    // assert(Principal.equal(caller, owner));
    var items = Buffer.Buffer<CanisterInfo>(Queue.size(canisters));
    for (item in Queue.toIter(canisters)) {
      items.add({
        id = item.id;
        launchTrail = item.launchTrail;
        initArgs = item.initArgs;
        owner = item.owner;
        moduleHash = item.moduleHash;
      });
    };
    return Buffer.toArray(items);
  };

  public query ({ caller }) func queryCanisterIds() : async [Text] {
    // assert(Principal.equal(caller, owner));
    var items = Buffer.Buffer<Text>(Queue.size(canisters));
    for (item in Queue.toIter(canisters)) {
      items.add(Principal.toText(item.id));
    };
    return Buffer.toArray(items);
  };

  public query ({ caller }) func queryCanisterPids() : async [Principal] {
    // assert(Principal.equal(caller, owner));
    var items = Buffer.Buffer<Principal>(Queue.size(canisters));
    for (item in Queue.toIter(canisters)) {
      items.add(item.id);
    };
    return Buffer.toArray(items);
  };

  public shared ({ caller }) func createPlanet(setting : CreatePlanetSetting) : async CreatePlanetResp {

    assert (checkWasm());

    // verify caller is user canister
    let userActor : actor {
      verify_canister : shared query (id : Principal) -> async Bool;
    } = actor (Principal.toText(userRouter));
    let isVerify = await userActor.verify_canister(caller);
    assert (isVerify);

    // verify valid invite code
    let inviteActor : Invitecode.InviteCodeActor = actor (Principal.toText(inviter));

    let isvalid = await inviteActor.verify_code(setting.code, setting.owner);
    if (not isvalid) {
      return #Err("Error: invite code is invalid");
    };

    // create canister
    let res = await createCanister();
    switch (res) {
      case (?canister_id) {
        let agree = selfAgreePayee();
        let arg = to_candid (
          setting.owner,
          setting.name,
          setting.avatar,
          setting.desc,
          agree,
        );
        Debug.print("setting: " # debug_show (setting) # " " # debug_show (setting.owner, setting.name, setting.avatar, setting.desc, agree));
        let isinstall = await installCanisterWasm(canister_id, #install, arg);
        if (not isinstall) {
          return #Err("Error: can not install planet canister");
        };

        ignore Queue.pushBack(
          canisters,
          {
            id = canister_id;
            launchTrail = launchTrail;
            initArgs = arg;
            var owner = setting.owner;
            var moduleHash = wasmHash;
          },
        );
        return #Ok({ id = canister_id });
      };
      case (_) {
        return #Err("Error: can not create planet canister, please check the cycles.");
      };
    };
  };

  public shared ({ caller }) func upgradePlanet(cid : Principal) : async Bool {
    assert (caller == owner);
    switch (findCanister(cid)) {
      case (?canister) {
        if (canister.moduleHash == wasmHash) {
          return true;
        };
        let isinstall = await installCanisterWasm(
          canister.id,
          #upgrade,
          canister.initArgs,
        );
        if (isinstall) {
          canister.moduleHash := wasmHash;
        };
        return isinstall;
      };
      case (_) {};
    };
    false;
  };

  private func checkWasm() : Bool {
    return wasm.size() > 0;
  };

  private func createCanister() : async ?Principal {
    let launchActor : Launchtrail.Self = actor (Principal.toText(launchTrail));
    let now = Time.now();
    let expire = now + 3600 * 1_000_000_000_000;

    let params : IcManager.CreateCanisterParams = {
      settings = ?{
        controllers = ?[launchTrail];
        compute_allocation = null;
        memory_allocation = null;
        freezing_threshold = null;
      };
    };

    let args = to_candid ((params));
    let sha = Hex.encode(Blob.toArray(Sha2.fromBlob(#sha256, args)));
    Debug.print("Sha256: " # sha);

    let action : Launchtrail.Action = {
      url = "";
      method = "create_canister";
      sha256 = ?sha;
      activates = #At(Nat64.fromIntWrap(now));
      expires = #At(Nat64.fromIntWrap(expire));
      canister = Principal.fromText("aaaaa-aa");
      requires = [];
      executors = null;
      revokers = null;
      payment = cyclesToken;
    };
    let ret = await launchActor.submit(action);

    switch (ret) {
      case (#Ok(index)) {
        let res = await launchActor.execute({
          args = Blob.toArray(args);
          index = index;
        });
        Debug.print("Execute: " # debug_show (res));
        switch (res) {
          case (#Ok(#Ok(nat))) {
            Debug.print(debug_show (nat));
            let data : ?IcManager.CanisterId = from_candid (Blob.fromArray(nat));
            Debug.print(debug_show (data));
            switch (data) {
              case (?ok) {
                return ?ok.canister_id;
              };
              case (_) {
                return null;
              };
            };
          };
          case (_) {
            return null;
          };
        };
      };
      case (#Err(err)) {
        Debug.print("Submit: " # debug_show (err));
      };
    };
    return null;
  };

  private func installCanisterWasm(
    canister_id : Principal,
    mode : IcManager.InstallMode,
    initArgs : Blob.Blob,
  ) : async Bool {
    let launchActor : Launchtrail.Self = actor (Principal.toText(launchTrail));
    let now = Time.now();
    let expire = now + 3600 * 1_000_000_000_000;

    let params : IcManager.InstallCodeParams = {
      mode = mode;
      canister_id = canister_id;
      wasm_module = wasm;
      arg = initArgs;
    };
    let args = to_candid ((params));
    let sha = Hex.encode(Blob.toArray(Sha2.fromBlob(#sha256, args)));

    Debug.print("Sha256: " # sha);

    let action : Launchtrail.Action = {
      url = "";
      method = "install_code";
      sha256 = ?sha;
      activates = #At(Nat64.fromIntWrap(now));
      expires = #At(Nat64.fromIntWrap(expire));
      canister = Principal.fromText("aaaaa-aa");
      requires = [];
      executors = null;
      revokers = null;
      payment = 0;
    };
    let ret = await launchActor.submit(action);
    Debug.print("submit: " # debug_show (ret));

    switch (ret) {
      case (#Ok(index)) {
        let res = await launchActor.execute({
          args = Blob.toArray(args);
          index = index;
        });
        Debug.print("Execute: " # debug_show (res));
        switch (res) {
          case (#Ok(#Ok(nat))) {
            // Debug.print(debug_show(nat));
            // let data: ?() = from_candid(Blob.fromArray(nat));
            return true;
          };
          case (_) {
            return false;
          };
        };
      };
      case (#Err(err)) {
        Debug.print("Submit: " # debug_show (err));
      };
    };
    return false;
  };

  private func findCanister(cid : Principal) : ?Canister {
    Queue.find(canisters, eqPrincialId(cid));
  };

  private func eqPrincialId(aid : Principal) : { id : Principal } -> Bool {
    func(x : { id : Principal }) : Bool { x.id == aid };
  };

  private func accountId(sa : ?[Nat8]) : Blob {
    AccountIdentifier.fromPrincipal(Principal.fromActor(this), sa);
  };

  private func selfAgreePayee() : Blob {
    if (argeePayee.size() == 0) {
      return accountId(null);
    };
    return argeePayee;
  };
};
