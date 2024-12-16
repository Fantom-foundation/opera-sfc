import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

// npx hardhat ignition deploy ./ignition/modules/ConstantsManager.ts --network testnet --deployment-id manager --parameters ignition/params.json

export default buildModule('ConstantsManager', m => {
  const deployAccount = m.getAccount(0);

  const minSelfStake = m.getParameter('minSelfStake');
  const maxDelegatedRatio = m.getParameter('maxDelegatedRatio');
  const validatorCommissions = m.getParameter('validatorCommissions');
  const burntFeeShare = m.getParameter('burntFeeShare');
  const treasuryFeeShare = m.getParameter('treasuryFeeShare');
  const withdrawalPeriodEpochs = m.getParameter('withdrawalPeriodEpochs');
  const withdrawalPeriodTime = m.getParameter('withdrawalPeriodTime');
  const baseRewardPerSecond = m.getParameter('baseRewardPerSecond');
  const offlinePenaltyThresholdTime = m.getParameter('offlinePenaltyThresholdTime');
  const offlinePenaltyThresholdBlocksNumber = m.getParameter('offlinePenaltyThresholdBlocksNumber');
  const targetGasPowerPerSecond = m.getParameter('targetGasPowerPerSecond');
  const gasPriceBalancingCounterweights = m.getParameter('gasPriceBalancingCounterweights');
  const averageUptimeEpochWindow = m.getParameter('averageUptimeEpochWindow');
  const updateMinAverageUptime = m.getParameter('updateMinAverageUptime');

  const constantsManager = m.contract('ConstantsManager', [deployAccount]);

  m.call(constantsManager, 'updateMinSelfStake', [minSelfStake], { from: deployAccount });
  m.call(constantsManager, 'updateMaxDelegatedRatio', [maxDelegatedRatio], { from: deployAccount });
  m.call(constantsManager, 'updateValidatorCommission', [validatorCommissions], { from: deployAccount });
  m.call(constantsManager, 'updateBurntFeeShare', [burntFeeShare], { from: deployAccount });
  m.call(constantsManager, 'updateTreasuryFeeShare', [treasuryFeeShare], { from: deployAccount });
  m.call(constantsManager, 'updateWithdrawalPeriodEpochs', [withdrawalPeriodEpochs], { from: deployAccount });
  m.call(constantsManager, 'updateWithdrawalPeriodTime', [withdrawalPeriodTime], { from: deployAccount });
  m.call(constantsManager, 'updateBaseRewardPerSecond', [baseRewardPerSecond], { from: deployAccount });
  m.call(constantsManager, 'updateOfflinePenaltyThresholdTime', [offlinePenaltyThresholdTime], { from: deployAccount });
  m.call(constantsManager, 'updateOfflinePenaltyThresholdBlocksNum', [offlinePenaltyThresholdBlocksNumber], {
    from: deployAccount,
  });
  m.call(constantsManager, 'updateTargetGasPowerPerSecond', [targetGasPowerPerSecond], { from: deployAccount });
  m.call(constantsManager, 'updateGasPriceBalancingCounterweight', [gasPriceBalancingCounterweights], {
    from: deployAccount,
  });
  m.call(constantsManager, 'updateAverageUptimeEpochWindow', [averageUptimeEpochWindow], { from: deployAccount });
  m.call(constantsManager, 'updateMinAverageUptime', [updateMinAverageUptime], { from: deployAccount });

  return { constantsManager };
});
