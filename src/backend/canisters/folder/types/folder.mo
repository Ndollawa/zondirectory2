import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";

module {
    public type Folder = {
        id : Principal;
        name : Text;
        parent : Principal;
        children : Buffer.Buffer<Folder>;
    };
};
