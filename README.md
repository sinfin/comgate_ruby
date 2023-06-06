# comgate_ruby
Client for Comgate payment gateway

## API docs for Comgate
https://help.comgate.cz/docs/api-protokol

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add comgate_ruby

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install comgate_ruby

## Usage
### 1) set gateway object
  As singleton on app init or for each transaction:
  ```ruby
    gateway = Comgate::Gateway.new(merchant_gateway_id: ":comgate_id",
                                   test_calls: false,
                                   client_secret: ":comgate_secret")
  ```

### 2) prepare endpoint
 Comgate sends POST requests to your app about transactions updates. The URL of it needs to be setup in Comgate Client portal. At endpoint, just call `gateway.process_callback(params)`, which will return
    `{state: :paid, transaction_id: ":transID"}` (at least). See bullets 4) and 5) in Single payment process bellow.
### 3) call appropriate method
 (see bellow)

## Usecases
### Single payment process
1) Start transaction by `gateway.start_transaction(payment_data)`. Response is
      ```ruby
        #<Comgate::Response:0x00007f56800295a8
          @array=nil,
          @errors=nil,
          @hash={:code=>0, :message=>"OK", :transaction_id=>"AB12-CD34-EF56", :redirect_to=>"https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56"},
          @http_code=200,
          @params_conversion_hash=
            { .... }
          @redirect_to="https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56">
      ```
   Important part is `response.hash` :
      ```ruby
         {
           code: 0,
           message: "OK",
           transaction_id: "AB12-CD34-EF56"
           redirect_to: "https://payments.comgate.cz/client/instructions/index?id=AB12-CD34-EF56",
         }
      ```
2) Redirect user to `response.redirect_to` page (=> display Comgate form).
3) Client will (not) pay.
4) Comgate will send request to your defined endpoint about status change of transaction. Call `gateway.process_state_change(payload)`, which will return
  `{state: :paid, transaction_id: ":transID"}`(and maybe some more informations).
5) Now is Your time to handle payment (or other state like `cancelled`, `authorized`).

### Recurring payments
1) Use `gateway.start_recurring_transaction(payment_data)` and store `transaction_id`.
2) Create following payments `gateway.repeat_recurring_transaction(payment_data: new_payment_data)`, where `new_payment_data` includes `{payment: {reccurrence: { init_transaction_id: transaction_id } } }`. No redirection here. Price can change in each payment.
3) Handle status change like bullets 4) and 5) in single payment

### Preauthorized payments
1) Use `gateway.start_preauthorized_transaction(payment_data)` and store `transaction_id`.
2a) Confirm payment by `gateway.confirm_preauthorized_transaction(payment_data.merge({transaction_id: ":transID"}))` (price cannot exceed preauthorized amount)
2b) Cancel payment by `gateway.cancel_preauthorized_transaction(transaction_id: ":transID")`
3) Handle status change like bullets 4) and 5) in single payment

### Verification payments
1) Use `gateway.start_verification_transaction(payment_data)` and store `transaction_id`.
2) If payment is succesfull, bank will refund payment immediatelly.
3) Then you can create (repeat) payments like reccuring payments.

### Refund payment
1) Call `gateway.refund_transaction(payment_data.merge({transaction_id: ":transID"}))` (refunded value cannot exceed paid amount)
2) Handle status change like bullets 4) and 5) in single payment

### Cancel payment
1) Call `gateway.cancel_transaction(transaction_id: ":transID")`
2) Handle status change like bullets 4) and 5) in single payment

### Check payment state (ad-hoc)
0) The endpoint must be always implemented, this is just additional way to check payment state
1) Call `gateway.check_transaction(transaction_id: ":transID")`. It will return `{state: :paid, transaction_id: ":transID"}` and some more infos.
2) Handle status change like bullet 5) in single payment

