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

    public shared query ({caller}) func getSuccessResponse<T>(data:T, statusCode:Nat,message:?Text){
        let msg = switch(message) {
            case(null) {return "Request was successful." };
            case(?value) { return value  };
        };
        let res:Success<T> = {
                status : "Success";
                statusCode : statusCode;
                message : msg;
                timestamp : Time.now();
                data : data;
        };
        return res;
    };

    public shared ({caller}) func getErrorResponse<T>(data:T, statusCode:Nat,message:?Text){
        let msg = switch(message) {
                    case(null) {return "Request was Unsuccessful." };
                    case(?value) { return value  };
                };
                let res:Error = {
                        status : "Error";
                        statusCode : statusCode;
                        message : msg;
                        timestamp : Time.now();
                };
                return res;
            };

};
