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

import CanDBConfig "../../libs/configs/canDB.config";
import CanDBHelper "../../libs/utils/helpers/canDB.helper";
import fractions "../../libs/utils/helpers/fractions.helper";

import { Item; ItemWithoutOwner } "types/item";

shared ({ caller = initialOwner }) actor class Item() = this {

    // FIXME: Communal will be a boolean flag, in order to deal with communal links and posts.
    let ITEM_TYPE_LINK = 0;
    let ITEM_TYPE_MESSAGE = 1;
    let ITEM_TYPE_POST = 2;
    let ITEM_TYPE_FOLDER = 3;

    // TODO: Does it make sense to keep `Streams` in lib?
    public type StreamsLinks = Nat;
    public let STREAM_LINK_SUBITEMS : StreamsLinks = 0; // folder <-> sub-items
    public let STREAM_LINK_SUBFOLDERS : StreamsLinks = 1; // folder <-> sub-folders
    public let STREAM_LINK_COMMENTS : StreamsLinks = 2; // item <-> comments
    public let STREAM_LINK_MAX : StreamsLinks = STREAM_LINK_COMMENTS;

    public type Streams = [?Reorder.Order];

    // TODO: messy order of the below functions

    public func serializeItem(item : Item) : Entity.AttributeValue {
        var buf = Buffer.Buffer<Entity.AttributeValuePrimitive>(8);
        buf.add(#int 0); // version
        buf.add(#bool(item.item.communal));
        buf.add(
            #int(
                switch (item.item.details) {
                    case (#link v) { ITEM_TYPE_LINK };
                    case (#message) { ITEM_TYPE_MESSAGE };
                    case (#post _) { ITEM_TYPE_POST };
                    case (#folder) { ITEM_TYPE_FOLDER };
                }
            )
        );
        buf.add(#text(Principal.toText(item.creator)));
        buf.add(#float(item.item.price));
        buf.add(#text(item.item.locale));
        buf.add(#text(item.item.title));
        buf.add(#text(item.item.description));
        switch (item.item.details) {
            case (#link v) {
                buf.add(#text v);
            };
            case _ {};
        };
        #tuple(Buffer.toArray(buf));
    };

    public func deserializeItem(attr : Entity.AttributeValue) : Item {
        var kind : Nat = 0;
        var creator : ?Principal = null;
        var communal = false;
        var price = 0.0;
        var locale = "";
        var title = "";
        var description = "";
        var details : { #none; #link; #message; #post; #folder } = #none;
        var link = "";
        let res = label r : Bool switch (attr) {
            case (#tuple arr) {
                var pos = 0;
                switch (arr[pos]) {
                    case (#int v) {
                        assert v == 0;
                    };
                    case _ { break r false };
                };
                pos += 1;
                switch (arr[pos]) {
                    case (#bool v) {
                        communal := v;
                    };
                    case _ { break r false };
                };
                pos += 1;
                switch (arr[pos]) {
                    case (#int v) {
                        kind := Int.abs(v);
                    };
                    case _ { break r false };
                };
                pos += 1;
                switch (arr[pos]) {
                    case (#text v) {
                        creator := ?Principal.fromText(v);
                    };
                    case _ { break r false };
                };
                pos += 1;
                switch (arr[pos]) {
                    case (#float v) {
                        price := v;
                    };
                    case _ { break r false };
                };
                pos += 1;
                switch (arr[pos]) {
                    case (#text v) {
                        locale := v;
                    };
                    case _ { break r false };
                };
                pos += 1;
                switch (arr[pos]) {
                    case (#text v) {
                        title := v;
                    };
                    case _ { break r false };
                };
                pos += 1;
                switch (arr[pos]) {
                    case (#text v) {
                        description := v;
                    };
                    case _ { break r false };
                };
                pos += 1;
                if (kind == ITEM_TYPE_LINK) {
                    switch (arr[pos]) {
                        case (#text v) {
                            link := v;
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
            Debug.trap("wrong item format");
        };
        let ?creator2 = creator else {
            Debug.trap("creator2: programming error");
        };
        {
            creator = creator2;
            item = {
                communal = communal;
                price = price;
                locale = locale;
                title = title;
                description = description;
                details = switch (kind) {
                    case (0) { #link link };
                    case (1) { #message };
                    case (2) { #post };
                    case (3) { #folder };
                    case _ { Debug.trap("wrong item format") };
                };
            };
        };
    };

    public func serializeStreams(streams : Streams) : Entity.AttributeValue {
        var buf = Buffer.Buffer<Entity.AttributeValuePrimitive>(18);
        for (item in streams.vals()) {
            switch (item) {
                case (?r) {
                    buf.add(#text(Principal.toText(Principal.fromActor(r.order.0))));
                    buf.add(#int(r.order.1));
                    buf.add(#text(Principal.toText(Principal.fromActor(r.reverse.0))));
                    buf.add(#int(r.reverse.1));
                };
                case null {
                    buf.add(#int(-1));
                };
            };
        };
        #tuple(Buffer.toArray(buf));
    };

    public func deserializeStreams(attr : Entity.AttributeValue) : Streams {
        let s = Buffer.Buffer<?Reorder.Order>(36);
        let #tuple arr = attr else {
            Debug.trap("programming error");
        };
        var i = 0;
        label w while (i != Array.size(arr)) {
            if (arr[i] == #int(-1)) {
                s.add(null);
                i += 1;
                continue w;
            };
            switch (arr[i], arr[i +1], arr[i +2], arr[i +3]) {
                case (#text c0, #int i0, #text c1, #int i1) {
                    i += 4;
                    s.add(
                        ?{
                            order = (actor (c0), Int.abs(i0));
                            reverse = (actor (c1), Int.abs(i1));
                        }
                    );
                };
                case _ {
                    Debug.trap("programming error");
                };
            };
        };

        Buffer.toArray(s);
    };

    public func onlyItemOwner(caller : Principal, _item : Item) {
        if (caller != _item.creator) {
            Debug.trap("not the item owner");
        };
    };

    public query func getItem(itemId : Nat) : async ?Item {
        let data = CanDBPartition.getAttribute({ sk = "i/" # Nat.toText(itemId) }, "i");
        do ? { deserializeItem(data!) };
    };

    public shared ({ caller }) func createItemData(item : ItemWithoutOwner) : async (Principal, Nat) {
        let item2 : Item = { creator = caller; item };
        let itemId = maxId;
        maxId += 1;
        let key = "i/" # Nat.toText(itemId);
        let canisterId = await CanDBIndex.putAttributeWithPossibleDuplicate(
            "backend",
            { sk = key; key = "i"; value = serializeItem(item2) },
        );
        (canisterId, itemId);
    };

    // We don't check that owner exists: If a user lost his/her item, that's his/her problem, not ours.
    public shared ({ caller }) func setItemData(canisterId : Principal, _itemId : Nat, item : ItemWithoutOwner) {
        var db : CanDBPartition.CanDBPartition = actor (Principal.toText(canisterId));
        let key = "i/" # Nat.toText(_itemId); // TODO: better encoding
        switch (await db.getAttribute({ sk = key }, "i")) {
            case (?oldItemRepr) {
                let oldItem = deserializeItem(oldItemRepr);
                if (caller != oldItem.creator) {
                    Debug.trap("can't change item owner");
                };
                let _item : Item = {
                    item = item;
                    creator = caller;
                    var streams = null;
                };
                if (_item.item.details != oldItem.item.details) {
                    Debug.trap("can't change item type");
                };
                if (oldItem.item.communal) {
                    Debug.trap("can't edit communal folder");
                };
                onlyItemOwner(caller, oldItem);
                await db.putAttribute({
                    sk = key;
                    key = "i";
                    value = serializeItem(_item);
                });
            };
            case _ { Debug.trap("no item") };
        };
    };

    public shared ({ caller }) func setPostText(canisterId : Principal, _itemId : Nat, text : Text) {
        var db : CanDBPartition.CanDBPartition = actor (Principal.toText(canisterId));
        let key = "i/" # Nat.toText(_itemId); // TODO: better encoding
        switch (await db.getAttribute({ sk = key }, "i")) {
            case (?oldItemRepr) {
                let oldItem = deserializeItem(oldItemRepr);
                if (caller != oldItem.creator) {
                    Debug.trap("can't change item owner");
                };
                onlyItemOwner(caller, oldItem);
                switch (oldItem.item.details) {
                    case (#post) {};
                    case _ { Debug.trap("not a post") };
                };
                await db.putAttribute({
                    sk = key;
                    key = "t";
                    value = #text(text);
                });
            };
            case _ { Debug.trap("no item") };
        };
    };

    // TODO: Also remove voting data.
    public shared ({ caller }) func removeItem(canisterId : Principal, _itemId : Nat) {
        // We first remove links, then the item itself, in order to avoid race conditions when displaying.
        // await Order.removeItemLinks((canisterId, _itemId));
        var db : CanDBPartition.CanDBPartition = actor (Principal.toText(canisterId));
        let key = "i/" # Nat.toText(_itemId);
        let ?oldItemRepr = await db.getAttribute({ sk = key }, "i") else {
            Debug.trap("no item");
        };
        let oldItem = deserializeItem(oldItemRepr);
        if (oldItem.item.communal) {
            Debug.trap("it's communal");
        };
        onlyItemOwner(caller, oldItem);
        await db.delete({ sk = key });
    };

    // Test func
    public shared ({ caller }) func(text : Text) : async Text {
        Debug.print(text);
        return text;
    };

};
