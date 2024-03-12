// import Nat32 "mo:base/Nat32";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
// import Array "mo:base/Array";
// import Buffer "mo:base/Buffer";

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

    // public type Item = {
    //     owner : ItemOwner;
    //     communal : ItemType;
    //     creator : Principal;
    //      tags    : Array
    //     price : Float;
    //     locale : Text;
    //     title : Text;
    //     description : Text;
    //     details : {
    //         #link : Text;
    //         #message : ();
    //         #post : (); // save post text separately
    //         #folder : ();
    //     };
    // };

    public type ItemRequestInput = {

    };

    type ItemResult = {

    };

    type ScanItemResult = {
        items : [ItemResult];
        nextKey : ?Text;
    };

};
