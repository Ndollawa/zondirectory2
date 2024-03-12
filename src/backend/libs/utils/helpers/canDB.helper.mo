import Text "mo:base/Text";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Char "mo:base/Char";
import Nat64 "mo:base/Nat64";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Time "mo:base/Time";
import Bool "mo:base/Bool";

import xNat "mo:xtendedNumbers/NatX";
import CM "mo:candb/CanisterMap";
import Nac "mo:nacdb/NacDB";
import NacDBPartition "../../../../storage/NacDBPartition";
import RBT "mo:stable-rbtree/StableRBTree";
import Entity "mo:candb/Entity";
import Reorder "mo:NacDBReorder/Reorder";
import PassportConfig "../../configs/passport.config";

module {
  // let phoneNumberVerificationCanisterId = "gzqxf-kqaaa-aaaak-qakba-cai"; // https://docs.nfid.one/developer/credentials/mobile-phone-number-credential

  // We will use that "-XXX" < "XXX" for any hex number XXX.

  func _toLowerHexDigit(v : Nat) : Char {
    Char.fromNat32(
      Nat32.fromNat(
        if (v < 10) {
          Nat32.toNat(Char.toNat32('0')) + v;
        } else {
          Nat32.toNat(Char.toNat32('a')) - 10 + v;
        }
      )
    );
  };

  func _fromLowerHexDigit(c : Char) : Nat {
    Nat32.toNat(
      if (c <= '9') {
        Char.toNat32(c) - Char.toNat32('0');
      } else {
        Char.toNat32(c) - (Char.toNat32('a') - 10);
      }
    );
  };

  func encodeBlob(g : Blob) : Text {
    var result = "";
    for (b in g.vals()) {
      let b2 = Nat8.toNat(b);
      result #= Text.fromChar(_toLowerHexDigit(b2 / 16)) # Text.fromChar(_toLowerHexDigit(b2 % 16));
    };
    result;
  };

  func decodeBlob(t : Text) : Blob {
    let buf = Buffer.Buffer<Nat8>(t.size() / 2);
    let c = t.chars();
    label r loop {
      let ?upper = c.next() else {
        break r;
      };
      let ?lower = c.next() else {
        Debug.trap("decodeBlob: wrong hex number");
      };
      let b = Nat8.fromNat(_fromLowerHexDigit(upper) * 16 + _fromLowerHexDigit(lower));
      buf.add(b);
    };
    Blob.fromArray(Buffer.toArray(buf));
  };

  public func encodeNat(n : Nat) : Text {
    var n64 = Nat64.fromNat(n);
    let buf = Buffer.Buffer<Nat8>(8);
    for (i in Iter.range(0, 7)) {
      buf.add(Nat8.fromNat(Nat64.toNat(n64 % 256)));
      n64 >>= 8;
    };
    let blob = Blob.fromArray(Array.reverse(Buffer.toArray(buf)));
    encodeBlob(blob);
  };

  public func decodeNat(t : Text) : Nat {
    let blob = decodeBlob(t);
    var result : Nat64 = 0;
    for (b in blob.vals()) {
      result <<= 8;
      result += xNat.from8To64(b);
    };
    Nat64.toNat(result);
  };

  // For integers less than 2**64 have the same lexigraphical sort order as the argument.
  public func encodeInt(n : Int) : Text {
    assert n < 2 ** 64;
    if (n >= 0) {
      encodeNat(Int.abs(n));
    } else {
      "-" # encodeNat(2 ** 64 - Int.abs(n));
    };
  };

  public func decodeInt(t : Text) : Int {
    let iter = t.chars();
    if (iter.next() == ?'-') {
      -(2 ** 64 - decodeNat(Text.fromIter(iter)));
    } else {
      decodeNat(t);
    };
  };

  /// More user info: Voting ///

};
