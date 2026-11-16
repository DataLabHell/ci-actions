# Changelog

## [2.0.0](https://github.com/DataLabHell/ci-actions/compare/python/flyte-deploy-v1.0.1...python/flyte-deploy-v2.0.0) (2026-11-16)


### ⚠ BREAKING CHANGES

* **python/flyte-deploy:** `client-id` and `client-secret` are now required and the `vault-*` inputs are removed. Pass them from the org secrets:

### Features

* **python/flyte-deploy:** take the client credentials as inputs instead of vault ([0ad94a4](https://github.com/DataLabHell/ci-actions/commit/0ad94a49dd2c3db9030a7854b711b3c7626eedcf))

## [1.0.1](https://github.com/DataLabHell/ci-actions/compare/python/flyte-deploy-v1.0.0...python/flyte-deploy-v1.0.1) (2026-10-13)


### Bug Fixes

* **python/flyte-deploy:** use correct commit sha for pr not pr temp one ([5953256](https://github.com/DataLabHell/ci-actions/commit/5953256159fb30d6ee03fe3a34b9af1a430a3808))

## 1.0.0 (2026-09-16)


### Features

* add action for flyte workflows deploy ([3f5153a](https://github.com/DataLabHell/ci-actions/commit/3f5153a57353f52dc1c6c9af7c94deeac63e3392))


### Bug Fixes

* flyte always reads configfile ([5dba033](https://github.com/DataLabHell/ci-actions/commit/5dba033c2fd78b8d66feb1499e998445416affb7))
* lint ([869b488](https://github.com/DataLabHell/ci-actions/commit/869b488f350c91dc47270560c6e22c7a6aee9aae))
* missing clientid ([3e09cca](https://github.com/DataLabHell/ci-actions/commit/3e09cca376237e3e8ea908d30e8db36c6d3d880a))
* other missed settings for flyte auth ([a8c889c](https://github.com/DataLabHell/ci-actions/commit/a8c889c475b25e9a0f6163099d831696eed975f9))
* typo ([eff229a](https://github.com/DataLabHell/ci-actions/commit/eff229a7e9caa5e6020455316740ab8c3d3f2628))
