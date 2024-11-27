import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// npx hardhat ignition deploy ./ignition/modules/NodeDriver.ts --network testnet --parameters ignition/params.json

export default buildModule("NodeDriver", (m) => {
  const nodeDriver = m.contract("NodeDriver");
  return { nodeDriver };
});