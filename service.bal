import ramith/payment_execution;
import ramith/fraud_check;
import ramith/payment_remediation;
import ballerina/time;
import ballerina/http;
import ballerina/log;

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
    boolean success;
    string description;
|};

type PaymentEvent record {
    string orderId;
    string message;
    string occurredAt = time:utcToString(time:utcNow());
    anydata|error payload?;
};

# A service representing a network-accessible API
# bound to port `9090`.
service / on new http:Listener(9090) {

    # A resource for payment initiation
    # + paymentInitation - the input string name
    # + return - result of the initiation or an error message
    resource function post payment/init(@http:Payload PaymentInitiation paymentInitation) returns PaymentInitiationResult|error {

        error? validationOutcome = validate(paymentInitation);
        _ = start emitPaymentEvent({
            orderId: paymentInitation.orderId,
            message: "payment rules evaluated",
            payload: validationOutcome
        });

        if validationOutcome is error {

            payment_remediation:Client paymentRemediationEp = check new (clientConfig = {
                auth: {
                    clientId: clientId,
                    clientSecret: clientSecret
                }
            });

            _ = start paymentRemediationEp->postPaymentRemediate(toRemediationRequest(paymentInitation));

            _ = start emitPaymentEvent({
                orderId: paymentInitation.orderId,
                message: "submitted for remediation",
                payload: paymentInitation
            });

            return {
                success: false,
                description: "payment init failed. submitted for remediation"
            };

        }

        payment_execution:Client payment_executionEp = check new (clientConfig = {
            auth: {
                clientId: clientId,
                clientSecret: clientSecret
            }
        });
        fraud_check:Client fraud_checkEp = check new (clientConfig = {
            auth: {
                clientId: clientId,
                clientSecret: clientSecret
            }
        });

        record {
            string orderId;
            float amount;
            string currency;
            string 'source;
        } paymentInformation = {
            orderId: paymentInitation.orderId,
            amount: paymentInitation.amount,
            currency: paymentInitation.currency,
            'source: paymentInitation.'source
        };

        future<fraud_check:FraudCheckResult|error> asyncFraudCheckResponse = start fraud_checkEp->postFraudCheck(payload = paymentInformation);
        _ = start emitPaymentEvent({
            orderId: paymentInitation.orderId,
            message: "payment submitted for fraud check"
        });

        future<payment_execution:PaymentResult|error> ayncPaymentExecutionResponse = start payment_executionEp->postPaymentExecute(payload = paymentInformation);
        _ = start emitPaymentEvent({
            orderId: paymentInitation.orderId,
            message: "payment submitted for execution"
        });

        fraud_check:FraudCheckResult|error fraudCheckResponse = wait asyncFraudCheckResponse;
        _ = start emitPaymentEvent({
            orderId: paymentInitation.orderId,
            message: "fraude check result received",
            payload: fraudCheckResponse
        });

        payment_execution:PaymentResult|error paymentExecutionResponse = wait ayncPaymentExecutionResponse;
        _ = start emitPaymentEvent({
            orderId: paymentInitation.orderId,
            message: "payment execution result received",
            payload: paymentExecutionResponse
        });

        return {
            success: true,
            description: "payment init successfull"
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

type PaymentRemediationRequest payment_remediation:PaymentRemediationRequest;

function toRemediationRequest(PaymentInitiation paymentInitiation) returns PaymentRemediationRequest => {
    orderId: paymentInitiation.orderId,
    amount: paymentInitiation.amount,
    currency: paymentInitiation.currency,
    'source: paymentInitiation.'source,
    description: paymentInitiation.description,
    receivedOn: time:utcToString(time:utcNow())
};

function emitPaymentEvent(PaymentEvent event) {
    log:printInfo("emiting payment event", paymentEvent = event.toString());
}
