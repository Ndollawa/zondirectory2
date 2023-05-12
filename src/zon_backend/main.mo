import IndexCanister "../storage/IndexCanister";
import PST "../zon_pst";
import DBPartition "../storage/DBPartition";
import Principal "mo:base/Principal";
import Float "mo:base/Float";
import Bool "mo:base/Bool";
import Debug "mo:base/Debug";
import Prelude "mo:base/Prelude";
import Entity "mo:candb/Entity";
import RBT "mo:stable-rbtree/StableRBTree";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import xNat "mo:xtendedNumbers/NatX";
import Buffer "mo:base/Buffer";

// TODO: Also make the founder's account an owner?
actor ZonBackend {
  stable var index: ?IndexCanister.IndexCanister = null;
  stable var pst: ?PST.PST = null;
  stable var itemsDB: ?DBPartition.DBPartition = null;
  stable var authorsDB: ?DBPartition.DBPartition = null;

  public shared({ caller }) func init() {
    founder := ?caller;
    if (pst == null) {
      // FIXME: `null` subaccount?
      pst := ?(await PST.PST({ owner = Principal.fromActor(ZonBackend); subaccount = null }));
    };
    if (index == null) {
      index := ?(await IndexCanister.IndexCanister([Principal.fromActor(ZonBackend)]));
    };
    if (authorsDB == null) {
      switch (index) {
        case (?index) {
          authorsDB := await index.createDBPartition("authors");
        };
        case (null) {}
      }
    }
  };

  stable var salesOwnersShare = 0.1;
  stable var upvotesOwnersShare = 0.5;
  stable var uploadOwnersShare = 0.15;
  stable var buyerAffiliateShare = 0.1;
  stable var sellerAffiliateShare = 0.15;

  public query func getSalesOwnersShare(): async Float { salesOwnersShare };
  public query func getUpvotesOwnersShare(): async Float { upvotesOwnersShare };
  public query func getUploadOwnersShare(): async Float { uploadOwnersShare };
  public query func getBuyerAffiliateShare(): async Float { buyerAffiliateShare };
  public query func getSellerAffiliateShare(): async Float { sellerAffiliateShare };

  stable var maxId: Nat64 = 0;

  // TODO: Here and below: subaccount?
  stable var founder: ?Principal = null;

  // TODO: Add `license` field?
  // TODO: Affiliates.
  // TODO: Images.
  // TODO: Upload files.
  // TODO: Item version.
  type Item = {
    owner: ?Principal;
    price: Nat;
    locale: Text;
    title: Text;
    description: Text;
    details: {
      #link : Text;
      #post : ();
      #category : ();
    };
  };

  type User = {
    locale: Text;
    nick: Text;
    title: Text;
    description: Text;
    link : Text;
  };

  func onlyMainOwner(caller: Principal): Bool {
    if (?caller == founder) {
      true;
    } else {
      Debug.trap("not the main owner");
    }
  };

  public shared({caller = caller}) func setMainOwner(_founder: Principal) {
    if (onlyMainOwner(caller)) {
      founder := ?_founder;
    }
  };

  public shared({caller = caller}) func removeMainOwner() {
    if (onlyMainOwner(caller)) {
      founder := null;
    }
  };

  public shared({caller = caller}) func setSalesOwnersShare(_share: Float) {
    if (onlyMainOwner(caller)) {
      salesOwnersShare := _share;
    };
  };

  public shared({caller = caller}) func setUpvotesOwnersShare(_share: Float) {
    if (onlyMainOwner(caller)) {
      upvotesOwnersShare := _share;
    };
  };

  public shared({caller = caller}) func setUploadOwnersShare(_share: Float) {
    if (onlyMainOwner(caller)) {
      uploadOwnersShare := _share;
    };
  };

  public shared({caller = caller}) func setBuyerAffiliateShare(_share: Float) {
    if (onlyMainOwner(caller)) {
      buyerAffiliateShare := _share;
    };
  };

  public shared({caller = caller}) func setSellerAffiliateShare(_share: Float) {
    if (onlyMainOwner(caller)) {
      sellerAffiliateShare := _share;
    };
  };

  func getItemsDB(): DBPartition.DBPartition {
    actor("itemsDB");
  };

  func onlyItemOwner(caller: Principal, _item: Item): Bool {
    if (?caller == _item.owner) {
      true;
    } else {
      Debug.trap("not the item owner");
    };
  };

  let SER_LINK = 0;
  let SER_POST = 1;
  let SER_CATEGORY = 2;

  func serializeItemAttr(item: Item): Entity.AttributeValue {
    var buf = Buffer.Buffer<Entity.AttributeValuePrimitive>(6);
    buf.add(#int (switch (item.details) {
      case (#link v) { SER_LINK };
      case (#post) { SER_POST };
      case (#category) { SER_CATEGORY };
    }));
    switch (item.owner) {
      case (?owner) {
        buf.add(#bool (true));
        buf.add(#text (Principal.toText(owner)));
      };
      case (null) {
        buf.add(#bool (false));
      };
    };
    buf.add(#int (item.price));
    buf.add(#text (item.locale));
    buf.add(#text (item.nick));
    buf.add(#text (item.title));
    buf.add(#text (item.description));
    switch (item.details) {
      case (#link v) {
        buf.add(#text v);
      };
      case _ {};
    };
    #tuple (buf.toArray());
  };

  func serializeItem(item: Item): [(Entity.AttributeKey, Entity.AttributeValue)] {
    [("v", serializeItemAttr(item))];
  };

  func deserializeItemAttr(attr: Entity.AttributeValue): Item {
    var kind: Int = 0;
    var owner: ?Principal = null;
    var price = 0;
    var locale = "";
    var nick = "";
    var title = "";
    var description = "";
    var details: {#none; #category; #link; #post} = #none;
    var link = "";
    let res = label r: Bool switch (attr) {
      case (#tuple arr) {
        var pos = 0;
        var num = 0;
        while (pos < arr.size()) {
          switch (num) {
            case (0) {
              switch (arr[pos]) {
                case (#int v) {
                  kind := v;
                };
                case _ { break r false };
              };
              pos += 1;
            };
            case (1) {
              switch (arr[pos]) {
                case (#bool true) {
                  switch (arr[pos+1]) {
                    case (#text v) {
                      owner := ?Principal.fromText(v);
                    };
                    case _ { break r false; };
                  };
                  pos += 2;
                };
                case (#bool false) {
                  owner := null;
                  pos += 1;
                };
                case _ { break r false; }
              };
            };
            case (2) {
              switch (arr[pos]) {
                case (#int v) {
                  price := 0; // FIXME: Use `v` instead.
                };
                case _ { break r false; };
              };
              pos += 1;
            };
            case (3) {
              switch (arr[pos]) {
                case (#text v) {
                  locale := v;
                };
                case _ { break r false; };
              };
              pos += 1;
            };
            case (4) {
              switch (arr[pos]) {
                case (#text v) {
                  nick := v;
                };
                case _ { break r false; };
              };
              pos += 1;
            };
            case (5) {
              switch (arr[pos]) {
                case (#text v) {
                  title := v;
                };
                case _ { break r false; };
              };
              pos += 1;
            };
            case (6) {
              switch (arr[pos]) {
                case (#text v) {
                  description := v;
                };
                case _ { break r false; }
              };
              pos += 1;
            };
            case (7) {
              switch (arr[pos]) {
                case (#text v) {
                  link := v;
                };
                case _ { break r false; };
              };
              pos += 1;
            };
            case _ { break r false; };
          };
          num += 1;
        };
        true;
      };
      case _ {
        false;
      };
    };
    if (not res) {
      Debug.trap("wrong item format");
    };
    {
      owner = owner;
      price = price;
      locale = locale;
      nick = nick;
      title = title;
      description = description;
      details = switch (kind) {
        case (0) { #link link };
        case (1) { #post };
        case (2) { #category };
        case _ { Debug.trap("wrong item format"); }
      };
    };    
  };

  func deserializeItem(map: Entity.AttributeMap): Item {
    let v = RBT.get(map, Text.compare, "v");
    switch (v) {
      case (?v) { deserializeItemAttr(v) };
      case _ { Debug.trap("map not found") };
    };    
  };

  // FIXME: This allows items with foreign user attribution.
  // We don't check owner: If a user lost his/her item, that's his/her problem, not ours.
  public shared({caller = caller}) func createItemData(canisterId: Principal, _item: Item) {
    let _itemId = maxId;
    maxId += 1;
    var db: DBPartition.DBPartition = actor(Principal.toText(canisterId));
    let key = Nat.toText(xNat.from64ToNat(_itemId)); // TODO: Should use binary encoding.
    db.put({sk = key; attributes = serializeItem(_item)});
  };

  // We don't check owner: If a user lost his/her item, that's his/her problem, not ours.
  public shared({caller = caller}) func setItemData(canisterId: Principal, _itemId: Nat64, _item: Item) {
    var db: DBPartition.DBPartition = actor(Principal.toText(canisterId));
    let key = Nat.toText(xNat.from64ToNat(_itemId)); // TODO: Should use binary encoding.
    switch (await db.get({sk = key})) {
      case (?oldItemRepr) {
        let oldItem = deserializeItem(oldItemRepr.attributes);
        if (onlyItemOwner(caller, oldItem)) {
          db.put({sk = key; attributes = serializeItem(_item)});
        };
      };
      case _ { Debug.trap("no item") };
    };
  };

  // TODO: Also remove voting data.
  public shared({caller = caller}) func removeItem(canisterId: Principal, _itemId: Nat64) {
    var db: DBPartition.DBPartition = actor(Principal.toText(canisterId));
    let key = Nat.toText(xNat.from64ToNat(_itemId)); // TODO: Should use binary encoding.
    switch (await db.get({sk = key})) {
      case (?oldItemRepr) {
        let oldItem = deserializeItem(oldItemRepr.attributes);
        if (onlyItemOwner(caller, oldItem)) {
          db.delete({sk = key});
        };
      };
      case _ { Debug.trap("no item") };
    };
  };

  // TODO: Should I set maximum lengths on user nick, chirp length, etc.

  func serializeUserAttr(user: User): Entity.AttributeValue {
    var buf = Buffer.Buffer<Entity.AttributeValuePrimitive>(6);
    buf.add(#text (user.locale));
    buf.add(#text (user.title));
    buf.add(#text (user.description));
    buf.add(#text (user.link));
    #tuple (buf.toArray());
  };

  func serializeUser(user: User): [(Entity.AttributeKey, Entity.AttributeValue)] {
    [("v", serializeUserAttr(user))];
  };

  func deserializeUserAttr(attr: Entity.AttributeValue): User {
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
                case (#text v) {
                  locale := v;
                };
                case _ { break r false };
              };
              pos += 1;
            };
            case (1) {
              switch (arr[pos]) {
                case (#text v) {
                  title := v;
                };
                case _ { break r false };
              };
              pos += 1;
            };
            case (2) {
              switch (arr[pos]) {
                case (#text v) {
                  description := v;
                };
                case _ { break r false };
              };
              pos += 1;
            };
            case (3) {
              switch (arr[pos]) {
                case (#text v) {
                  link := v;
                };
                case _ { break r false };
              };
              pos += 1;
            };
            case _ { break r false; };
          };
          num += 1;
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

  func deserializeUser(map: Entity.AttributeMap): User {
    let v = RBT.get(map, Text.compare, "v");
    switch (v) {
      case (?v) { deserializeUserAttr(v) };
      case _ { Debug.trap("map not found") };
    };    
  };

  // TODO: `removeItemOwner`

  public shared({caller = caller}) func setUserData(canisterId: Principal, _user: User) {
    var db: DBPartition.DBPartition = actor(Principal.toText(canisterId));
    let key = Principal.toText(caller); // TODO: Should use binary encoding.
    db.put({sk = key; attributes = serializeUser(_user)});
  };

  // FIXME
  // TODO: Should also remove all his/her items?
  public shared({caller = caller}) func removeUser(canisterId: Principal) {
    var db: DBPartition.DBPartition = actor(Principal.toText(canisterId));
    let key = Principal.toText(caller);
    db.delete({sk = key});
  };

  let wrappedICPCanisterId = "o5d6i-5aaaa-aaaah-qbz2q-cai"; // https://github.com/C3-Protocol/wicp_docs
  // TODO: Or "utozz-siaaa-aaaam-qaaxq-cai": https://dank.ooo/wicp/ (seem to have less UX)\
  // TODO: Or "ryjl3-tyaaa-aaaaa-aaaba-cai" - native NNS ICP token.
  // Also consider using https://github.com/dfinity/examples/tree/master/motoko/invoice-canister
  // or https://github.com/research-ag/motoko-lib/blob/main/src/TokenHandler.mo

  public shared({caller = caller}) func pay(canisterId: Principal) {
  }
};
