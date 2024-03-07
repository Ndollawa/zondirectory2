import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Float "mo:base/Float";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";

import BTree "mo:stableheapbtreemap/BTree";
import RBT "mo:stable-rbtree/StableRBTree";
import xNat "mo:xtendedNumbers/NatX";
import StableBuffer "mo:StableBuffer/StableBuffer";

import ICRC1Types "mo:icrc1/ICRC1/Types";
import CanDBIndex "canister:CanDBIndex";
import CanDBPartition "../storage/CanDBPartition";
import MyCycles "mo:nacdb/Cycles";
import Entity "mo:candb/Entity";
import CanDBConfig "libs/configs/canDB.config";
import NacDbPartition "../storage/NacDBPartition";

import Payments "canisters/payments/main";
import Order "canisters/order/main";
import CanDBHelper "libs/utils/helpers/canDB.helper";
import PassportConfig "libs/configs/passport.config";

shared actor class ZonBackend() = this {
/// External Canisters ///

  /// Some Global Variables ///

  // See ARCHITECTURE.md for database structure

  // TODO: Avoid duplicate user nick names.

  stable var maxId: Nat = 0;

  stable var founder: ?Principal = null;

  /// Initialization ///

  stable var initialized: Bool = false;

  public shared({ caller }) func init(): async () {
    ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);

    if (initialized) {
      Debug.trap("already initialized");
    };

    founder := ?caller;

    initialized := true;
  };

  /// Owners ///

  func onlyMainOwner(caller: Principal) {
    if (?caller != founder) {
      Debug.trap("not the main owner");
    }
  };

  public shared({caller}) func setMainOwner(_founder: Principal) {
    onlyMainOwner(caller);

    founder := ?_founder;
  };

  // TODO: probably, superfluous.
  public shared({caller}) func removeMainOwner() {
    onlyMainOwner(caller);
    
    founder := null;
  };

  /// Users ///

  type User = {
    locale: Text;
    nick: Text;
    title: Text;
    description: Text;
    // TODO: long description
    link : Text;
  };

  func serializeUser(user: User): Entity.AttributeValue {
    var buf = Buffer.Buffer<Entity.AttributeValuePrimitive>(6);
    buf.add(#int 0); // version
    buf.add(#text (user.locale));
    buf.add(#text (user.nick));
    buf.add(#text (user.title));
    buf.add(#text (user.description));
    buf.add(#text (user.link));
    #tuple (Buffer.toArray(buf));
  };

  func deserializeUser(attr: Entity.AttributeValue): User {
    var locale = "";
    var nick = "";
    var title = "";
    var description = "";
    var link = "";
    let res = label r: Bool switch (attr) {
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
            case _ { break r false; };
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

  public shared({caller}) func setUserData(partitionId: ?Principal, _user: User) {
    let key = "u/" # Principal.toText(caller); // TODO: Should use binary encoding.
    // TODO: Add Hint to CanDBMulti
    ignore await CanDBIndex.putAttributeNoDuplicates("user", {
        sk = key;
        key = "u";
        value = serializeUser(_user);
      },
    );
  };

  // TODO: Should also remove all his/her items?
  public shared({caller}) func removeUser(canisterId: Principal) {
    var db: CanDBPartition.CanDBPartition = actor(Principal.toText(canisterId));
    let key = "u/" # Principal.toText(caller);
    await db.delete({sk = key});
  };

  /// Items ///

  stable var rootItem: ?(CanDBPartition.CanDBPartition, Nat) = null;

  public shared({caller}) func setRootItem(part: Principal, id: Nat)
    : async ()
  {
    onlyMainOwner(caller);

    rootItem := ?(actor(Principal.toText(part)), id);
  };

  public query func getRootItem(): async ?(Principal, Nat) {
    do ? {
      let (part, n) = rootItem!;
      (Principal.fromActor(part), n);
    };
  };

  public shared({caller}) func createItemData(item: CanDBHelper.ItemWithoutOwner)
    : async (Principal, Nat)
  {
    let item2: CanDBHelper.Item = { creator = caller; item; };
    let itemId = maxId;
    maxId += 1;
    let key = "i/" # Nat.toText(itemId);
    let canisterId = await CanDBIndex.putAttributeWithPossibleDuplicate(
      "main", { sk = key; key = "i"; value = CanDBHelper.serializeItem(item2) }
    );
    (canisterId, itemId);
  };

  // We don't check that owner exists: If a user lost his/her item, that's his/her problem, not ours.
  public shared({caller}) func setItemData(canisterId: Principal, _itemId: Nat, item: CanDBHelper.ItemWithoutOwner) {
    var db: CanDBPartition.CanDBPartition = actor(Principal.toText(canisterId));
    let key = "i/" # Nat.toText(_itemId); // TODO: better encoding
    switch (await db.getAttribute({sk = key}, "i")) {
      case (?oldItemRepr) {
        let oldItem = CanDBHelper.deserializeItem(oldItemRepr);
        if (caller != oldItem.creator) {
          Debug.trap("can't change item owner");
        };
        let _item: CanDBHelper.Item = { item = item; creator = caller; var streams = null; };
        if (_item.item.details != oldItem.item.details) {
          Debug.trap("can't change item type");
        };
        if (oldItem.item.communal) {
          Debug.trap("can't edit communal folder");
        };
        CanDBHelper.onlyItemOwner(caller, oldItem);
        await db.putAttribute({sk = key; key = "i"; value = CanDBHelper.serializeItem(_item)});
      };
      case _ { Debug.trap("no item") };
    };
  };

  public shared({caller}) func setPostText(canisterId: Principal, _itemId: Nat, text: Text) {
    var db: CanDBPartition.CanDBPartition = actor(Principal.toText(canisterId));
    let key = "i/" # Nat.toText(_itemId); // TODO: better encoding
    switch (await db.getAttribute({sk = key}, "i")) {
      case (?oldItemRepr) {
        let oldItem = CanDBHelper.deserializeItem(oldItemRepr);
        if (caller != oldItem.creator) {
          Debug.trap("can't change item owner");
        };
        CanDBHelper.onlyItemOwner(caller, oldItem);
        switch(oldItem.item.details) {
          case (#post) {};
          case _ { Debug.trap("not a post"); };
        };
        await db.putAttribute({ sk = key; key = "t"; value = #text(text) });
      };
      case _ { Debug.trap("no item") };
    };
  };

  // TODO: Also remove voting data.
  public shared({caller}) func removeItem(canisterId: Principal, _itemId: Nat) {
    // We first remove links, then the item itself, in order to avoid race conditions when displaying.
    await Order.removeItemLinks((canisterId, _itemId));
    var db: CanDBPartition.CanDBPartition = actor(Principal.toText(canisterId));
    let key = "i/" # Nat.toText(_itemId);
    let ?oldItemRepr = await db.getAttribute({sk = key}, "i") else {
      Debug.trap("no item");
    };
    let oldItem = CanDBHelper.deserializeItem(oldItemRepr);
    if (oldItem.item.communal) {
      Debug.trap("it's communal");
    };
    CanDBHelper.onlyItemOwner(caller, oldItem);
    await db.delete({sk = key});
  };

  // TODO: Set maximum lengths on user nick, chirp length, etc.

  /// Affiliates ///

  // public shared({caller}) func setAffiliate(canister: Principal, buyerAffiliate: ?Principal, sellerAffiliate: ?Principal): async () {
  //   var db: CanDBPartition.CanDBPartition = actor(Principal.toText(canister));
  //   if (buyerAffiliate == null and sellerAffiliate == null) {
  //     await db.delete({sk = "a/" # Principal.toText(caller)});
  //   };
  //   let buyerAffiliateStr = switch (buyerAffiliate) {
  //     case (?user) { Principal.toText(user) };
  //     case (null) { "" }
  //   };
  //   let sellerAffiliateStr = switch (sellerAffiliate) {
  //     case (?user) { Principal.toText(user) };
  //     case (null) { "" }
  //   };
  //   // await db.put({sk = "a/" # Principal.toText(caller); attributes = [("v", #text (buyerAffiliateStr # "/" # sellerAffiliateStr))]});
  // };

  public shared func get_trusted_origins(): async [Text] {
    return [];
  };
};
