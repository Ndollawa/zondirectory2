import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Time "mo:base/Time";
import Principal "mo:base/Principal";

module Auth {
    type User = {
        id : Principal;
        // .
        // .
        // .
        // other attributes
    };

    type User = {
        id : Principal;
        userId : Principal;
        fisrtName : Text;
        lastName : Text;
        // age:Time.Date;
        // .
        // .
        // .
        // other attributes
    };
};
