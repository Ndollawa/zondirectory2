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
};
