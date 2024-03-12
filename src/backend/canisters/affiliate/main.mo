shared ({ caller = owner }) actor class Affiliate() = this {
    // TODO: Set maximum lengths on user nick, chirp length, etc.

    /// Affiliates ///

    // public shared({caller}) func setAffiliate(canister: Principal, buyerAffiliate: ?Principal, sellerAffiliate: ?Principal): async () {
    //   var db: CanDBPartition.CanDBPartition = actor(Principal.toText(canister));
    //   if (buyerAffiliate == null and sellerAffiliate == null) {
    //     await db.delete({sk = "a/" # Principal.toText(caller)});
    //   };
    //   let buyerAffiliateStr = switch (buyerAffiliate) {
    //     case (?user) { Principal.toText(user) };
    //     case (null) { "" }
    //   };
    //   let sellerAffiliateStr = switch (sellerAffiliate) {
    //     case (?user) { Principal.toText(user) };
    //     case (null) { "" }
    //   };
    //   // await db.put({sk = "a/" # Principal.toText(caller); attributes = [("v", #text (buyerAffiliateStr # "/" # sellerAffiliateStr))]});
    // };

};
