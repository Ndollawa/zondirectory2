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

import Item "canisters/item/main";
import { ItemWithoutOwner } "canisters/items/types/item";
import Auth "canisters/auth/main";
import Folder "canisters/folder/main";
import Vote "canisters/vote/main";
import Payment "canisters/payment/main";
import Order "canisters/order/main";
import CanDBHelper "libs/utils/helpers/canDB.helper";
import PassportConfig "libs/configs/passport.config";

shared ({ caller = owner }) actor class ZonBackend() = this {
  /// External Canisters ///

  /// Some Global Variables ///

  // See ARCHITECTURE.md htmlFor database structure

  // TODO: Avoid duplicate user nick names.

  stable var maxId : Nat = 0;

  stable var founder : ?Principal = null;

  /// Initialization ///

  stable var initialized : Bool = false;

  public shared ({ caller }) func init() : async () {
    ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles);

    if (initialized) {
      Debug.trap("already initialized");
    };

    founder := ?caller;

    initialized := true;
  };

  /// Owners ///

  func onlyMainOwner(caller : Principal) {
    if (?caller != founder) {
      Debug.trap("not the main owner");
    };
  };

  public shared ({ caller }) func setMainOwner(_founder : Principal) {
    onlyMainOwner(caller);

    founder := ?_founder;
  };

  // TODO: probably, superfluous.
  public shared ({ caller }) func removeMainOwner() {
    onlyMainOwner(caller);

    founder := null;
  };

  stable var rootItem : ?(CanDBPartition.CanDBPartition, Nat) = null;

  public shared ({ caller }) func setRootItem(part : Principal, id : Nat) : async () {
    onlyMainOwner(caller);

    rootItem := ?(actor (Principal.toText(part)), id);
  };

  public query func getRootItem() : async ?(Principal, Nat) {
    do ? {
      let (part, n) = rootItem!;
      (Principal.fromActor(part), n);
    };
  };

  /// Items Endpoints ///

  public shared ({ caller }) func createItemData(item : ItemWithoutOwner) : async (Principal, Nat) {
    await Item.createItemData(item);
  };

  // We don't check that owner exists: If a user lost his/her item, that's his/her problem, not ours.
  public shared ({ caller }) func setItemData(canisterId : Principal, _itemId : Nat, item : ItemWithoutOwner) {
    await Item.setItemData(canisterId, _itemId, item);
  };

  public shared ({ caller }) func setPostText(canisterId : Principal, _itemId : Nat, text : Text) {
    await Item.setPostText(canisterId, _itemId, text);
  };

  // TODO: Also remove voting data.
  public shared ({ caller }) func removeItem(canisterId : Principal, _itemId : Nat) {
    await Item.remove(canisterId, _itemId);
  };

  /// Vote Endpoints ///
  /// Auth Endpoints ///
  /// Folder/Category Endpoints ///
  /// Payment Endpoints ///
  /// Order Endpoints ///
  /// Affiliate Endpoints ///

  public shared func get_trusted_origins() : async [Text] {
    return [];
  };
};
