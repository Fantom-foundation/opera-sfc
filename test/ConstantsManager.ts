import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ConstantsManager } from '../typechain-types';

describe('ConstantsManager', () => {
  const fixture = async () => {
    const [owner, nonOwner] = await ethers.getSigners();
    const manager: ConstantsManager = await ethers.deployContract('ConstantsManager', [owner]);

    return {
      owner,
      nonOwner,
      manager,
    };
  };

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('Update min self-stake', () => {
    it('Should revert when not owner', async function () {
      await expect(this.manager.connect(this.nonOwner).updateMinSelfStake(1000)).to.be.revertedWithCustomError(
        this.manager,
        'OwnableUnauthorizedAccount',
      );
    });

    it('Should revert when value is too small', async function () {
      await expect(
        this.manager.connect(this.owner).updateMinSelfStake(100_000n * BigInt(1e18) - 1n),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooSmall');
    });

    it('Should revert when value is too large', async function () {
      await expect(
        this.manager.connect(this.owner).updateMinSelfStake(10_000_000n * BigInt(1e18) + 1n),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update min self-stake', async function () {
      const newValue = 1_000_000n * BigInt(1e18);
      await this.manager.connect(this.owner).updateMinSelfStake(newValue);
      expect(await this.manager.minSelfStake()).to.equal(newValue);
    });
  });

  describe('Update max delegated ratio', () => {
    it('Should revert when not owner', async function () {
      await expect(this.manager.connect(this.nonOwner).updateMaxDelegatedRatio(1000)).to.be.revertedWithCustomError(
        this.manager,
        'OwnableUnauthorizedAccount',
      );
    });

    it('Should revert when value is too small', async function () {
      await expect(
        this.manager.connect(this.owner).updateMaxDelegatedRatio(BigInt(1e18) - 1n),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooSmall');
    });

    it('Should revert when value is too large', async function () {
      await expect(
        this.manager.connect(this.owner).updateMaxDelegatedRatio(31n * BigInt(1e18) + 1n),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update max delegated ratio', async function () {
      const newValue = BigInt(1e18);
      await this.manager.connect(this.owner).updateMaxDelegatedRatio(newValue);
      expect(await this.manager.maxDelegatedRatio()).to.equal(newValue);
    });
  });

  describe('Update validator commission', () => {
    it('Should revert when not owner', async function () {
      await expect(this.manager.connect(this.nonOwner).updateValidatorCommission(1000)).to.be.revertedWithCustomError(
        this.manager,
        'OwnableUnauthorizedAccount',
      );
    });

    it('Should revert when value is too large', async function () {
      await expect(
        this.manager.connect(this.owner).updateValidatorCommission(BigInt(1e18) / 2n + 1n),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update validator commission', async function () {
      const newValue = BigInt(1e18) / 2n;
      await this.manager.connect(this.owner).updateValidatorCommission(newValue);
      expect(await this.manager.validatorCommission()).to.equal(newValue);
    });
  });

  describe('Update burnt fee share', () => {
    it('Should revert when not owner', async function () {
      await expect(this.manager.connect(this.nonOwner).updateBurntFeeShare(1000)).to.be.revertedWithCustomError(
        this.manager,
        'OwnableUnauthorizedAccount',
      );
    });

    it('Should revert when value is too large', async function () {
      // set treasury fee share to 60%
      await this.manager.connect(this.owner).updateTreasuryFeeShare((BigInt(1e18) * 60n) / 100n);

      // set burnt fee share to 50% -> should revert because exceeds 100%
      await expect(
        this.manager.connect(this.owner).updateBurntFeeShare((BigInt(1e18) * 50n) / 100n),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update burnt fee share', async function () {
      const newValue = BigInt(1e18) / 2n;
      await this.manager.connect(this.owner).updateBurntFeeShare(newValue);
      expect(await this.manager.burntFeeShare()).to.equal(newValue);
    });
  });

  describe('Update treasury fee share', () => {
    it('Should revert when not owner', async function () {
      await expect(this.manager.connect(this.nonOwner).updateTreasuryFeeShare(1000)).to.be.revertedWithCustomError(
        this.manager,
        'OwnableUnauthorizedAccount',
      );
    });

    it('Should revert when value is too large', async function () {
      // set burnt fee share to 40%
      await this.manager.connect(this.owner).updateBurntFeeShare((BigInt(1e18) * 40n) / 100n);

      // set treasury fee share to 61% -> should revert because exceeds 100%
      await expect(
        this.manager.connect(this.owner).updateTreasuryFeeShare((BigInt(1e18) * 61n) / 100n),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update treasury fee share', async function () {
      const newValue = BigInt(1e18) / 2n;
      await this.manager.connect(this.owner).updateTreasuryFeeShare(newValue);
      expect(await this.manager.treasuryFeeShare()).to.equal(newValue);
    });
  });

  describe('Update withdrawal period epochs', () => {
    it('Should revert when not owner', async function () {
      await expect(
        this.manager.connect(this.nonOwner).updateWithdrawalPeriodEpochs(1000),
      ).to.be.revertedWithCustomError(this.manager, 'OwnableUnauthorizedAccount');
    });

    it('Should revert when value is too small', async function () {
      await expect(this.manager.connect(this.owner).updateWithdrawalPeriodEpochs(1)).to.be.revertedWithCustomError(
        this.manager,
        'ValueTooSmall',
      );
    });

    it('Should revert when value is too large', async function () {
      await expect(this.manager.connect(this.owner).updateWithdrawalPeriodEpochs(101)).to.be.revertedWithCustomError(
        this.manager,
        'ValueTooLarge',
      );
    });

    it('Should succeed and update withdrawal period epochs', async function () {
      const newValue = 50;
      await this.manager.connect(this.owner).updateWithdrawalPeriodEpochs(newValue);
      expect(await this.manager.withdrawalPeriodEpochs()).to.equal(newValue);
    });
  });

  describe('Update withdrawal period time', () => {
    it('Should revert when not owner', async function () {
      await expect(this.manager.connect(this.nonOwner).updateWithdrawalPeriodTime(1000)).to.be.revertedWithCustomError(
        this.manager,
        'OwnableUnauthorizedAccount',
      );
    });

    it('Should revert when value is too small', async function () {
      await expect(
        this.manager.connect(this.owner).updateWithdrawalPeriodTime(86_400 - 1),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooSmall');
    });

    it('Should revert when value is too large', async function () {
      await expect(
        this.manager.connect(this.owner).updateWithdrawalPeriodTime(30 * 86_400 + 1),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update withdrawal period time', async function () {
      const newValue = 86_400;
      await this.manager.connect(this.owner).updateWithdrawalPeriodTime(newValue);
      expect(await this.manager.withdrawalPeriodTime()).to.equal(newValue);
    });
  });

  describe('Update base reward per second', () => {
    it('Should revert when not owner', async function () {
      await expect(this.manager.connect(this.nonOwner).updateBaseRewardPerSecond(1000)).to.be.revertedWithCustomError(
        this.manager,
        'OwnableUnauthorizedAccount',
      );
    });

    it('Should revert when value is too large', async function () {
      await expect(
        this.manager.connect(this.owner).updateBaseRewardPerSecond(32n * BigInt(1e18) + 1n),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update base reward per second', async function () {
      const newValue = BigInt(1e18);
      await this.manager.connect(this.owner).updateBaseRewardPerSecond(newValue);
      expect(await this.manager.baseRewardPerSecond()).to.equal(newValue);
    });
  });

  describe('Update offline penalty threshold time', () => {
    it('Should revert when not owner', async function () {
      await expect(
        this.manager.connect(this.nonOwner).updateOfflinePenaltyThresholdTime(1000),
      ).to.be.revertedWithCustomError(this.manager, 'OwnableUnauthorizedAccount');
    });

    it('Should revert when value is too small', async function () {
      await expect(
        this.manager.connect(this.owner).updateOfflinePenaltyThresholdTime(86_400 - 1),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooSmall');
    });

    it('Should revert when value is too large', async function () {
      await expect(
        this.manager.connect(this.owner).updateOfflinePenaltyThresholdTime(10 * 86_400 + 1),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update offline penalty threshold time', async function () {
      const newValue = 86_400;
      await this.manager.connect(this.owner).updateOfflinePenaltyThresholdTime(newValue);
      expect(await this.manager.offlinePenaltyThresholdTime()).to.equal(newValue);
    });
  });

  describe('Update offline penalty threshold blocks num', () => {
    it('Should revert when not owner', async function () {
      await expect(
        this.manager.connect(this.nonOwner).updateOfflinePenaltyThresholdBlocksNum(1000),
      ).to.be.revertedWithCustomError(this.manager, 'OwnableUnauthorizedAccount');
    });

    it('Should revert when value is too small', async function () {
      await expect(
        this.manager.connect(this.owner).updateOfflinePenaltyThresholdBlocksNum(99),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooSmall');
    });

    it('Should revert when value is too large', async function () {
      await expect(
        this.manager.connect(this.owner).updateOfflinePenaltyThresholdBlocksNum(1_000_001),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update offline penalty threshold blocks num', async function () {
      const newValue = 500;
      await this.manager.connect(this.owner).updateOfflinePenaltyThresholdBlocksNum(newValue);
      expect(await this.manager.offlinePenaltyThresholdBlocksNum()).to.equal(newValue);
    });
  });

  describe('Update average uptime epoch window', () => {
    it('Should revert when not owner', async function () {
      await expect(
        this.manager.connect(this.nonOwner).updateAverageUptimeEpochWindow(1000),
      ).to.be.revertedWithCustomError(this.manager, 'OwnableUnauthorizedAccount');
    });

    it('Should revert when value is too small', async function () {
      await expect(this.manager.connect(this.owner).updateAverageUptimeEpochWindow(9)).to.be.revertedWithCustomError(
        this.manager,
        'ValueTooSmall',
      );
    });

    it('Should revert when value is too large', async function () {
      await expect(
        this.manager.connect(this.owner).updateAverageUptimeEpochWindow(87_601),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update average uptime epoch window', async function () {
      const newValue = 50;
      await this.manager.connect(this.owner).updateAverageUptimeEpochWindow(newValue);
      expect(await this.manager.averageUptimeEpochWindow()).to.equal(newValue);
    });
  });

  describe('Update min average uptime', () => {
    it('Should revert when not owner', async function () {
      await expect(this.manager.connect(this.nonOwner).updateMinAverageUptime(1000)).to.be.revertedWithCustomError(
        this.manager,
        'OwnableUnauthorizedAccount',
      );
    });

    it('Should revert when value is too large', async function () {
      await expect(
        this.manager.connect(this.owner).updateMinAverageUptime((BigInt(1e18) * 9n) / 10n + 1n),
      ).to.be.revertedWithCustomError(this.manager, 'ValueTooLarge');
    });

    it('Should succeed and update min average uptime', async function () {
      const newValue = 95;
      await this.manager.connect(this.owner).updateMinAverageUptime(newValue);
      expect(await this.manager.minAverageUptime()).to.equal(newValue);
    });
  });

  describe('Update issued tokens recipient', () => {
    it('Should revert when not owner', async function () {
      await expect(
        this.manager.connect(this.nonOwner).updateIssuedTokensRecipient(this.nonOwner.address),
      ).to.be.revertedWithCustomError(this.manager, 'OwnableUnauthorizedAccount');
    });

    it('Should succeed and update issued tokens recipient', async function () {
      await this.manager.connect(this.owner).updateIssuedTokensRecipient(this.nonOwner);
      expect(await this.manager.issuedTokensRecipient()).to.equal(this.nonOwner);
    });
  });
});