### Get payment methods allowed to merchant
1) Call `gateway.allowed_payment_methods(params)`. It will return array of allowed payment methods in `response.array`.
   ```ruby
    [
      { id: "BANK_CZ_CS_P",
        name: "Česká spořitelna - PLATBA 24",
        description: "On-line platba pro majitele účtu u České spořitelny.",
        logo_url: "https://payments.comgate.cz/assets/images/logos/BANK_CZ_CS_P.png" },
      { id: "BANK_CZ_FB_P",
        name: "Fio banka - PayMyway",
        description: "On-line platba pro majitele účtu u Fio banky.",
        logo_url: "https://payments.comgate.cz/assets/images/logos/BANK_CZ_FB.png" }
    ]
   ```

### Get list of transfers for date
1) Call `gateway.transfers_from(date)`. Array of transfers will be returned in `response.array`.
    ```ruby
      [
        { transfer_id: 1234567,
          transfer_date: date,
          account_counter_party: "0/0000",
          account_outgoing: "123456789/0000",
          variable_symbol: "12345678"}
      ]
    ```

## Parameters
Structure of parameters is unchanged across most of methods, but you can leave out unused keys. You will get error if You  do not pass required key.
See `test/comgate/test_gateway.rb` for examples.
Also returned hash have consistent structure (very similar to input params)
Maximal mixed version looks like:
```ruby
  {
    code: 0, # output
    message: "OK", # output
    transfer_id: "1234-abcd-45678", # input/output
    test: true, # input (handle as test call)/ output (created by test call)
    state: :paid, # output (:pending, :paid, :cancelled, :authorized)
    merchant: {
      gateway_id: "some_id_from_comgate", # output (input is set at gateway init)
      target_shop_account: "12345678/1234", # input (change against default)/ output
    },
    payment: {
        amount_in_cents: 12_900, # input/output
        currency: "CZK", # input/output
        label: "Payment for 2 straws", # input/output
        reference_id: "our eshop order #1 reference", # input/output
        method: "CARD_CZ_CSOB_2", # input (selected method; or use "ALL") / output
        product_name: "product name ABC", # input/output
        fee: nil, # output ( if automatic deduction of the payment fee is set at Comgate)
        variable_symbol: 739_689_656, # output (so I acctually do not know where it came from)
        apple_pay_payload: "raw apple pay payload", # input
        dynamic_expiration: false, # input (see  https://help.comgate.cz/v1/docs/expirace-plateb )
        expiration_time: "10h", # input ( use "m" or  "h" or "d", but only one of them; allowed rage "30m".."7d")
        description: "Some description",
        reccurrence: { init_transaction_id: "12AD-dfsA-4568",
                       period: 1 } },
    },
    payer: {
        email: "payer1@gmail.com", # input/output
        phone: "+420778899", # input/output
        first_name: "John", # input - not used at Comgate
        last_name: "Doe", # input - not used at Comgate
        account_number: "account_num", # output
        account_name: "payer account name" # output
    },
    options: {
      country_code: "DE", # input (can restrict allowed  payment methods)
      language_code: "sk", # input
      shop_return_url: "https://example.com/return",
      callback_url: "https://example.com/callback"
    },
    # items are not used at Comgate
    items: [{ type: "ITEM",
              name: "Je to kulatý – Měsíční (6. 6. 2023 – 6. 7. 2023)",
              amount_in_cents: 9900,
              count: 1,
              vat_rate_percent: 21 }],
    headers: {} # not actually used now
  }
```

## Response
 Response returned from `gateway` call is `Comgate::Response` instance.
 You can check redirection `response.redirect? ? response.redirect_to : nil`.
 Most of the time, the response shoul be hash-like, stored in `response.hash`. But for lists there will be array in `response.array`.
 If there are errors from API call , they will be in `response.errors`. But note, that gateway will raise them and not return `Comgate::Response` instance.
 And you can also check `result.http_code` (which is surprisingly 200 from API errors)

## Errors
Connection errors or API error responses are raised as RuntimeError with message like ` "{:api=>[\"[Error #1309] incorrect amount\"]}"`.
Error Number and text can be found in `lib/comgate/response.rb`.
This may be refactored in future.

## One more thing
This gem extends `Hash` with methods `deep_symbolize_keys` and `deep_merge` (if needed).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/comgate_ruby.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
