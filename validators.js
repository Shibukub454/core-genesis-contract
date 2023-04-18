const web3 = require("web3")
const RLP = require('rlp');

// Configure
const validators = [
  
   {
     "consensusAddr": "0x01Bca3615D24d3c638836691517b2B9b49b054B1",
     "feeAddr": "0x01Bca3615D24d3c638836691517b2B9b49b054B1",
   },
   {
     "consensusAddr": "0xa458499604A85E90225a14946f36368Ae24df16D",
     "feeAddr": "0xa458499604A85E90225a14946f36368Ae24df16D",
   },
   {
     "consensusAddr": "0x5E00C0D5C4C10d4c805aba878D51129A89d513e0",
     "feeAddr": "0x5E00C0D5C4C10d4c805aba878D51129A89d513e0",
   },
   {
     "consensusAddr": "0x1Cd652bC64Af3f09B490dAae27f46e53726ce230",
     "feeAddr": "0x1Cd652bC64Af3f09B490dAae27f46e53726ce230",
   },
   {
     "consensusAddr": "0xDA37ccECBB2D7C83aE27eE2BeBFE8EBCe162c600",
     "feeAddr": "0xDA37ccECBB2D7C83aE27eE2BeBFE8EBCe162c600",
   },
   {
    "consensusAddr": "0x0BF80E376f6B9D4C8377d7B45FA2622748f27027",
    "feeAddr": "0x0BF80E376f6B9D4C8377d7B45FA2622748f27027",
  },
  {
    "consensusAddr": "0x4e8baa8f9af84936d1272b52c6086ac1f2dfcb3e",
    "feeAddr": "0x4e8baa8f9af84936d1272b52c6086ac1f2dfcb3e",
  }
];

// ===============  Do not edit below ====
function generateExtradata(validators) {
  let extraVanity =Buffer.alloc(32);
  let validatorsBytes = extraDataSerialize(validators);
  let extraSeal =Buffer.alloc(65);
  return Buffer.concat([extraVanity,validatorsBytes,extraSeal]);
}

function extraDataSerialize(validators) {
  let n = validators.length;
  let arr = [];
  for (let i = 0;i<n;i++) {
    let validator = validators[i];
    arr.push(Buffer.from(web3.utils.hexToBytes(validator.consensusAddr)));
  }
  return Buffer.concat(arr);
}

function validatorUpdateRlpEncode(validators) {
  let n = validators.length;
  let vals = [];
  for (let i = 0;i<n;i++) {
    vals.push([
      validators[i].consensusAddr,
      validators[i].feeAddr,
    ]);
  }
  return web3.utils.bytesToHex(RLP.encode(vals));
}

extraValidatorBytes = generateExtradata(validators);
validatorSetBytes = validatorUpdateRlpEncode(validators);

exports = module.exports = {
  extraValidatorBytes: extraValidatorBytes,
  validatorSetBytes: validatorSetBytes,
}