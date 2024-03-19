import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Principal "mo:base/Principal";

import Entity "mo:candb/Entity";
import Token "mo:icrc1/ICRC1/Canisters/Token";
import BTree "mo:stableheapbtreemap/BTree";
import ICRC1Types "mo:icrc1/ICRC1/Types";
// import MyCycles "mo:nacdb/Cycles";
import BTree "mo:stableheapbtreemap/BTree"; // TODO: Remove.
import RBT "mo:stable-rbtree/StableRBTree";
import StableBuffer "mo:StableBuffer/StableBuffer";
import Itertools "mo:itertools/Iter";

import Nac "mo:nacdb/NacDB";
import OpsQueue "mo:nacdb/OpsQueue"; // TODO: Remove.
import GUID "mo:nacdb/GUID";
import Reorder "mo:NacDBReorder/Reorder";
import CanDBPartition "canister:CanDBPartition";
import CanDBIndex "canister:CanDBIndex";
import Multi "mo:CanDBMulti/Multi";
import NacDBIndex "canister:NacDBIndex";
import NacDBPartition "canister:NacDBPartition";

import CanDBConfig "../../libs/configs/canDB.config";
import CanDBHelper "../../libs/utils/helpers/canDB.helper";
import fractions "../../libs/utils/helpers/fractions.helper";

import { deserializeItem; serializeItem } = "./types/item";
import { deserializeStream; serializeStream } = "./types/stream";
import StreamTypes "./types/stream";
import ItemTypes "types/item";

