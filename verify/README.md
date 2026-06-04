# Contract verification — Shannon explorer

`forge verify-contract` against the Shannon Blockscout API was not reachable from CI
(`Address is not a smart-contract` — the public verifier endpoint differs), so verify via the
explorer UI using the bundled Standard-JSON input.

## HajarGuardian v3 — `0x544578aCc02EA4BEA5CAaA3382A6d7AE52aAbc9c`

1. Open https://shannon-explorer.somnia.network/address/0x544578aCc02EA4BEA5CAaA3382A6d7AE52aAbc9c
2. **Contract → Verify & Publish → Solidity (Standard-JSON-Input)**.
3. Upload `verify/HajarGuardian.v3.standard-input.json`.
4. Settings:
   - Compiler: **v0.8.30**
   - Optimization: **Yes, 200 runs**
   - EVM version: **cancun**
   - Contract name: `src/HajarGuardian.sol:HajarGuardian`
5. Constructor args (ABI-encoded, no `0x`):
   ```
   000000000000000000000000037bb9c718f3f7fe5ecbdb0b600d607b52706776000000000000000000000000000000000000000000000000b24ac1afbcefc708
   ```
   = `constructor(0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776, 12847293847561029384)`

To regenerate the Standard-JSON input:

```bash
forge verify-contract 0x544578aCc02EA4BEA5CAaA3382A6d7AE52aAbc9c \
  src/HajarGuardian.sol:HajarGuardian \
  --compiler-version 0.8.30 --num-of-optimizations 200 \
  --constructor-args $(cast abi-encode "constructor(address,uint256)" \
    0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776 12847293847561029384) \
  --show-standard-json-input > verify/HajarGuardian.v3.standard-input.json
```
