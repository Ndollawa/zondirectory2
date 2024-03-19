import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Time "mo:base/Time";
import Principal "mo:base/Principal";

import Token "mo:icrc1/ICRC1/Canisters/Token";
import BTree "mo:stableheapbtreemap/BTree";
import ICRC1Types "mo:icrc1/ICRC1/Types";
import MyCycles "mo:nacdb/Cycles";
import CanDBPartition "../../../storage/CanDBPartition";

// import PST "canister:pst";
import { User } = "types/auth";

import CanDBConfig "../../libs/configs/canDB.config";
import PassportConfig "../../libs/configs/passport.config";
import CanDBHelper "../../libs/utils/helpers/canDB.helper";
import fractions "../../libs/utils/helpers/fractions.helper";

shared ({ caller = initialOwner }) actor class Auth() = this {
  /// Users ///

  func serializeUser(user : User) : Entity.AttributeValue {
    var buf = Buffer.Buffer<Entity.AttributeValuePrimitive>(6);
    buf.add(#int 0); // version
    buf.add(#text(user.locale));
    buf.add(#text(user.nick));
    buf.add(#text(user.title));
    buf.add(#text(user.description));
    buf.add(#text(user.link));
    #tuple(Buffer.toArray(buf));
  };

  func deserializeUser(attr : Entity.AttributeValue) : User {
    var locale = "";
    var nick = "";
    var title = "";
    var description = "";
    var link = "";
    let res = label r : Bool switch (attr) {
      case (#tuple arr) {
        var pos = 0;
        while (pos < arr.size()) {
          switch (pos) {
            case (0) {
              switch (arr[pos]) {
                case (#int v) {
                  assert v == 0; // version
                };
                case _ { break r false };
              };
            };
            case (1) {
              switch (arr[pos]) {
                case (#text v) {
                  locale := v;
                };
                case _ { break r false };
              };
            };
            case (2) {
              switch (arr[pos]) {
                case (#text v) {
                  nick := v;
                };
                case _ { break r false };
              };
            };
            case (3) {
              switch (arr[pos]) {
                case (#text v) {
                  title := v;
                };
                case _ { break r false };
              };
            };
            case (4) {
              switch (arr[pos]) {
                case (#text v) {
                  description := v;
                };
                case _ { break r false };
              };
            };
            case (5) {
              switch (arr[pos]) {
                case (#text v) {
                  link := v;
                };
                case _ { break r false };
              };
            };
            case _ { break r false };
          };
          pos += 1;
        };
        true;
      };
      case _ {
        false;
      };
    };
    if (not res) {
      Debug.trap("wrong user format");
    };
    {
      locale = locale;
      nick = nick;
      title = title;
      description = description;
      link = link;
    };
  };

  public shared ({ caller }) func setUserData(partitionId : ?Principal, _user : User) {
    let key = "u/" # Principal.toText(caller); // TODO: Should use binary encoding.
    // TODO: Add Hint to CanDBMulti
    ignore await CanDBIndex.putAttributeNoDuplicates(
      "user",
      {
        sk = key;
        key = "u";
        value = serializeUser(_user);
      },
    );
  };

  // TODO: Should also remove all his/her items?
  public shared ({ caller }) func removeUser(canisterId : Principal) {
    var db : CanDBPartition.CanDBPartition = actor (Principal.toText(canisterId));
    let key = "u/" # Principal.toText(caller);
    await db.delete({ sk = key });
  };

  func sybilScoreImpl(user : Principal) : async* (Bool, Float) {
    // checkCaller(user); // TODO: enable?

    let voting = await* getVotingData(user, null); // TODO: hint `partitionId`, not null
    switch (voting) {
      case (?voting) {
        Debug.print("VOTING: " # debug_show (voting));
        if (
          voting.lastChecked + 150 * 24 * 3600 * 1_000_000_000 >= Time.now() and // TODO: Make configurable.
          voting.points >= PassportConfig.minimumScore,
        ) {
          (true, voting.points);
        } else {
          (false, 0.0);
        };
      };
      case null { (false, 0.0) };
    };
  };

  public shared ({ caller }) func sybilScore() : async (Bool, Float) {
    await* sybilScoreImpl(caller);
  };

  public shared func checkSybil(user : Principal) : async () {
    // checkCaller(user); // TODO: enable?
    if (PassportConfig.skipSybil) {
      return;
    };
    let (allowed, score) = await* sybilScoreImpl(user);
    if (not allowed) {
      Debug.trap("Sybil check failed");
    };
  };
};
