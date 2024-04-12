import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Hex "mo:encoding/Hex";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Queue "mo:mutable-queue/Queue";
import Sha2 "mo:sha2";
import Text "mo:base/Text";
import Time "mo:base/Time";
import AccountIdentifier "mo:principal/blob/AccountIdentifier";
import Cycles "mo:base/ExperimentalCycles";
import Option "mo:base/Option";
import Bool "mo:base/Bool";
import Iter "mo:base/Iter";
import Canister "mo:matchers/Canister";
import Invitecode "./invitecode";
import IcManager "./icmanager";
import Launchtrail "./launchtrail";
import Subnet "./subnet";

shared ({ caller = initowner }) actor class MoraDAO() = this {
  private stable var owner : Principal = initowner;
  private stable var wasm : Blob = Blob.fromArray([]);
  private stable var wasmHash : Blob = Blob.fromArray([]);
  private stable var userRouter : Principal = Principal.fromText("aaaaa-aa");
  private stable var inviter : Principal = Principal.fromText("aaaaa-aa");
  // private stable
  // 0.2 trillion cycles for each token canister
  private stable var argeePayee : Blob = Blob.fromArray([]);
  private stable var launchTrail : Any = null; // deprecated
  private stable var cyclesToken : Any = null; // deprecated

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

  private stable var trailWasm : Blob = Blob.fromArray([]);
  private stable var trailWasmHash : Blob = Blob.fromArray([]);
  private stable var alltrails : Queue.Queue<Principal> = Queue.empty();

  private stable var trailMaxCount : Nat = 800;
  private stable var trailCycles : Nat = 200_000_000_000_000;
  private stable var planetCycles : Nat = 200_000_000_000;
  private stable var updaters : Queue.Queue<Principal> = Queue.empty();

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

  public type QueryCanisterIdsResp = {
    page : Nat;
    total : Int;
    hasmore : Bool;
    data : [Principal];
  };

  public type QueryCommonReq = {
    page : Nat;
    size : Nat;
  };

  system func preupgrade() {};
  system func postupgrade() {};

  public shared ({ caller }) func setOwner(p : Principal) {
    assert (Principal.equal(caller, owner));
    owner := p;
  };

  public shared ({ caller }) func addUpdater(p : Principal) : async Bool {
    assert (caller == owner);
    if (verifyUpdater(p)) {
      return true;
    };
    ignore Queue.pushBack(updaters, p);
    return true;
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

  public shared ({ caller }) func setTrailWasm(blob : Blob) {
    assert (Principal.equal(caller, owner));
    trailWasm := blob;
    trailWasmHash := Sha2.fromBlob(#sha256, trailWasm);
  };

  public shared ({ caller }) func initTrail(num : Int) : async Int {
    assert (caller == owner);
    var count : Int = 0;
    for (i in Iter.range(1, num)) {
      if (await addSubnetTrailCanister()) {
        count := count + 1;
      };
    };
    return count;
  };

  public shared ({ caller }) func test_init_subnet_trail() : async ?Principal {
    assert (caller == owner);
    let ret = await Subnet.cross_create_canister(Principal.fromActor(this), 2_000_000);
    switch (ret) {
      case (#ok(canister_id)) {
        ignore await installTrailCanister(canister_id);
        return ?canister_id;
      };
      case (_) {
        return null;
      };
    };
  };

  public shared ({ caller }) func test_install_trail(pid : Principal) : async Bool {
    assert (caller == owner);
    let ret = await installTrailCanister(pid);
    return ret;
  };

  public shared ({ caller }) func test_deposit(pid : Principal) : async Bool {
    assert (caller == owner);
    let ret = await depositTrailCycle(pid);
    return ret;
  };

  public shared ({ caller }) func test_add_trail(pid : Principal) : async Bool {
    assert (caller == owner);
    ignore Queue.pushBack(alltrails, pid);
    return true;
  };

  public shared ({ caller }) func test_status(pid : Principal) : async IcManager.CanisterStatus {
    assert (caller == owner);
    let ic_manager : IcManager.ICActor = actor ("aaaaa-aa");
    return await ic_manager.canister_status({
      canister_id = pid;
    });
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

  public query func verifyPlanet(pid : Principal) : async Bool {
    switch (findCanister(pid)) {
      case (?canister) {
        true;
      };
      case (_) {
        false;
      };
    };
  };

  public query func queryWasmHash() : async Text {
    return Hex.encode(Blob.toArray(wasmHash));
  };

  public query func queryTrailWasmHash() : async Text {
    return Hex.encode(Blob.toArray(trailWasmHash));
  };

  public query func queryAgreePayee() : async Text {
    AccountIdentifier.toText(selfAgreePayee());
  };

  public query func canisterAccount() : async Text {
    AccountIdentifier.toText(accountId(null));
  };

  //return cycles balance
  public query func wallet_balance() : async Nat {
    return Cycles.balance();
  };

  //cycles deposit
  public func wallet_receive() : async { accepted : Nat64 } {
    let available = Cycles.available();
    let accepted = Cycles.accept<system>(Nat.min(available, 10_000_000));
    { accepted = Nat64.fromNat(accepted) };
  };

  type CanisterInfo = {
    id : Principal;
    launchTrail : Principal;
    initArgs : Blob;
    owner : Principal;
    moduleHash : Blob;
  };
  public query func queryCanisters() : async [CanisterInfo] {
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

  public query ({ caller }) func queryCanisterCount() : async Int {
    assert (Principal.equal(caller, owner));
    return Queue.size(canisters);
  };

  public query func queryCanisterIds() : async [Text] {
    // assert(Principal.equal(caller, owner));
    var items = Buffer.Buffer<Text>(Queue.size(canisters));
    for (item in Queue.toIter(canisters)) {
      items.add(Principal.toText(item.id));
    };
    return Buffer.toArray(items);
  };

  public query func queryCanisterPids() : async [Principal] {
    // assert(Principal.equal(caller, owner));
    var items = Buffer.Buffer<Principal>(Queue.size(canisters));
    for (item in Queue.toIter(canisters)) {
      items.add(item.id);
    };
    return Buffer.toArray(items);
  };

  public query ({ caller }) func queryCanisterIdList(req : QueryCommonReq) : async QueryCanisterIdsResp {
    let res = limitCanisterIds(caller, req);

    return {
      page = req.page;
      total = res.0;
      hasmore = res.1;
      data = res.2;
    };
  };

  public query func queryCanisterInfo(cid : Principal) : async ?CanisterInfo {
    // assert(Principal.equal(caller, owner));
    switch (findCanister(cid)) {
      case (?canister) {
        ?{
          id = canister.id;
          launchTrail = canister.launchTrail;
          initArgs = canister.initArgs;
          owner = canister.owner;
          moduleHash = canister.moduleHash;
        };
      };
      case (_) {
        null;
      };
    };
  };

  public query func queryTrailPids() : async [Principal] {
    // assert (Principal.equal(caller, owner));
    return Queue.toArray(alltrails);
  };

  public shared ({ caller }) func createPlanet(setting : CreatePlanetSetting) : async CreatePlanetResp {

    assert (checkWasm());

    // verify caller is user canister
    let userActor : actor {
      verify_canister : shared query (id : Principal) -> async Bool;
    } = actor (Principal.toText(userRouter));
    let isVerify = await userActor.verify_canister(caller);
    assert (isVerify);

    // get launchtrail ID
    let trail = await getTrail();
    if (Option.isNull(trail)) {
      return #Err("Error: can not get launchtrail, please contrat adminer");
    };
    let trail_id = Option.unwrap(trail);

    // verify valid invite code
    let inviteActor : Invitecode.InviteCodeActor = actor (Principal.toText(inviter));

    let isvalid = await inviteActor.verify_code(setting.code, setting.owner);
    if (not isvalid) {
      return #Err("Error: invite code is invalid");
    };

    // create canister
    let res = await createPlanetCanister(trail_id);
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
        let isinstall = await installPlanetCanisterWasm(trail_id, canister_id, #install, arg);
        if (not isinstall) {
          return #Err("Error: can not install planet canister");
        };

        ignore Queue.pushBack(
          canisters,
          {
            id = canister_id;
            launchTrail = trail_id;
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
    assert (caller == owner or verifyUpdater(caller));
    switch (findCanister(cid)) {
      case (?canister) {
        if (canister.moduleHash == wasmHash) {
          return true;
        };
        let isinstall = await installPlanetCanisterWasm(
          canister.launchTrail,
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

  private func getTrail() : async ?Principal {
    let idx = Queue.size(canisters);
    let max = Queue.size(alltrails);
    if (idx >= trailMaxCount * max) {
      let ret = await addSubnetTrailCanister();
      if (not ret) {
        return null;
      };
    };
    var index = idx / trailMaxCount;
    for (item in Queue.toIter(alltrails)) {
      if (index == 0) {
        return ?item;
      };
      index := index - 1;
    };
    return null;
  };

  private func addTrailCanister() : async Bool {
    let canister = await createTrailCanister();
    switch (canister) {
      case (?canister_id) {
        let ret = await installTrailCanister(canister_id);
        ignore Queue.pushBack(alltrails, canister_id);
        return ret;
      };
      case (_) {
        return false;
      };
    };
  };

  private func addSubnetTrailCanister() : async Bool {
    let ret = await Subnet.cross_create_canister(Principal.fromActor(this), 2_000_000);
    switch (ret) {
      case (#ok(canister_id)) {
        var ret = await installTrailCanister(canister_id);
        if ret {
          ret := await depositTrailCycle(canister_id);
        };
        ignore Queue.pushBack(alltrails, canister_id);
        return ret;
      };
      case (_) {
        return false;
      };
    };
  };

  private func depositTrailCycle(trail_id : Principal) : async Bool {
    let launchActor : Launchtrail.Self = actor (Principal.toText(trail_id));
    Cycles.add<system>(trailCycles);
    await launchActor.wallet_receive();
    true;
  };

  private func createTrailCanister() : async ?Principal {
    let params : IcManager.CreateCanisterParams = {
      settings = ?{
        controllers = ?[Principal.fromActor(this)];
        compute_allocation = null;
        memory_allocation = null;
        freezing_threshold = null;
      };
    };

    Cycles.add<system>(trailCycles);
    let ic_manager : IcManager.ICActor = actor ("aaaaa-aa");
    let res = await ic_manager.create_canister(params);

    ?res.canister_id;
  };

  private func installTrailCanister(canister_id : Principal) : async Bool {
    let ic_manager : IcManager.ICActor = actor ("aaaaa-aa");
    let config : Launchtrail.InitialConfig = {
      bucket_size = 10000;
      max_buckets = 1000;
      config = {
        min_schedule = 0;
        revokers = [Principal.fromActor(this)];
        submitters = [Principal.fromActor(this)];
      };
    };
    let initArgs = to_candid (config);
    let params : IcManager.InstallCodeParams = {
      mode = #install;
      canister_id = canister_id;
      wasm_module = trailWasm;
      arg = initArgs;
    };
    let _res = await ic_manager.install_code(params);
    return true;
  };

  private func createPlanetCanister(trail_id : Principal) : async ?Principal {
    let launchActor : Launchtrail.Self = actor (Principal.toText(trail_id));
    let now = Time.now();
    let expire = now + 3600 * 1_000_000_000;

    let params : IcManager.CreateCanisterParams = {
      settings = ?{
        controllers = ?[trail_id];
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
      activates = #In(0);
      expires = #At(Nat64.fromIntWrap(expire));
      canister = Principal.fromText("aaaaa-aa");
      requires = [];
      executors = null;
      revokers = null;
      payment = planetCycles;
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

  private func installPlanetCanisterWasm(
    trail_id : Principal,
    canister_id : Principal,
    mode : IcManager.InstallMode,
    initArgs : Blob.Blob,
  ) : async Bool {
    let launchActor : Launchtrail.Self = actor (Principal.toText(trail_id));
    let now = Time.now();
    let expire = now + 3600 * 1_000_000_000;

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
      activates = #In(0);
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

  private func limitCanisterIds(_caller : Principal, req : QueryCommonReq) : (Int, Bool, [Principal]) {
    var data = Buffer.Buffer<Principal>(0);
    let pagesize = checkPageSize(req.page, req.size);
    let size = pagesize.1;
    var start = (pagesize.0 - 1) * size;
    var hasmore = false;
    var total = 0;

    var iter : Iter.Iter<Canister> = Queue.toIter(canisters);
    Iter.iterate(
      iter,
      func(x : Canister, _idx : Int) {
        if (total >= start and total < start + size) {
          data.add(x.id);
        };
        total := total + 1;
      },
    );
    if (total >= start + size) {
      hasmore := true;
    };
    return (total, hasmore, Buffer.toArray(data));
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

  private func checkPageSize(p : Nat, s : Nat) : (Int, Int) {
    var page : Int = p;
    if (page < 1) {
      page := 1;
    };
    var size : Int = s;
    if (size > 2000) {
      size := 2000;
      // limit max page size
    } else if (size < 1) {
      size := 100;
    };
    return (page, size);
  };

  private func findUpdater(p : Principal) : ?Principal {
    Queue.find(updaters, func(x : Principal) : Bool { x == p });
  };

  private func verifyUpdater(p : Principal) : Bool {
    switch (findUpdater(p)) {
      case (?id) { true };
      case (_) { false };
    };
  };
};
