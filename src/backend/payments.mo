import lib "lib";
import PST "canister:pst";
import Token "mo:icrc1/ICRC1/Canisters/Token";
import BTree "mo:btree/BTree";
import ICRC1Types "mo:icrc1/ICRC1/Types";
import Time "mo:base/Time";
import Principal "mo:base/Principal";
import CanDBPartition "../storage/CanDBPartition";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import fractions "./fractions";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";

actor class Payments() = this {
  stable var initialized: Bool = false;

  /// Incoming Payments ///

  public shared({ caller }) func init(): async () {
    if (initialized) {
      Debug.trap("already initialized");
    };

    founder := ?caller;

    initialized := true;
  };

  /// Owners ///

  stable var founder: ?Principal = null;

  func onlyMainOwner(caller: Principal) {
    if (?caller != founder) {
      Debug.trap("not the main owner");
    }
  };

  public shared({caller}) func setMainOwner(_founder: Principal) {
    onlyMainOwner(caller);

    founder := ?_founder;
  };

  public shared({caller}) func removeMainOwner() {
    onlyMainOwner(caller);
    
    founder := null;
  };

  let nativeIPCToken = "ryjl3-tyaaa-aaaaa-aaaba-cai"; // native NNS ICP token.
  // let wrappedICPCanisterId = "o5d6i-5aaaa-aaaah-qbz2q-cai"; // https://github.com/C3-Protocol/wicp_docs
  // let wrappedICPCanisterId = "utozz-siaaa-aaaam-qaaxq-cai"; // https://dank.ooo/wicp/ (seem to have less UX)
  // Also consider using https://github.com/dfinity/examples/tree/master/motoko/invoice-canister
  // or https://github.com/research-ag/motoko-lib/blob/main/src/TokenHandler.mo

  stable var ledger: Token.Token = actor(nativeIPCToken);

  /// Shares ///

  stable var salesOwnersShare = fractions.fdiv(1, 10); // 10%
  stable var upvotesOwnersShare = fractions.fdiv(1, 2); // 50%
  stable var uploadOwnersShare = fractions.fdiv(3, 20); // 15%
  stable var buyerAffiliateShare = fractions.fdiv(1, 10); // 10%
  stable var sellerAffiliateShare = fractions.fdiv(3, 20); // 15%

  public query func getSalesOwnersShare(): async fractions.Fraction { salesOwnersShare };
  public query func getUpvotesOwnersShare(): async fractions.Fraction { upvotesOwnersShare };
  public query func getUploadOwnersShare(): async fractions.Fraction { uploadOwnersShare };
  public query func getBuyerAffiliateShare(): async fractions.Fraction { buyerAffiliateShare };
  public query func getSellerAffiliateShare(): async fractions.Fraction { sellerAffiliateShare };

  public shared({caller}) func setSalesOwnersShare(_share: fractions.Fraction) {
    onlyMainOwner(caller);
    
    salesOwnersShare := _share;
  };

  public shared({caller}) func setUpvotesOwnersShare(_share: fractions.Fraction) {
    onlyMainOwner(caller);
    
    upvotesOwnersShare := _share;
  };

  public shared({caller}) func setUploadOwnersShare(_share: fractions.Fraction) {
    onlyMainOwner(caller);
    
    uploadOwnersShare := _share;
  };

  public shared({caller}) func setBuyerAffiliateShare(_share: fractions.Fraction) {
    onlyMainOwner(caller);
    
    buyerAffiliateShare := _share;
  };

  public shared({caller}) func setSellerAffiliateShare(_share: fractions.Fraction) {
    onlyMainOwner(caller);
    
    sellerAffiliateShare := _share;
  };

  /////////////////

  type IncomingPayment = {
    kind: { #payment; #donation };
    itemId: Nat;
    amount: ICRC1Types.Balance;
    var time: ?Time.Time;
  };

  // func serializePaymentAttr(payment: IncomingPayment): Entity.AttributeValue {
  //   var buf = Buffer.Buffer<Entity.AttributeValuePrimitive>(3);
  //   buf.add(#int (switch (payment.kind) {
  //     case (#payment) { 0 };
  //     case (#donation) { 1 };
  //   }));
  //   buf.add(#int (payment.itemId));
  //   buf.add(#int (payment.amount));
  //   #tuple (Buffer.toArray(buf));
  // };

  // func serializePayment(payment: IncomingPayment): [(Entity.AttributeKey, Entity.AttributeValue)] {
  //   [("v", serializePaymentAttr(payment))];
  // };

  // func deserializePaymentAttr(attr: Entity.AttributeValue): IncomingPayment {
  //   var kind: { #payment; #donation } = #payment;
  //   var itemId: Int = 0;
  //   var amount = 0;
  //   let res = label r: Bool switch (attr) {
  //     case (#tuple arr) {
  //       var pos = 0;
  //       while (pos < arr.size()) {
  //         switch (pos) {
  //           case (0) {
  //             switch (arr[pos]) {
  //               case (#int v) {
  //                 switch (v) {
  //                   case (0) { kind := #payment; };
  //                   case (1) { kind := #donation; };
  //                   case _ { break r false };
  //                 }
  //               };
  //               case _ { break r false };
  //             };
  //           };
  //           case (1) {
  //             switch (arr[pos]) {
  //               case (#int v) {
  //                 itemId := v;
  //               };
  //               case _ { break r false };
  //             };
  //           };
  //           case (2) {
  //             switch (arr[pos]) {
  //               case (#int v) {
  //                 amount := Int.abs(v);
  //               };
  //               case _ { break r false };
  //             };
  //           };
  //           case _ { break r false; };
  //         };
  //         pos += 1;
  //       };
  //       true;
  //     };
  //     case _ {
  //       false;
  //     };
  //   };
  //   if (not res) {
  //     Debug.trap("wrong user format");
  //   };
  //   {
  //     kind = kind;
  //     itemId = itemId;
  //     amount = amount;
  //   };    
  // };

  // func deserializePayment(map: Entity.AttributeMap): IncomingPayment {
  //   let v = RBT.get(map, Text.compare, "v");
  //   switch (v) {
  //     case (?v) { deserializePaymentAttr(v) };
  //     case _ { Debug.trap("map not found") };
  //   };    
  // };

  // TODO: clean space by removing smallest payments.
  stable var currentPayments: BTree.BTree<Principal, IncomingPayment> = BTree.init<Principal, IncomingPayment>(null); // TODO: Delete old ones.
  
  // TODO: clean space by removing smallest debts.
  stable var ourDebts: BTree.BTree<Principal, OutgoingPayment> = BTree.init<Principal, OutgoingPayment>(null);

  public query func getOurDebt(user: Principal): async Nat {
    switch (BTree.get(ourDebts, Principal.compare, user)) {
      case (?debt) { debt.amount };
      case (null) { 0 };
    };
  };

  func indebt(to: Principal, amount: Nat) {
    if (amount == 0) {
      return;
    };
    ignore BTree.update<Principal, OutgoingPayment>(ourDebts, Principal.compare, to, func (old: ?OutgoingPayment): OutgoingPayment {
      let sum = switch (old) {
        case (?old) { old.amount + amount };
        case (null) { amount };
      };
      { amount = sum; var time = null };
    });
  };

  // TODO: On non-existent payment it proceeds successful. Is it OK?
  func processPayment(paymentCanisterId: Principal, userId: Principal, _buyerAffiliate: ?Principal, _sellerAffiliate: ?Principal): async () {
    var db: CanDBPartition.CanDBPartition = actor(Principal.toText(paymentCanisterId)); // FIXME
    switch (BTree.get<Principal, IncomingPayment>(currentPayments, Principal.compare, userId)) {
      case (?payment) {
        let itemKey = "i/" # Nat.toText(payment.itemId);
        switch (await db.getAttribute({sk = itemKey}, "i")) {
          case (?itemRepr) {
            let item = lib.deserializeItem(itemRepr);
            let time = switch (payment.time) {
              case (?time) { time };
              case (null) {
                let time = Time.now();
                payment.time := ?time;
                ignore BTree.insert<Principal, IncomingPayment>(currentPayments, Principal.compare, userId, payment);
                time;
              };
            };
            let fee = await ledger.icrc1_fee();
            let result = await ledger.icrc1_transfer({
              from_subaccount = ?Principal.toBlob(userId);
              to = {owner = Principal.fromActor(this); subaccount = null};
              amount = payment.amount - fee;
              fee = null;
              memo = null;
              created_at_time = ?Nat64.fromNat(Int.abs(time)); // idempotent
            });
            switch (result) {
              case (#Ok _ or #Err (#Duplicate _)) {};
              case _ { Debug.trap("can't pay") };
            };
            let _shareholdersShare = fractions.mul(payment.amount, salesOwnersShare);
            recalculateShareholdersDebt(Int.abs(_shareholdersShare), _buyerAffiliate, _sellerAffiliate);
            let toAuthor = payment.amount - _shareholdersShare;
            indebt(item.creator, Int.abs(toAuthor));
          };
          case (null) {};
        };
        ignore BTree.delete<Principal, IncomingPayment>(currentPayments, Principal.compare, userId);
      };
      case (null) {};
    };
  };

  /// Dividents and Withdrawals ///

  var totalDividends = 0;
  var totalDividendsPaid = 0; // actually paid sum
  // TODO: Set a heavy transfer fee of the PST to ensure that `lastTotalDivedends` doesn't take much memory.
  stable var lastTotalDivedends: BTree.BTree<Principal, Nat> = BTree.init<Principal, Nat>(null);

  func _dividendsOwing(_account: Principal): async Nat {
    let lastTotal = switch (BTree.get(lastTotalDivedends, Principal.compare, _account)) {
      case (?value) { value };
      case (null) { 0 };
    };
    let _newDividends = Int.abs((totalDividends: Int) - lastTotal);
    // rounding down
    let balance = await PST.icrc1_balance_of({owner = _account; subaccount = null});
    let total = await PST.icrc1_total_supply();
    balance * _newDividends / total;
  };

  func recalculateShareholdersDebt(_amount: Nat, _buyerAffiliate: ?Principal, _sellerAffiliate: ?Principal) {
    // Affiliates are delivered by frontend.
    // address payable _buyerAffiliate = affiliates[msg.sender];
    // address payable _sellerAffiliate = affiliates[_author];
    var _shareHoldersAmount = _amount;
    switch (_buyerAffiliate) {
      case (?_buyerAffiliate) {
        let _buyerAffiliateAmount = Int.abs(fractions.mul(_amount, buyerAffiliateShare));
        indebt(_buyerAffiliate, _buyerAffiliateAmount);
        if (_shareHoldersAmount < _buyerAffiliateAmount) {
          Debug.trap("negative amount to pay");
        };
        _shareHoldersAmount -= _buyerAffiliateAmount;
      };
      case (null) {};
    };
    switch (_sellerAffiliate) {
      case (?_sellerAffiliate) {
        let _sellerAffiliateAmount = Int.abs(fractions.mul(_amount, sellerAffiliateShare));
        indebt(_sellerAffiliate, _sellerAffiliateAmount);
        if (_shareHoldersAmount < _sellerAffiliateAmount) {
          Debug.trap("negative amount to pay");
        };
        _shareHoldersAmount -= _sellerAffiliateAmount;
      };
      case (null) {};
    };
    totalDividends += _shareHoldersAmount;
  };

  /// Outgoing Payments ///

  type OutgoingPayment = {
    amount: ICRC1Types.Balance;
    var time: ?Time.Time;
  };

  public shared({caller}) func payout(subaccount: ?ICRC1Types.Subaccount) {
    switch (BTree.get<Principal, OutgoingPayment>(ourDebts, Principal.compare, caller)) {
      case (?payment) {
        let time = switch (payment.time) {
          case (?time) { time };
          case (null) {
            let time = Time.now();
            payment.time := ?time;
            time;
          }
        };
        let fee = await ledger.icrc1_fee();
        let result = await ledger.icrc1_transfer({
          from_subaccount = null;
          to = {owner = caller; subaccount = subaccount};
          amount = payment.amount - fee;
          fee = null;
          memo = null;
          created_at_time = ?Nat64.fromNat(Int.abs(time)); // idempotent
        });
        ignore BTree.delete<Principal, OutgoingPayment>(ourDebts, Principal.compare, caller);
      };
      case (null) {};
    }
  };
}