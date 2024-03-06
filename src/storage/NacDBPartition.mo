import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Iter "mo:base/Iter";
import I "mo:base/Iter";
import Principal "mo:base/Principal";
import Bool "mo:base/Bool";
import Nat "mo:base/Nat";

import Buffer "mo:stable-buffer/StableBuffer"; // TODO: Here and in other places, use just `Buffer`.
import BTree "mo:stableheapbtreemap/BTree";
import Nac "mo:nacdb/NacDB";
import MyCycles "mo:nacdb/Cycles";
import CanDBConfig "../backend/libs/configs/canDB.config";

shared ({ caller }) actor class Partition(
    initialOwners : [Principal]
) = this {
    stable var owners = initialOwners;

    func checkCaller(caller : Principal) {
        if (caller == Principal.fromActor(this)) {
            return;
        };
        if (Array.find(owners, func(e : Principal) : Bool { e == caller }) == null) {
            Debug.trap("NacDBPartition: not allowed from " # Principal.toText(caller));
        };
    };

    public shared ({ caller = caller }) func setOwners(_owners : [Principal]) : async () {
        checkCaller(caller);

        owners := _owners;
    };

    public query func getOwners() : async [Principal] { owners };

    // func ownersOrSelf(): [Principal] {
    //     let buf = Buffer.fromArray<Principal>(owners);
    //     Buffer.add(buf, Principal.fromActor(this));
    //     Buffer.toArray(buf);
    // };

    stable let index : Nac.IndexCanister = actor (Principal.toText(caller));

    stable let superDB = Nac.createSuperDB(CanDBConfig.dbOptions);

    // Mandatory methods //

    public shared ({ caller }) func rawInsertSubDB(map : [(Nac.SK, Nac.AttributeValue)], inner : ?Nac.InnerSubDBKey, userData : Text) : async {
        inner : Nac.InnerSubDBKey;
    } {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.rawInsertSubDB(superDB, map, inner, userData);
    };

    public shared ({ caller }) func rawInsertSubDBAndSetOuter(
        map : [(Nac.SK, Nac.AttributeValue)],
        keys : ?{
            inner : Nac.InnerSubDBKey;
            outer : Nac.OuterSubDBKey;
        },
        userData : Text,
    ) : async { inner : Nac.InnerSubDBKey; outer : Nac.OuterSubDBKey } {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.rawInsertSubDBAndSetOuter(superDB, this, map, keys, userData);
    };

    public shared func isOverflowed({}) : async Bool {
        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.isOverflowed({ dbOptions = CanDBConfig.dbOptions; superDB });
    };

    // Some data access methods //

    public query func superDBSize() : async Nat {
        // ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.superDBSize(superDB);
    };

    public shared ({ caller }) func deleteSubDBInner({
        innerKey : Nac.InnerSubDBKey;
    }) : async () {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        await* Nac.deleteSubDBInner({ superDB; innerKey });
    };

    public shared ({ caller }) func putLocation(outerKey : Nac.OuterSubDBKey, innerCanister : Principal, newInnerSubDBKey : Nac.InnerSubDBKey) : async () {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        let inner : Nac.InnerCanister = actor (Principal.toText(innerCanister));
        Nac.putLocation(superDB, outerKey, inner, newInnerSubDBKey);
    };

    public shared ({ caller }) func createOuter(part : Principal, outerKey : Nac.OuterSubDBKey, innerKey : Nac.InnerSubDBKey) : async {
        inner : (Principal, Nac.InnerSubDBKey);
        outer : (Principal, Nac.OuterSubDBKey);
    } {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        let part2 : Nac.PartitionCanister = actor (Principal.toText(part));
        let { inner; outer } = Nac.createOuter(superDB, part2, outerKey, innerKey);
        {
            inner = (Principal.fromActor(inner.0), inner.1);
            outer = (Principal.fromActor(outer.0), outer.1);
        };
    };

    public shared ({ caller }) func deleteInner({
        innerKey : Nac.InnerSubDBKey;
        sk : Nac.SK;
    }) : async () {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        await* Nac.deleteInner({ innerSuperDB = superDB; innerKey; sk });
    };

    public query func scanLimitInner({
        innerKey : Nac.InnerSubDBKey;
        lowerBound : Nac.SK;
        upperBound : Nac.SK;
        dir : BTree.Direction;
        limit : Nat;
    }) : async BTree.ScanLimitResult<Text, Nac.AttributeValue> {
        // ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.scanLimitInner({
            innerSuperDB = superDB;
            innerKey;
            lowerBound;
            upperBound;
            dir;
            limit;
        });
    };

    public shared func scanLimitOuter({
        outerKey : Nac.OuterSubDBKey;
        lowerBound : Text;
        upperBound : Text;
        dir : BTree.Direction;
        limit : Nat;
    }) : async BTree.ScanLimitResult<Text, Nac.AttributeValue> {
        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        await* Nac.scanLimitOuter({
            outerSuperDB = superDB;
            outerKey;
            lowerBound;
            upperBound;
            dir;
            limit;
        });
    };

    public query func scanSubDBs() : async [(Nac.OuterSubDBKey, (Principal, Nac.InnerSubDBKey))] {
        // ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        type T1 = (Nac.OuterSubDBKey, (Nac.InnerCanister, Nac.InnerSubDBKey));
        type T2 = (Nac.OuterSubDBKey, (Principal, Nac.InnerSubDBKey));
        let array : [T1] = Nac.scanSubDBs({ superDB });
        let iter = Iter.map(
            array.vals(),
            func((outerKey, (inner, innerKey)) : T1) : T2 {
                (outerKey, (Principal.fromActor(inner), innerKey));
            },
        );
        Iter.toArray(iter);
    };

    public query func getByInner({ innerKey : Nac.InnerSubDBKey; sk : Nac.SK }) : async ?Nac.AttributeValue {
        // ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.getByInner({ superDB; innerKey; sk });
    };

    public query func hasByInner({ innerKey : Nac.InnerSubDBKey; sk : Nac.SK }) : async Bool {
        // ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.hasByInner({ superDB; innerKey; sk });
    };

    public shared func getByOuter({ outerKey : Nac.OuterSubDBKey; sk : Nac.SK }) : async ?Nac.AttributeValue {
        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        await* Nac.getByOuter({ outerSuperDB = superDB; outerKey; sk });
    };

    public shared func hasByOuter({ outerKey : Nac.OuterSubDBKey; sk : Nac.SK }) : async Bool {
        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        await* Nac.hasByOuter({ outerSuperDB = superDB; outerKey; sk });
    };

    public shared func hasSubDBByOuter(options : { outerKey : Nac.OuterSubDBKey }) : async Bool {
        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        await* Nac.hasSubDBByOuter({
            outerSuperDB = superDB;
            outerKey = options.outerKey;
        });
    };

    public query func hasSubDBByInner(options : { innerKey : Nac.InnerSubDBKey }) : async Bool {
        // ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.hasSubDBByInner({
            innerSuperDB = superDB;
            innerKey = options.innerKey;
        });
    };

    public shared func subDBSizeByOuter({ outerKey : Nac.OuterSubDBKey }) : async ?Nat {
        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        await* Nac.subDBSizeByOuter({ outerSuperDB = superDB; outerKey });
    };

    public query func subDBSizeByInner({ innerKey : Nac.InnerSubDBKey }) : async ?Nat {
        // ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.subDBSizeByInner({ superDB; innerKey });
    };

    public shared ({ caller }) func startInsertingImpl({
        guid : [Nat8];
        indexCanister : Principal;
        outerCanister : Principal;
        outerKey : Nac.OuterSubDBKey;
        sk : Nac.SK;
        value : Nac.AttributeValue;
        innerKey : Nac.InnerSubDBKey;
        needsMove : Bool;
    }) : async () {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        let index : Nac.IndexCanister = actor (Principal.toText(indexCanister));
        let outer : Nac.OuterCanister = actor (Principal.toText(outerCanister));
        await* Nac.startInsertingImpl({
            guid = Blob.fromArray(guid);
            indexCanister = index;
            outerCanister = outer;
            outerKey;
            sk;
            value;
            innerSuperDB = superDB;
            innerKey;
            needsMove;
        });
    };

    public func getSubDBUserDataOuter(options : { outerKey : Nac.OuterSubDBKey }) : async ?Text {
        await* Nac.getSubDBUserDataOuter({
            superDB;
            outerKey = options.outerKey;
        });
    };

    public func getSubDBUserDataInner(options : { innerKey : Nac.InnerSubDBKey }) : async ?Text {
        Nac.getSubDBUserDataInner({ superDB; subDBKey = options.innerKey });
    };

    // TODO: Add this function to the public interface in NacDB?
    public query func getInner(outerKey : Nac.OuterSubDBKey) : async ?(Principal, Nac.InnerSubDBKey) {
        do ? {
            let (part, key) = Nac.getInner(superDB, outerKey)!;
            (Principal.fromActor(part), key);
        };
    };

    public shared ({ caller }) func deleteSubDBOuter({
        outerKey : Nac.OuterSubDBKey;
    }) : async () {
        checkCaller(caller);
        await* Nac.deleteSubDBOuter({ superDB; outerKey });
    };

    public shared func rawDeleteSubDB({ innerKey : Nac.InnerSubDBKey }) : async () {
        checkCaller(caller);

        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.rawDeleteSubDB(superDB, innerKey);
    };

    public query func rawGetSubDB({ innerKey : Nac.InnerSubDBKey }) : async ?{
        map : [(Nac.SK, Nac.AttributeValue)];
        userData : Text;
    } {
        // ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);
        Nac.rawGetSubDB(superDB, innerKey);
    };

    // TODO: Remove superfluous functions from above.
};
