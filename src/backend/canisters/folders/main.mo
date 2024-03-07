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

shared ({ caller = initialOwner }) actor class Folder() {

    // public shared ({ caller }) func find() {};
    // public shared ({ caller }) func findMany() {};
    // public shared ({ caller }) func create() {};
    // public shared ({ caller }) func createMany() {};
    // public shared ({ caller }) func update() {};
    // public shared ({ caller }) func updateMany() {};
    // public shared ({ caller }) func delete() {};
    // public shared ({ caller }) func deleteMany() {};

};
