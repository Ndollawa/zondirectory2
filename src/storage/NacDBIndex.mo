import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Iter "mo:base/Iter";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Cycles "mo:base/ExperimentalCycles";

import StableBuffer "mo:stable-buffer/StableBuffer";
import Buffer "mo:stable-buffer/StableBuffer";

import Nac "mo:nacdb/NacDB";
import MyCycles "mo:nacdb/Cycles";
import Partition "./NacDBPartition";
import CanDBConfig "../backend/libs/configs/canDB.config";

shared ({ caller = initialOwner }) actor class NacDBIndex() = this {
    stable var owners = [initialOwner];

    func checkCaller(caller : Principal) {
        if (Array.find(owners, func(e : Principal) : Bool { e == caller }) == null) {
            Debug.trap("NacDBIndex: not allowed");
        };
    };

    public shared ({ caller = caller }) func setOwners(_owners : [Principal]) : async () {
        checkCaller(caller);

        owners := _owners;
    };

    public query func getOwners() : async [Principal] { owners };

    func ownersOrSelf() : [Principal] {
        let buf = Buffer.fromArray<Principal>(owners);
        Buffer.add(buf, Principal.fromActor(this));
        Buffer.toArray(buf);
    };

    stable var dbIndex : Nac.DBIndex = Nac.createDBIndex(CanDBConfig.dbOptions);

    stable var initialized = false;

    public shared ({ caller }) func init(_owners : [Principal]) : async () {
        checkCaller(caller);
        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        if (initialized) {
            Debug.trap("already initialized");
        };

        owners := _owners;
        MyCycles.addPart(CanDBConfig.dbOptions.partitionCycles);
        StableBuffer.add(dbIndex.canisters, await Partition.Partition(ownersOrSelf()));
        initialized := true;
    };

    public query func getCanisters() : async [Principal] {
        // ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        let iter = Iter.map(
            Nac.getCanisters(dbIndex).vals(),
            func(x : Nac.PartitionCanister) : Principal {
                Principal.fromActor(x);
            },
        );
        Iter.toArray(iter);
    };

    public shared ({ caller }) func createPartition() : async Principal {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        MyCycles.addPart(CanDBConfig.dbOptions.partitionCycles);
        Principal.fromActor(await Partition.Partition(ownersOrSelf()));
    };

    public shared ({ caller }) func createPartitionImpl() : async Principal {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        await* Nac.createPartitionImpl(this, dbIndex);
    };

    public shared ({ caller }) func createSubDB(guid : [Nat8], { userData : Text }) : async {
        inner : (Principal, Nac.InnerSubDBKey);
        outer : (Principal, Nac.OuterSubDBKey);
    } {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        let r = await* Nac.createSubDB(Blob.fromArray(guid), { index = this; dbIndex; dbOptions = CanDBConfig.dbOptions; userData });
        {
            inner = (Principal.fromActor(r.inner.0), r.inner.1);
            outer = (Principal.fromActor(r.outer.0), r.outer.1);
        };
    };

    // Management methods //

    type CanisterId = Principal;

    type Management = actor {
        // create_canister : ({ settings : ?CanisterSettings }) -> async ({
        //   canister_id : CanisterId;
        // });
        install_code : ({
            mode : { #install; #reinstall; #upgrade };
            canister_id : CanisterId;
            wasm_module : Blob;
            arg : Blob;
        }) -> async ();
        // update_settings : ({ canister_id : CanisterId; settings : CanisterSettings }) -> async (); // TODO
        deposit_cycles : ({ canister_id : Principal }) -> async ();
    };

    public shared ({ caller }) func upgradeCanistersInRange(wasm : Blob, inclusiveBottom : Nat, exclusiveTop : Nat) : async () {
        checkCaller(caller);

        let canisters = Nac.getCanisters(dbIndex);
        let ic : Management = actor ("aaaaa-aa");
        for (i in Iter.range(inclusiveBottom, exclusiveTop -1)) {
            await ic.install_code({
                arg = to_candid ([]);
                wasm_module = wasm;
                mode = #upgrade;
                canister_id = Principal.fromActor(canisters[i]);
            });
        };
    };

    public shared ({ caller }) func deleteSubDB(guid : [Nat8], { outerCanister : Principal; outerKey : Nac.OuterSubDBKey }) : async () {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        let outer : Nac.OuterCanister = actor (Principal.toText(outerCanister));
        await* Nac.deleteSubDB(Blob.fromArray(guid), { dbOptions = CanDBConfig.dbOptions; dbIndex; outerCanister = outer; outerKey });
    };

    public shared ({ caller }) func delete(guid : [Nat8], { outerCanister : Principal; outerKey : Nac.OuterSubDBKey; sk : Nac.SK }) : async () {
        checkCaller(caller);

        let outer : Nac.OuterCanister = actor (Principal.toText(outerCanister));
        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        await* Nac.delete(Blob.fromArray(guid), { dbIndex; outerCanister = outer; outerKey; sk });
    };

    public shared ({ caller }) func insert(
        guid : [Nat8],
        {
            outerCanister : Principal;
            outerKey : Nac.OuterSubDBKey;
            sk : Nac.SK;
            value : Nac.AttributeValue;
        },
    ) : async Result.Result<{ inner : (Principal, Nac.InnerSubDBKey); outer : (Principal, Nac.OuterSubDBKey) }, Text> {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        let result = await* Nac.insert(
            Blob.fromArray(guid),
            {
                indexCanister = Principal.fromActor(this);
                outerCanister = outerCanister;
                dbIndex;
                outerKey;
                sk;
                value;
            },
        );
        switch (result) {
            case (#ok { inner; outer }) {
                let innerx : Principal = Principal.fromActor(inner.0);
                let outerx : Principal = Principal.fromActor(outer.0);
                #ok { inner = (innerx, inner.1); outer = (outerx, outer.1) };
            };
            case (#err err) {
                #err err;
            };
        };
    };
};
