import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Principal "mo:base/Principal";

import Entity "mo:candb/Entity";

import Reorder "mo:NacDBReorder/Reorder";

module {

    public type Streams = [?Reorder.Order];

    public func serializeStream(streams : Streams) : async Entity.AttributeValue {
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

    public func deserializeStream(attr : Entity.AttributeValue) : async Streams {
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

};
