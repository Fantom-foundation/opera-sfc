import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

// npx hardhat ignition deploy ./ignition/modules/NodeDriverAuth.ts --network testnet --deployment-id nodeDriverAuth --parameters ignition/params.json

export default buildModule('NodeDriverAuth', m => {
  const NodeDriverAuth = m.contract('NodeDriverAuth');
  return { NodeDriverAuth };
});
