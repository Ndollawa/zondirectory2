import Nat "mo:base/Nat";
import Float "mo:base/Float";
import Time "mo:base/Time";
import Bool "mo:base/Bool";

module {

    // TODO: Use this.
    public type Karma = {
        earnedVotes : Nat;
        remainingBonusVotes : Nat;
        lastBonusUpdated : Time.Time;
    };

    public type VotingScore = {
        points : Float; // Gitcoin score
        lastChecked : Time.Time;
        ethereumAddress : Text; // TODO: Store in binary
    };
};
