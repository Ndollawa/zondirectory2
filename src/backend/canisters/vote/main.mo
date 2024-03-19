import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Char "mo:base/Char";
import Nat64 "mo:base/Nat64";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Time "mo:base/Time";
import Bool "mo:base/Bool";

import xNat "mo:xtendedNumbers/NatX";
import CM "mo:candb/CanisterMap";
import Nac "mo:nacdb/NacDB";
import NacDBPartition "../../../storage/NacDBPartition";
import RBT "mo:stable-rbtree/StableRBTree";
import Entity "mo:candb/Entity";
import Reorder "mo:NacDBReorder/Reorder";
import PassportConfig "../../libs/configs/passport.config";

import { Karma; VotingScore } "./types/vote";

shared ({ caller = initialOwner }) actor class Vote() = this {

    public func serializeKarma(karma : Karma) : Entity.AttributeValue {
        #tuple([
            #int(0), // version
            #int(karma.earnedVotes),
            #int(karma.remainingBonusVotes),
            #int(karma.lastBonusUpdated),
        ]);
    };

    public func deserializeKarma(attr : Entity.AttributeValue) : Karma {
        let res = label r {
            switch (attr) {
                case (#tuple arr) {
                    let a : [var Nat] = Array.tabulateVar<Nat>(3, func _ = 0);
                    switch (arr[0]) {
                        case (#int v) {
                            assert v == 0;
                        };
                        case _ { Debug.trap("Wrong karma version") };
                    };
                    for (i in Iter.range(0, 2)) {
                        switch (arr[i +1]) {
                            case (#int elt) {
                                a[i] := Int.abs(elt);
                            };
                            case _ { break r };
                        };
                        return {
                            earnedVotes = a[0];
                            remainingBonusVotes = a[1];
                            lastBonusUpdated = a[2];
                        };
                    };
                };
                case _ { break r };
            };
        };
        Debug.trap("wrong votes format");
    };
    // TODO: Also store, how much votings were done.

    public func serializeVoting(voting : VotingScore) : Entity.AttributeValue {
        var buf = Buffer.Buffer<Entity.AttributeValuePrimitive>(4);
        buf.add(#int 0); // version
        buf.add(#bool true);
        buf.add(#float(voting.points));
        buf.add(#int(voting.lastChecked));
        buf.add(#text(voting.ethereumAddress));
        #tuple(Buffer.toArray(buf));
    };

    public func deserializeVoting(attr : Entity.AttributeValue) : VotingScore {
        var isScore : Bool = false;
        var points : Float = 0.0;
        var lastChecked : Time.Time = 0;
        var ethereumAddress : Text = "";

        let res = label r : Bool switch (attr) {
            case (#tuple arr) {
                var pos : Nat = 0;
                switch (arr[pos]) {
                    case (#int v) {
                        assert v == 0;
                    };
                    case _ { break r false };
                };
                pos += 1;
                switch (arr[pos]) {
                    case (#bool v) {
                        isScore := v;
                    };
                    case _ { break r false };
                };
                pos += 1;
                if (isScore) {
                    switch (arr[pos]) {
                        case (#float v) {
                            points := v;
                        };
                        case _ { break r false };
                    };
                    pos += 1;
                    switch (arr[pos]) {
                        case (#int v) {
                            lastChecked := v;
                        };
                        case _ { break r false };
                    };
                    pos += 1;
                    switch (arr[pos]) {
                        case (#text v) {
                            ethereumAddress := v;
                        };
                        case _ { break r false };
                    };
                    pos += 1;
                };
                true;
            };
            case _ { break r false };
        };
        if (not res) {
            Debug.trap("cannot deserialize Voting");
        };
        { points; lastChecked; ethereumAddress };
    };

    func setVotingDataImpl(user : Principal, partitionId : ?Principal, voting : VotingScore) : async* () {
        let sk = "u/" # Principal.toText(user); // TODO: Should use binary encoding.
        // TODO: Add Hint to CanDBMulti
        ignore await* Multi.putAttributeNoDuplicates(
            pkToCanisterMap,
            "user",
            {
                sk;
                key = "v";
                value = serializeVoting(voting);
            },
        );
    };

    public shared ({ caller }) func setVotingData(user : Principal, partitionId : ?Principal, voting : VotingScore) : async () {
        checkCaller(caller); // necessary
        await* setVotingDataImpl(user, partitionId, voting);
    };

    func getVotingData(caller : Principal, partitionId : ?Principal) : async* ?CanDBHelper.VotingScore {
        let sk = "u/" # Principal.toText(caller); // TODO: Should use binary encoding.
        // TODO: Add Hint to CanDBMulti
        let res = await* Multi.getAttributeByHint(pkToCanisterMap, "user", partitionId, { sk; key = "v" });
        do ? { deserializeVoting(res!.1!) };
    };

    /// Voting ///

    /// `amount == 0` means canceling the vote.
    public shared ({ caller }) func vote(parentPrincipal : Principal, parent : Nat, childPrincipal : Principal, child : Nat, value : Int, comment : Bool) : async () {
        await CanDBIndex.checkSybil(caller);
        assert value >= -1 and value <= 1;

        let userVotesSK = "v/" # Principal.toText(caller) # "/" # Nat.toText(parent) # "/" # Nat.toText(child);
        let oldVotes = await CanDBIndex.getFirstAttribute("user", { sk = userVotesSK; key = "v" }); // TODO: race condition
        let (principal, oldValue) = switch (oldVotes) {
            case (?oldVotes) { (?oldVotes.0, oldVotes.1) };
            case null { (null, null) };
        };
        let oldValue2 = switch (oldValue) {
            case (?v) {
                let #int v2 = v else {
                    Debug.trap("wrong votes");
                };
                v2;
            };
            case null { 0 };
        };
        let difference = value - oldValue2;
        if (difference == 0) {
            return;
        };
        // TODO: Take advantage of `principal` as a hint.
        ignore await CanDBIndex.putAttributeNoDuplicates("user", { sk = userVotesSK; key = "v"; value = #int value });

        // Update total votes for the given parent/child:
        let totalVotesSK = "w/" # Nat.toText(parent) # "/" # Nat.toText(child);
        let oldTotals = await CanDBIndex.getFirstAttribute("user", { sk = totalVotesSK; key = "v" }); // TODO: race condition
        let (up, down, oldTotalsPrincipal) = switch (oldTotals) {
            case (?(oldTotalsPrincipal, ?(#tuple(a)))) {
                let (#int up, #int down) = (a[0], a[1]) else {
                    Debug.trap("votes programming error");
                };
                (up, down, ?oldTotalsPrincipal);
            };
            case null {
                (0, 0, null);
            };
            case _ {
                Debug.trap("votes programming error");
            };
        };

        // TODO: Check this block of code for errors.
        let changeUp = (value == 1 and oldValue2 != 1) or (oldValue2 == 1 and value != 1);
        let changeDown = (value == -1 and oldValue2 != -1) or (oldValue2 == -1 and value != -1);
        var up2 = up;
        var down2 = down;
        if (changeUp or changeDown) {
            if (changeUp) {
                up2 += if (difference > 0) { 1 } else { -1 };
            };
            if (changeDown) {
                down2 += if (difference > 0) { -1 } else { 1 };
            };
            // TODO: Take advantage of `oldTotalsPrincipal` as a hint:
            ignore await CanDBIndex.putAttributeNoDuplicates("user", { sk = totalVotesSK; key = "v"; value = #tuple([#int up2, #int down2]) }); // TODO: race condition
        };

        let parentCanister = actor (Principal.toText(parentPrincipal)) : CanDBPartition.CanDBPartition;
        let links = await* getStreamLinks((childPrincipal, child), comment);
        let streamsData = await* itemsStream((parentPrincipal, parent), "sv");
        let streamsVar : [var ?Reorder.Order] = switch (streamsData) {
            case (?streams) { Array.thaw(streams) };
            case null { [var null, null, null] };
        };
        let order = switch (streamsVar[links]) {
            case (?order) { order };
            case null {
                await* Reorder.createOrder(GUID.nextGuid(guidGen), NacDBIndex, orderer);
            };
        };
        if (streamsVar[links] == null) {
            streamsVar[links] := ?order;
            let data = CanDBHelper.serializeStreams(Array.freeze(streamsVar));
            await parentCanister.putAttribute({
                sk = "i/" # Nat.toText(parent);
                key = "sv";
                value = data;
            });
        };

        await* Reorder.move(
            GUID.nextGuid(guidGen),
            NacDBIndex,
            orderer,
            {
                order;
                value = Nat.toText(child) # "@" # Principal.toText(childPrincipal);
                relative = true;
                newKey = -difference * 2 ** 16;
            },
        );
    };

    // TODO: Below functions?

    // func deserializeVoteAttr(attr: Entity.AttributeValue): Float {
    //   switch(attr) {
    //     case (#float v) { v };
    //     case _ { Debug.trap("wrong data"); };
    //   }
    // };

    // func deserializeVotes(map: Entity.AttributeMap): Float {
    //   let v = RBT.get(map, Text.compare, "v");
    //   switch (v) {
    //     case (?v) { deserializeVoteAttr(v) };
    //     case _ { Debug.trap("map not found") };
    //   };
    // };

    // TODO: It has race period of duplicate (two) keys. In frontend de-duplicate.
    // TODO: Use binary keys.
    // TODO: Sorting CanDB by `Float` is wrong order.
    // func setVotes(
    //   stream: VotesStream,
    //   oldVotesRandom: Text,
    //   votesUpdater: ?Float -> Float,
    //   oldVotesDBCanisterId: Principal,
    //   parentChildCanisterId: Principal,
    // ): async* () {
    //   if (StableBuffer.size(stream.settingVotes) != 0) {
    //     return;
    //   };
    //   let tmp = StableBuffer.get(stream.settingVotes, Int.abs((StableBuffer.size(stream.settingVotes): Int) - 1));

    //   // Prevent races:
    //   if (not tmp.inProcess) {
    //     if (BTree.has(stream.currentVotes, Nat64.compare, tmp.parent) or BTree.has(stream.currentVotes, Nat64.compare, tmp.child)) {
    //       Debug.trap("clash");
    //     };
    //     ignore BTree.insert(stream.currentVotes, Nat64.compare, tmp.parent, ());
    //     ignore BTree.insert(stream.currentVotes, Nat64.compare, tmp.child, ());
    //     tmp.inProcess := true;
    //   };

    //   let oldVotesDB: CanDBPartition.CanDBPartition = actor(Principal.toText(oldVotesDBCanisterId));
    //   let oldVotesKey = stream.prefix2 # Nat.toText(xNat.from64ToNat(tmp.parent)) # "/" # Nat.toText(xNat.from64ToNat(tmp.child));
    //   let oldVotesWeight = switch (await oldVotesDB.get({sk = oldVotesKey})) {
    //     case (?oldVotesData) { ?deserializeVotes(oldVotesData.attributes) };
    //     case (null) { null }
    //   };
    //   let newVotes = switch (oldVotesWeight) {
    //     case (?oldVotesWeight) {
    //       let newVotesWeight = votesUpdater(?oldVotesWeight);
    //       { weight = newVotesWeight; random = oldVotesRandom };
    //     };
    //     case (null) {
    //       let newVotesWeight = votesUpdater null;
    //       { weight = newVotesWeight; random = rng.next() };
    //     };
    //   };

    //   // TODO: Should use binary format. // TODO: Decimal serialization makes order by `random` broken.
    //   // newVotes -> child
    //   let newKey = stream.prefix1 # Nat.toText(xNat.from64ToNat(tmp.parent)) # "/" # Float.toText(newVotes.weight) # "/" # oldVotesRandom;
    //   await oldVotesDB.put({sk = newKey; attributes = [("v", #text (Nat.toText(Nat64.toNat(tmp.child))))]});
    //   // child -> newVotes
    //   let parentChildCanister: CanDBPartition.CanDBPartition = actor(Principal.toText(parentChildCanisterId));
    //   let newKey2 = stream.prefix2 # Nat.toText(xNat.from64ToNat(tmp.parent)) # "/" # Nat.toText(xNat.from64ToNat(tmp.child));
    //   // TODO: Use NacDB:
    //   await parentChildCanister.put({sk = newKey2; attributes = [("v", #float (newVotes.weight))]});
    //   switch (oldVotesWeight) {
    //     case (?oldVotesWeight) {
    //       let oldKey = stream.prefix1 # Nat.toText(xNat.from64ToNat(tmp.parent)) # "/" # Float.toText(oldVotesWeight) # "/" # oldVotesRandom;
    //       // delete oldVotes -> child
    //       await oldVotesDB.delete({sk = oldKey});
    //     };
    //     case (null) {};
    //   };

    //   ignore StableBuffer.removeLast(stream.settingVotes);
    // };

    // stable var userBusyVoting: BTree.BTree<Principal, ()> = BTree.init<Principal, ()>(null); // TODO: Delete old ones.

    // TODO: Need to remember the votes // TODO: Remembering in CanDB makes no sense because need to check canister.
    // public shared({caller}) func oneVotePerPersonVote(sybilCanister: Principal) {
    //   await* checkSybil(sybilCanister, caller);
    //   ignore BTree.insert(userBusyVoting, Principal.compare, caller, ());

    //   // setVotes(
    //   //   stream: VotesStream,
    //   //   oldVotesRandom: Text,
    //   //   votesUpdater: ?Float -> Float,
    //   //   oldVotesDBCanisterId: Principal,
    //   //   parentChildCanisterId)
    //   // TODO
    // };

    // func setVotes2(parent: Nat64, child: Nat64, prefix1: Text, prefix2: Text) {

    // }
};
