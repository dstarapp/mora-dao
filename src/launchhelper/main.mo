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

shared({caller = initowner}) actor class LaunchHelper()  = this {
  private stable var owner: Principal = initowner;
  private stable var wasm: Blob = Blob.fromArray([]);
  private stable var wasmHash: Blob = Blob.fromArray([]);
  private stable var launchTrail : Principal = Principal.fromText("aaaaa-aa");
  private stable var userRouter : Principal = Principal.fromText("aaaaa-aa");
  private stable var cyclesToken: Nat = 200_000_000_000; // 0.2 trillion cycles for each token canister
  private stable var argeePayee: Blob = Blob.fromArray([]);

  type Canister = {
    id: Principal;
    owner: Principal;
    launchTrail: Principal;
    initArgs: Blob;
    moduleHash: Blob;
  };
  private stable var canisters: Queue.Queue<Canister> = Queue.empty();

  type Version = {
    wasm: Blob;
    wasmHash: Blob;
  };
  private stable var versions: Queue.Queue<Version> = Queue.empty();

  type CreatePlanetSetting = {
    owner: Principal;
    name: Text;
    avatar: Text;
    desc: Text;
    payee: Blob;
  };

  public shared({caller}) func setOwner(p: Principal) {
    assert(Principal.equal(caller, owner));
    owner := owner;
  };

  public shared({caller}) func setWasm(blob : Blob) {
    assert(Principal.equal(caller, owner));
    if (not checkWasm()) {
      ignore Queue.pushBack(versions, {wasm = wasm; wasmHash = wasmHash});
    };
    wasm := blob;
    wasmHash := Sha2.fromBlob(#sha256, wasm);
  };

  public shared({caller}) func setLaunch(p: Principal) {
    assert(Principal.equal(caller, owner));
    launchTrail := p;
  };

  public shared({caller}) func setUserRouter(p: Principal) {
    assert(Principal.equal(caller, owner));
    userRouter := p;
  };

  public shared({caller}) func setAgreePayee(p: Blob) {
    assert(Principal.equal(caller, owner));
    argeePayee := p;
  };

  public query func queryWasmHash(): async Text {
    return Hex.encode(Blob.toArray(wasmHash));
  };

  public query({caller}) func queryCanisters(): async [Canister] {
    assert(Principal.equal(caller, owner));
    var items = Buffer.Buffer<Canister>(Queue.size(canisters));
    for (item in Queue.toIter(canisters)) {
      items.add(item);
    };
    return items.toArray();
  };

  public shared({caller}) func createPlanet(setting: CreatePlanetSetting): async ?Principal {

    assert(checkWasm());

    // verify caller is user canister
    let userActor : actor {
      verify_canister: shared query (id: Principal) -> async Bool;
    } = actor (Principal.toText(userRouter));
    let isVerify = await userActor.verify_canister(caller);
    assert(isVerify);

    // create canister
    let res = await createCanister();
    switch(res){
      case(?canister_id){
        let arg = to_candid(setting.owner, setting.name, setting.avatar, setting.desc, setting.payee, argeePayee);
        Debug.print("setting: " # debug_show(setting) # " " # debug_show(setting.owner, setting.name, setting.avatar, setting.desc, setting.payee, argeePayee));
        let isinstall = await installCanisterWasm(canister_id, #install, arg);
        if (not isinstall) {
          return null;
        };

        ignore Queue.pushBack(canisters, {
          id = canister_id;
          owner = setting.owner;
          launchTrail = launchTrail;
          initArgs = arg;
          moduleHash = wasmHash;
        })
      };
      case(_){}
    };
    return res;
  };

  private func checkWasm(): Bool {
    return wasm.size() > 0;
  };

  private func createCanister(): async ?Principal {
    let launchActor : Launchtrail.Self = actor(Principal.toText(launchTrail));
    let now = Time.now();
    let expire = now + 3600 * 1_000_000_000_000;

    let params: IcManager.CreateCanisterParams = {
      settings = ?{
        controllers = ?[launchTrail];
        compute_allocation = null;
        memory_allocation = null;
        freezing_threshold = null;
      };
    };

    let args = to_candid((params));
    let sha = Hex.encode(Blob.toArray(Sha2.fromBlob(#sha256, args)));
    Debug.print("Sha256: " # sha);

    let action: Launchtrail.Action = {
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

    switch(ret) {
      case(#Ok(index)){
        let res = await launchActor.execute({
          args = Blob.toArray(args);
          index = index;
        });
        Debug.print("Execute: " # debug_show(res));
        switch(res){
          case(#Ok(#Ok(nat))){
            Debug.print(debug_show(nat));
            let data: ?IcManager.CanisterId = from_candid(Blob.fromArray(nat));
            Debug.print(debug_show(data));
            switch(data) {
              case(?ok){
                return ?ok.canister_id;
              };
              case(_){
                return null;
              };
            }
          };
          case(_){
            return null;
          };
        };
      };
      case(#Err(err)){
        Debug.print("Submit: " # debug_show(err));
      };
    };
    return null;
  };

  private func installCanisterWasm(canister_id: Principal, mode: IcManager.InstallMode, initArgs: Blob.Blob): async Bool {
    let launchActor : Launchtrail.Self = actor(Principal.toText(launchTrail));
    let now = Time.now();
    let expire = now + 3600 * 1_000_000_000_000;

    let params: IcManager.InstallCodeParams = {
      mode = mode;
      canister_id = canister_id;
      wasm_module = wasm;
      arg = initArgs;
    };
    let args = to_candid((params));
    let sha = Hex.encode(Blob.toArray(Sha2.fromBlob(#sha256, args)));

    Debug.print("Sha256: " # sha);

    let action: Launchtrail.Action = {
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
    Debug.print("submit: " # debug_show(ret));

    switch(ret) {
      case(#Ok(index)){
        let res = await launchActor.execute({
          args = Blob.toArray(args);
          index = index;
        });
        Debug.print("Execute: " # debug_show(res));
        switch(res){
          case(#Ok(#Ok(nat))){
            // Debug.print(debug_show(nat));
            // let data: ?() = from_candid(Blob.fromArray(nat));
            return true;
          };
          case(_){
            return false;
          };
        };
      };
      case(#Err(err)){
        Debug.print("Submit: " # debug_show(err));
      };
    };
    return false;
  };
};