shared ({ caller = initialOwner }) actor class ItemService() = this {

    public type ItemWithoutOwner = ItemTypes.ItemWithoutOwner;
    public type Item = ItemTypes.Item;
    public type Streams = StreamTypes.Streams;
    stable var maxId : Nat = 0;
    // stable var rng: Prng.Seiran128 = Prng.Seiran128(); // WARNING: This is not a cryptographically secure pseudorandom number generator.
    stable let guidGen = GUID.init(Array.tabulate<Nat8>(16, func _ = 0));
    stable var owners = [initialOwner];

    stable let orderer = Reorder.createOrderer({ queueLengths = 20 });
    // TODO: Does it make sense to keep `Streams` in lib?Item; ItemWithoutOwner;
    // public type StreamsLinks = Nat;
    // public let STREAM_LINK_SUBITEMS : StreamsLinks = 0; // folder <-> sub-items
    // public let STREAM_LINK_SUBFOLDERS : StreamsLinks = 1; // folder <-> sub-folders
    // public let STREAM_LINK_COMMENTS : StreamsLinks = 2; // item <-> comments
    // public let STREAM_LINK_MAX : StreamsLinks = STREAM_LINK_COMMENTS;

    func checkCaller(caller : Principal) {
        if (Array.find(owners, func(e : Principal) : Bool { e == caller }) == null) {
            Debug.trap("order: not allowed");
        };
    };

    public shared ({ caller = caller }) func setOwners(_owners : [Principal]) : async () {
        checkCaller(caller);

        owners := _owners;
    };

    public query func getOwners() : async [Principal] { owners };

    stable var initialized : Bool = false;

    public shared ({ caller }) func init(_owners : [Principal]) : async () {
        checkCaller(caller);
        ignore MyCycles.topUpCycles(CanDBConfig.dbOptions.partitionCycles); // TODO: another number of cycles?
        if (initialized) {
            Debug.trap("already initialized");
        };

        owners := _owners;
        MyCycles.addPart(CanDBConfig.dbOptions.partitionCycles);
        initialized := true;
    };

    func _onlyItemOwner(caller : Principal, _item : Item) : async () {
        if (caller != _item.creator) {
            Debug.trap("not the item owner");
        };
    };

    public query func getItem(itemId : Nat) : async ?Item {
        let data = await CanDBPartition.getAttribute({ sk = "i/" # Nat.toText(itemId) }, "i");
        do ? { deserializeItem(data!) };
    };

    public shared ({ caller }) func createItemData(item : ItemWithoutOwner) : async (Principal, Nat) {
        let item2 : Item = { creator = caller; item };
        maxId += 1;
        let itemId = maxId;

        let key = "i/" # Nat.toText(itemId);
        let canisterId = await CanDBIndex.putAttributeWithPossibleDuplicate(
            "main",
            { sk = key; key = "i"; value = serializeItem(item2) },
        );
        return (canisterId, itemId);
    };

    // We don't check that owner exists: If a user lost his/her item, that's his/her problem, not ours.
    public shared ({ caller }) func setItemData(canisterId : Principal, _itemId : Nat, item : ItemWithoutOwner) : async () {
        let key = "i/" # Nat.toText(_itemId); // TODO: better encoding
        switch (await CanDBPartition.getAttribute({ sk = key }, "i")) {
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
                await CanDBPartition.putAttribute({
                    sk = key;
                    key = "i";
                    value = serializeItem(_item);
                });
            };
            case _ { Debug.trap("no item") };
        };
    };

    public shared ({ caller }) func setPostText(canisterId : Principal, _itemId : Nat, text : Text) : async () {
        let key = "i/" # Nat.toText(_itemId); // TODO: better encoding
        switch (await CanDBPartition.getAttribute({ sk = key }, "i")) {
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
                await CanDBPartition.putAttribute({
                    sk = key;
                    key = "t";
                    value = #text(text);
                });
            };
            case _ { Debug.trap("no item") };
        };
    };

    // TODO: Also remove voting data.
    public shared ({ caller }) func removeItem(canisterId : Principal, _itemId : Nat) : async () {
        // We first remove links, then the item itself, in order to avoid race conditions when displaying.
        // await Order.removeItemLinks((canisterId, _itemId));

        let key = "i/" # Nat.toText(_itemId);
        let ?oldItemRepr = await CanDBPartition.getAttribute({ sk = key }, "i") else {
            Debug.trap("no item");
        };
        let oldItem = deserializeItem(oldItemRepr);
        if (oldItem.item.communal) {
            Debug.trap("it's communal");
        };
        onlyItemOwner(caller, oldItem);
        await CanDBPartition.delete({ sk = key });
    };

    func addItemToList(theSubDB : Reorder.Order, itemToAdd : (Principal, Nat), side : { #beginning; #end; #zero }) : async* () {
        let scanItemInfo = Nat.toText(itemToAdd.1) # "@" # Principal.toText(itemToAdd.0);
        let theSubDB2 : Nac.OuterCanister = theSubDB.order.0;
        if (await theSubDB2.hasByOuter({ outerKey = theSubDB.reverse.1; sk = scanItemInfo })) {
            return; // prevent duplicate
        };
        // TODO: race

        let timeScanSK = if (side == #zero) {
            0;
        } else {
            let scanResult = await theSubDB2.scanLimitOuter({
                dir = if (side == #end) { #bwd } else { #fwd };
                outerKey = theSubDB.order.1;
                lowerBound = "";
                upperBound = "x";
                limit = 1;
                ascending = ?(if (side == #end) { false } else { true });
            });
            let timeScanSK = if (scanResult.results.size() == 0) {
                // empty list
                0;
            } else {
                let t = scanResult.results[0].0;
                let n = decodeInt(Text.fromIter(Itertools.takeWhile(t.chars(), func(c : Char) : Bool { c != '#' })));
                if (side == #end) { n + 1 } else { n - 1 };
            };
            timeScanSK;
        };

        let guid = GUID.nextGuid(guidGen);

        // TODO: race condition
        await* Reorder.add(
            guid,
            NacDBIndex,
            orderer,
            {
                order = theSubDB;
                key = timeScanSK;
                value = scanItemInfo;
            },
        );
    };

    // Public API //

    public shared ({ caller }) func addItemToFolder(
        catId : (Principal, Nat),
        itemId : (Principal, Nat),
        comment : Bool,
        side : { #beginning; #end }, // ignored unless adding to an owned folder
    ) : async () {

        // TODO: Race condition when adding an item.
        // TODO: Ensure that it is retrieved once.
        let ?folderItemData = await CanDBPartition.getAttribute({ sk = "i/" # Nat.toText(catId.1) }, "i") else {
            Debug.trap("cannot get folder item");
        };
        let folderItem = deserializeItem(folderItemData);

        if (not folderItem.item.communal) {
            // TODO: Remove `folderItem.item.details == #folder and`?
            _onlyItemOwner(caller, folderItem);
        };
        if (folderItem.item.details != #folder and not comment) {
            Debug.trap("not a folder");
        };
        let links = await* getStreamLinks(itemId, comment);
        await* addToStreams(catId, itemId, comment, links, itemId1, "st", "rst", #beginning);
        if (folderItem.item.details == #folder) {
            await* addToStreams(catId, itemId, comment, links, itemId1, "sv", "rsv", side);
        } else {
            await* addToStreams(catId, itemId, comment, links, itemId1, "sv", "rsv", #end);
        };
    };

    /// `key1` and `key2` are like `"st"` and `"rst"`
    func addToStreams(
        catId : (Principal, Nat),
        itemId : (Principal, Nat),
        comment : Bool, // FIXME: Use it.
        links : StreamsLinks,
        itemId1 : CanDBPartition.CanDBPartition,
        key1 : Text,
        key2 : Text,
        side : { #beginning; #end; #zero },
    ) : async* () {
        // Put into the beginning of time order.
        let streams1 = await* itemsStream(catId, key1);
        let streams2 = await* itemsStream(itemId, key2);
        let streamsVar1 : [var ?Reorder.Order] = switch (streams1) {
            case (?streams) { Array.thaw(streams) };
            case null { [var null, null, null] };
        };
        let streamsVar2 : [var ?Reorder.Order] = switch (streams2) {
            case (?streams) { Array.thaw(streams) };
            case null { [var null, null, null] };
        };
        let streams1t = switch (streams1) {
            case (?t) { t[links] };
            case (null) { null };
        };
        let stream1 = switch (streams1t) {
            case (?stream) { stream };
            case null {
                let v = await* Reorder.createOrder(GUID.nextGuid(guidGen), NacDBIndex, orderer);
                streamsVar1[links] := ?v;
                v;
            };
        };
        let streams2t = switch (streams2) {
            case (?t) { t[links] };
            case (null) { null };
        };
        let stream2 = switch (streams2t) {
            case (?stream) { stream };
            case null {
                let v = await* Reorder.createOrder(GUID.nextGuid(guidGen), NacDBIndex, orderer);
                streamsVar2[links] := ?v;
                v;
            };
        };
        await* addItemToList(stream1, itemId, side);
        await* addItemToList(stream2, catId, side);
        let itemData1 = serializeStreams(Array.freeze(streamsVar1));
        let itemData2 = serializeStreams(Array.freeze(streamsVar2));
        await itemId1.putAttribute({
            sk = "i/" # Nat.toText(catId.1);
            key = key1;
            value = itemData1;
        });
        await itemId1.putAttribute({
            sk = "i/" # Nat.toText(itemId.1);
            key = key2;
            value = itemData2;
        });
    };

    // public shared ({ caller }) func removeItemLinks(itemId : (Principal, Nat)) : async () {
    //   // checkCaller(caller); // FIXME: Uncomment.
    //   await* _removeItemLinks(itemId);
    // };

    func _removeItemLinks(itemId : (Principal, Nat)) : async* () {
        // FIXME: Also delete the other end.
        await* _removeStream("st", itemId);
        await* _removeStream("sv", itemId);
        await* _removeStream("rst", itemId);
        await* _removeStream("rsv", itemId);
        // await* _removeStream("stc", itemId);
        // await* _removeStream("vsc", itemId);
        // await* _removeStream("rstc", itemId);
        // await* _removeStream("rsvc", itemId);
    };

    /// Removes a stream
    /// TODO: Race condition on removing first links in only one direction. Check for more race conditions.
    func _removeStream(kind : Text, itemId : (Principal, Nat)) : async* () {
        let directStream = await* itemsStream(itemId, kind);
        switch (directStream) {
            case (?directStream) {
                for (index in directStream.keys()) {
                    switch (directStream[index]) {
                        case (?directOrder) {
                            let value = Nat.toText(itemId.1) # "@" # Principal.toText(itemId.0);
                            let reverseKind = if (kind.chars().next() == ?'r') {
                                let iter = kind.chars();
                                ignore iter.next();
                                Text.fromIter(iter);
                            } else {
                                "r" # kind;
                            };
                            // Delete links pointing to us:
                            // TODO: If more than 100_000?
                            let result = await directOrder.order.0.scanLimitOuter({
                                outerKey = directOrder.order.1;
                                lowerBound = "";
                                upperBound = "x";
                                dir = #fwd;
                                limit = 100_000;
                            });
                            for (p in result.results.vals()) {
                                let #text q = p.1 else {
                                    Debug.trap("order: programming error");
                                };
                                // TODO: Extract this to a function:
                                let words = Text.split(q, #char '@'); // a bit inefficient
                                let w1o = words.next();
                                let w2o = words.next();
                                let (?w1, ?w2) = (w1o, w2o) else {
                                    Debug.trap("order: programming error");
                                };
                                let ?w1i = Nat.fromText(w1) else {
                                    Debug.trap("order: programming error");
                                };
                                let reverseStream = await* itemsStream((Principal.fromText(w2), w1i), reverseKind);
                                switch (reverseStream) {
                                    case (?reverseStream) {
                                        switch (reverseStream[index]) {
                                            case (?reverseOrder) {
                                                Debug.print("q=" # q # ", parent=" # debug_show (w1i) # "@" # w2 # ", kind=" # reverseKind);
                                                await* Reorder.delete(GUID.nextGuid(guidGen), NacDBIndex, orderer, { order = reverseOrder; value });
                                            };
                                            case null {};
                                        };
                                    };
                                    case null {};
                                };
                            };
                            // Delete our own sub-DB (before deleting the item itself):
                            await directOrder.order.0.deleteSubDBOuter({
                                outerKey = directOrder.order.1;
                            });
                        };
                        case null {};
                    };
                };
            };
            case null {};
        };

    };

    func getStreamLinks(/*catId: (Principal, Nat),*/ itemId : (Principal, Nat), comment : Bool) : async* StreamsLinks {
        // let catId1: CanDBPartition.CanDBPartition = actor(Principal.toText(catId.0));
        // TODO: Ensure that item data is readed once per `addItemToFolder` call.
        let ?childItemData = await CanDBPartition.getAttribute({ sk = "i/" # Nat.toText(itemId.1) }, "i") else {
            // TODO: Keep doing for other folders after a trap?
            Debug.trap("cannot get child item");
        };
        let childItem = deserializeItem(childItemData);

        if (comment) {
            STREAM_LINK_COMMENTS;
        } else {
            switch (childItem.item.details) {
                case (#folder) { STREAM_LINK_SUBFOLDERS };
                case _ { STREAM_LINK_SUBITEMS };
            };
        };
    };

    /// `key1` and `key2` are like `"st"` and `"rst"`
    /// TODO: No need to return an option type
    func itemsStream(itemId : (Principal, Nat), key2 : Text) : async* ?Streams {
        let streamsData = await CanDBPartition.getAttribute({ sk = "i/" # Nat.toText(itemId.1) }, key2);
        let streams = switch (streamsData) {
            case (?data) {
                deserializeStreams(data);
            };
            case null {
                [null, null, null];
            };
        };
        ?streams;
    };

    // Test func
    public shared ({ caller }) func greet(text : Text) : async Text {
        Debug.print(text);
        return text;
    };

};
