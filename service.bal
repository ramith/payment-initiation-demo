import ballerina/http;

configurable string clientSecret = ?;

configurable string clientId = ?;

type SUPPORTED_CURRENCIES "USD"|"GBP"|"INR"|"EURO";

type PaymentInitiation record {|
    string orderId;
    float amount;
    string currency;
    string 'source;
    string description;
|};

type PaymentInitiationResult record {|
|};

# A service representing a network-accessible API
# bound to port `9090`.
service / on new http:Listener(9090) {

    # A resource for payment initiation
    # + paymentInitation - the input string name
    # + return - result of the initiation or an error message
    resource function post payment/init(@http:Payload PaymentInitiation paymentInitation) returns PaymentInitiationResult|error {

        error? validationOutcome = validate(paymentInitation);
        if validationOutcome is error {

        }

        return {

        };
    }
}

function validate(PaymentInitiation paymentInitation) returns error? {

    if paymentInitation.orderId.length() == 0 {
        return error("order id cannot be empty");
    }

    if paymentInitation.amount <= 0.05 {
        return error("payment is below miminum amount chargable by payment provider");
    }

    if !(paymentInitation.currency is SUPPORTED_CURRENCIES) {
        return error("unsupported currency");
    }
}

