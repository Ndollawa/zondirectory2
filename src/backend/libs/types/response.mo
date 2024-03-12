import Nat "mo:base/Nat";
import Time "mo:base/Time";
import Text "mo:base/Text";
// import Array "mo:base/Array";
// import Buffer "mo:base/Buffer";

module {
    public type Success<T> = {
        status : Text;
        statusCode : Nat;
        message : Text;
        timestamp : Time.Time;
        data : T;
    };
    public type Error = {
        status : Text;
        statusCode : Nat;
        message : Text;
        // path : Text;
        timestamp : Time.Time;
    };

};
