import Verify "mo:passport-client-dfinity/lib/Verifier";

module {
    // Don't verify users for sybil. It's useful for a test installation running locally.
    public let skipSybil = true;
    public let minimumScore = 20.0;
    // public let skipSybil = true | false;

    public let configScorer : Verify.Config = {
        scorerId = 134236531776317; //<NUMBER>  get it at https://scorer.gitcoin.co/
        scorerAPIKey = "myKey"; //"<KEY>" get it at https://scorer.gitcoin.co/
        scorerUrl = "https://api.scorer.gitcoin.co";
    };
};
