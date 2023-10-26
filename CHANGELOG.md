## [0.8.3.8] - 2023-10-26
- fixed oversecured logs :-)

## [0.8.3.7] - 2023-09-14
- removed `secret` from logs

## [0.8.3.6] - 2023-08-10
- added `gateway.download_zipped_csvs_of_transfers(date: time_as_date, output_file_path: path_to_download)` (to get transfer fees :-) )

## [0.8.3.1] - 2023-06-28
- fixed internal passing errors

## [0.8.3] - 2023-06-27
- If response from Comgate API is error, but contain "transId", we do not raise exception but pass info up to stack

## [0.8.2] - 2023-06-20
- If ENV["COMGATE_MIN_LOG_LEVEL"] is set, calls and responses to Comgate are logged at that level. Otherwise `:debug` is used.

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


