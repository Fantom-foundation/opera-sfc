import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// npx hardhat ignition deploy ./ignition/modules/SFC.ts --network testnet --parameters ignition/params.json

export default buildModule("SFC", (m) => {
  const sfc = m.contract("SFC");
  return { sfc };
});