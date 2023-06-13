## [0.8.1] - 2023-06-13
- Allowed  `proxy_uri` param for Comgate::Gateway

## [0.8] - 2023-06-06
- Update to conform universal payment interface params (see Readme)
- BREAKING: change in repeating params `{transaction_id: "xxx", ....}` is now at `{payment: {reccurrence: { init_transaction_id: "xxx" } } }`

## [0.7.1] - 2023-04-27

- better handling errors not in "error" param from Comgate
- renamed  `check_state` to `check_transaction` (and keep backward compatibility)
- renamed  `process_payment_callback` to `process_callback` (and keep backward compatibility)

## [0.5.0] - 2023-04-20

- Initial release


