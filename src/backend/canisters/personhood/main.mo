import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";

import Types "mo:passport-client-dfinity/lib/Types";
import V "mo:passport-client-dfinity/lib/Verifier";

import CanDBIndex "canister:CanDBIndex";
import ic_eth "canister:ic_eth";
import lib "../../utils/libs/helpers/canDB.helper";
import passportConfig "../../utils/configs/passport.config";

actor Personhood {
    /// Shared ///

    // TODO: canister hint for ethereumAddress
    func controlEthereumAddress(caller : Principal, address : Text) : async* () {
        let callerText = Principal.toText(caller);
        // TODO: race:
        let pa = await CanDBIndex.getFirstAttribute("user", { sk = address; key = "p" });
        switch (pa) {
            case (?(p, ? #text a)) {
                if (a != callerText) {
                    Debug.trap("attempt to use other's Ethereum address");
                };
            };
            case _ {
                // TODO: Optimize performance:
                ignore await CanDBIndex.putAttributeNoDuplicates(
                    "user",
                    { sk = address; key = "p"; value = #text callerText },
                );
            };
        };
    };

    // TODO: This function is unused
    public shared ({ caller }) func scoreBySignedEthereumAddress({
        address : Text;
        signature : Text;
        nonce : Text;
    }) : async Text {
        await* controlEthereumAddress(caller, address);
        // A real app would store the verified address somewhere instead of just returning the score to frontend.
        // Use `extractItemScoreFromBody` or `extractItemScoreFromJSON` to extract score.
        let body = await* V.scoreBySignedEthereumAddress({
            ic_eth;
            address;
            signature;
            nonce;
            config = passportConfig.configScorer;
            transform = removeHTTPHeaders;
        });
        let score = V.extractItemScoreFromBody(body);
        await CanDBIndex.setVotingData(
            caller,
            null,
            {
                // TODO: Provide partition hint.
                points = score;
                lastChecked = Time.now();
                ethereumAddress = address;
                config = passportConfig.configScorer;
            },
        );
        body;
    };

    public shared ({ caller }) func submitSignedEthereumAddressForScore({
        address : Text;
        signature : Text;
        nonce : Text;
    }) : async Text {
        await* controlEthereumAddress(caller, address);
        // A real app would store the verified address somewhere instead of just returning the score to frontend.
        // Use `extractItemScoreFromBody` or `extractItemScoreFromJSON` to extract score.
        let body = await* V.submitSignedEthereumAddressForScore({
            ic_eth;
            address;
            signature;
            nonce;
            config = passportConfig.configScorer;
            transform = removeHTTPHeaders;
        });
        let score = V.extractItemScoreFromBody(body);
        await CanDBIndex.setVotingData(
            caller,
            null,
            {
                // TODO: Provide partition hint, not `null`.
                points = score;
                lastChecked = Time.now();
                ethereumAddress = address;
                config = passportConfig.configScorer;
            },
        );
        body;
    };

    public shared func getEthereumSigningMessage() : async {
        message : Text;
        nonce : Text;
    } {
        await* V.getEthereumSigningMessage({
            transform = removeHTTPHeaders;
            config = passportConfig.configScorer;
        });
    };

    public shared query func removeHTTPHeaders(args : Types.TransformArgs) : async Types.HttpResponsePayload {
        V.removeHTTPHeaders(args);
    };
};
