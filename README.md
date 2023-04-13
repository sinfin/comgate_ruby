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
    gateway = Commgate::Gateway.new(merchant_gateway_id: ":comgate_id",
                                    test_calls: false,
                                    secret: ":comgate_secret")
  ```

### 2) prepare endpoint
 Comgate sends POST requests to your app about transactions updates. The URL of it needs to be setup in Comgate Client portal. At endpoint, just call `gateway.process_state_change(params)`, which will return
    `{state: :paid, transaction_id: ":transID"}` (at least). See bullets 4) and 5) in Single payment process bellow.
### 3) call appropriate method
 (see bellow)

## Usecases
### Single payment process
1) Start transaction by `gateway.start_transaction(payment_data)`. Response contains `transaction_id` and `redirect_to`.
2) Redirect user to `redirect_to` page (Comgate form).
3) Client will (not) pay.
4) Comgate will send request to your defined endpoint about status change of transaction. Call `gateway.process_state_change(payload)`, which will return
  `{state: :paid, transaction_id: ":transID"}`(and maybe some more informations).
5) Now is Your time to handle payment (or other state like `cancelled`, `authorized`).

### Reccuring payments
1) Use `gateway.start_reccuring_transaction(payment_data)` and store `transaction_id`.
2) Create following payments `gateway.repeat_transaction(transaction_id: ":transID", payment_data: payment_data }})`. No redirection here. Price can change in each payment.
3) Handle status change like bullets 4) and 5) in single payment

### Preauthorized payments
1) Use `gateway.start_preauthorized_transaction(payment_data)` and store `transaction_id`.
2a) Confirm payment by `gateway.authorize_transaction(transaction_id: ":transID", payment_data)` (price cannot exceed preauthorized amount)
2b) Cancel payment by `gateway.cancel_preauthorized_transaction(transaction_id: ":transID")`
3) Handle status change like bullets 4) and 5) in single payment

### Verification payments
1) Use `gateway.start_verfication_transaction(payment_data)` and store `transaction_id`.
2) If payment is succesfull, bank will refund payment immediatelly.
3) Then you can create (repeat) payments like reccuring payments.

### Refund payment
1) Call `gateway.refund_transaction(transaction_id: ":transID", payment_data)` (refunded value cannot exceed paid amount)
2) Handle status change like bullets 4) and 5) in single payment

### Cancel payment
1) Call `gateway.cancel_transaction(transaction_id: ":transID")`
2) Handle status change like bullets 4) and 5) in single payment

### Check payment state (ad-hoc)
0) The endpoint must be always implemented, this is just additional way to check payment state
1) Call `gateway.check_state(transaction_id: ":transID")`. It will return `{state: :paid, transaction_id: ":transID"}` and some more infos.
2) Handle status change like bullet 5) in single payment

### Get payment methods allowed to merchant
1) Call `gateway.allowed_payment_methods`. It will return array of allowed payment methods.
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
1) Call `gateway.transfers_from(date)`. Array of transfers will be returned.
    ```ruby
    [
      { transfer_id: 1234567,
        transfer_date: date,
        account_counter_party: "0/0000",
        account_outgoing: "123456789/0000",
        variable_symbol: "12345678"}
    ]

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/comgate_ruby.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
