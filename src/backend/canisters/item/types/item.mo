import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";

import Entity "mo:candb/Entity";

module {
    type ItemOwner = {
        #ItemWithoutOwner;
        #ItemWithOwner;
    };

    type ItemType = {
        #Communal;
        #Owned;
    };
    // FIXME: Communal will be a boolean flag, in order to deal with communal links and posts.
    public type ItemWithoutOwner = {
        communal : Bool;
        price : Float;
        locale : Text;
        title : Text;
        description : Text;
        details : {
            #link : Text;
            #message : ();
            #post : (); // save post text separately
            #folder : ();
        };
    };

    // TODO: Add `license` field?
    // TODO: Images.
    // TODO: Item version.
    public type Item = {
        creator : Principal;
        item : ItemWithoutOwner;
    };

    public type ItemRequestInput = {

    };

    type ItemResult = {

    };

    type ScanItemResult = {
        items : [ItemResult];
        nextKey : ?Text;
    };
    // FIXME: Communal will be a boolean flag, in order to deal with communal links and posts.
    let ITEM_TYPE_LINK = 0;
    let ITEM_TYPE_MESSAGE = 1;
    let ITEM_TYPE_POST = 2;
    let ITEM_TYPE_FOLDER = 3;

    public func serializeItem(item : Item) : async Entity.AttributeValue {
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
    public func deserializeItem(attr : Entity.AttributeValue) : async Item {
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

};
