import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Time "mo:base/Time";
import Principal "mo:base/Principal";

module Auth {

  type User = {
    locale : Text;
    nick : Text;
    title : Text;
    description : Text;
    // TODO: long description
    link : Text;
  };

    type Profile = {
        fisrtName : Text;
        lastName : Text;
        // age:Time.Date;
        // .
        // .
        // .
        // other attributes
    };
};
