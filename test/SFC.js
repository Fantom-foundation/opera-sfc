const { BN, expectRevert } = require('@openzeppelin/test-helpers');
const chai = require('chai');
const { expect } = require('chai');
const chaiAsPromised = require('chai-as-promised');

chai.use(chaiAsPromised);
const UnitTestSFC = artifacts.require('UnitTestSFC');
const UnitTestSFCLib = artifacts.require('UnitTestSFCLib');
const SFCI = artifacts.require('SFCUnitTestI');
const NodeDriverAuth = artifacts.require('NodeDriverAuth');
const NodeDriver = artifacts.require('NodeDriver');
const NetworkInitializer = artifacts.require('UnitTestNetworkInitializer');
const StubEvmWriter = artifacts.require('StubEvmWriter');
const ConstantsManager = artifacts.require('UnitTestConstantsManager');

function amount18(n) {
    return new BN(web3.utils.toWei(n, 'ether'));
}

async function sealEpoch(sfc, duration, _validatorsMetrics = undefined) {
    let validatorsMetrics = _validatorsMetrics;
    const validatorIDs = (await sfc.lastValidatorID()).toNumber();

    if (validatorsMetrics === undefined) {
        validatorsMetrics = {};
        for (let i = 0; i < validatorIDs; i++) {
            validatorsMetrics[i] = {
                offlineTime: new BN('0'),
                offlineBlocks: new BN('0'),
                uptime: duration,
                originatedTxsFee: amount18('0'),
            };
        }
    }
    // unpack validator metrics
    const allValidators = [];
    const offlineTimes = [];
    const offlineBlocks = [];
    const uptimes = [];
    const originatedTxsFees = [];
    for (let i = 0; i < validatorIDs; i++) {
        allValidators.push(i + 1);
        offlineTimes.push(validatorsMetrics[i].offlineTime);
        offlineBlocks.push(validatorsMetrics[i].offlineBlocks);
        uptimes.push(validatorsMetrics[i].uptime);
        originatedTxsFees.push(validatorsMetrics[i].originatedTxsFee);
    }

    await sfc.advanceTime(duration);
    await sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees, 0);
    await sfc.sealEpochValidators(allValidators);
}

class BlockchainNode {
    constructor(sfc, minter) {
        this.validators = {};
        this.nextValidators = {};
        this.sfc = sfc;
        this.minter = minter;
    }

    async handle(tx) {
        const logs = tx.receipt.rawLogs;
        for (let i = 0; i < logs.length; i += 1) {
            if (logs[i].topics[0] === web3.utils.sha3('UpdateValidatorWeight(uint256,uint256)')) {
                const validatorID = web3.utils.toBN(logs[i].topics[1]);
                const weight = web3.utils.toBN(logs[i].data);
                if (weight.isZero()) {
                    delete this.nextValidators[validatorID.toString()];
                } else {
                    this.nextValidators[validatorID.toString()] = weight;
                }
            }
        }
    }

    async sealEpoch(duration, _validatorsMetrics = undefined) {
        let validatorsMetrics = _validatorsMetrics;
        const validatorIDs = Object.keys(this.validators);
        const nextValidatorIDs = Object.keys(this.nextValidators);
        if (validatorsMetrics === undefined) {
            validatorsMetrics = {};
            for (let i = 0; i < validatorIDs.length; i += 1) {
                validatorsMetrics[validatorIDs[i].toString()] = {
                    offlineTime: new BN('0'),
                    offlineBlocks: new BN('0'),
                    uptime: duration,
                    originatedTxsFee: amount18('0'),
                };
            }
        }
        // unpack validator metrics
        const offlineTimes = [];
        const offlineBlocks = [];
        const uptimes = [];
        const originatedTxsFees = [];
        for (let i = 0; i < validatorIDs.length; i += 1) {
            offlineTimes.push(validatorsMetrics[validatorIDs[i].toString()].offlineTime);
            offlineBlocks.push(validatorsMetrics[validatorIDs[i].toString()].offlineBlocks);
            uptimes.push(validatorsMetrics[validatorIDs[i].toString()].uptime);
            originatedTxsFees.push(validatorsMetrics[validatorIDs[i].toString()].originatedTxsFee);
        }

        await this.sfc.advanceTime(duration);
        await this.handle(await this.sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees, 0));
        await this.handle(await this.sfc.sealEpochValidators(nextValidatorIDs));
        this.validators = this.nextValidators;
        // clone this.nextValidators
        this.nextValidators = {};
        for (const vid in this.validators) {
            this.nextValidators[vid] = this.validators[vid];
        }
    }
}

const pubkey = '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc525f';
const pubkey1 = '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc5251';
const pubkey2 = '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc5252';

contract('SFC', async ([account1, account2]) => {
    let nodeIRaw;
    beforeEach(async () => {
        this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
        nodeIRaw = await NodeDriver.new();
        const evmWriter = await StubEvmWriter.new();
        this.nodeI = await NodeDriverAuth.new();
        this.sfcLib = await UnitTestSFCLib.new();
        const initializer = await NetworkInitializer.new();
        await initializer.initializeAll(12, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, account1);
        this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
    });

    describe('Nde', () => {
        it('Should migrate to New address', async () => {
            await this.nodeI.migrateTo(account1, { from: account1 });
        });

        it('Should not migrate if not owner', async () => {
            await expectRevert(this.nodeI.migrateTo(account2, { from: account2 }), 'Ownable: caller is not the owner');
        });

        it('Should not copyCode if not owner', async () => {
            await expectRevert(this.nodeI.copyCode('0x0000000000000000000000000000000000000000', account1, { from: account2 }), 'Ownable: caller is not the owner');
        });

        it('Should copyCode', async () => {
            await this.nodeI.copyCode(this.sfc.address, account1, { from: account1 });
        });

        it('Should update network version', async () => {
            await this.nodeI.updateNetworkVersion(1, { from: account1 });
        });

        it('Should not update network version if not owner', async () => {
            await expectRevert(this.nodeI.updateNetworkVersion(1, { from: account2 }), 'Ownable: caller is not the owner');
        });

        it('Should advance epoch', async () => {
            await this.nodeI.advanceEpochs(1, { from: account1 });
        });

        it('Should not set a new storage if not backend address', async () => {
            await expectRevert(nodeIRaw.setStorage(account1, web3.utils.soliditySha3('testKey'), web3.utils.soliditySha3('testValue'), { from: account1 }), 'caller is not the backend');
        });

        it('Should not advance epoch if not owner', async () => {
            await expectRevert(this.nodeI.advanceEpochs(1, { from: account2 }), 'Ownable: caller is not the owner');
        });

        it('Should not set backend if not backend address', async () => {
            await expectRevert(nodeIRaw.setBackend('0x0000000000000000000000000000000000000000', { from: account1 }), 'caller is not the backend');
        });

        it('Should not swap code if not backend address', async () => {
            await expectRevert(nodeIRaw.swapCode('0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', { from: account1 }), 'caller is not the backend');
        });

        it('Should not be possible add a Genesis Validator through NodeDriver if not called by Node', async () => {
            await expectRevert(nodeIRaw.setGenesisValidator(account1, 1, pubkey, 0, await this.sfc.currentEpoch(), Date.now(), 0, 0), 'not callable');
        });

        it('Should not be possible to deactivate a validator through NodeDriver if not called by Node', async () => {
            await expectRevert(nodeIRaw.deactivateValidator(0, 1), 'not callable');
        });

        it('Should not be possible to add a Genesis Delegation through NodeDriver if not called by node', async () => {
            await expectRevert(nodeIRaw.setGenesisDelegation(account2, 1, 100, 0, 0, 0, 0, 0, 1000), 'not callable');
        });

        it('Should not be possible to seal Epoch Validators through NodeDriver if not called by node', async () => {
            await expectRevert(nodeIRaw.sealEpochValidators([0, 1]), 'not callable');
        });

        it('Should not be possible to seal Epoch through NodeDriver if not called by node', async () => {
            await expectRevert(nodeIRaw.sealEpoch([0, 1], [0, 1], [0, 1], [0, 1]), 'not callable');
            await expectRevert(nodeIRaw.sealEpochV1([0, 1], [0, 1], [0, 1], [0, 1], 0), 'not callable');
        });
    });

    describe('Genesis Validator', () => {
        beforeEach(async () => {
            await this.sfc.enableNonNodeCalls();
            await expect(this.sfc.setGenesisValidator(account1, 1, pubkey, 1 << 3, await this.sfc.currentEpoch(), Date.now(), 0, 0)).to.be.fulfilled;
            await this.sfc.disableNonNodeCalls();
        });

        it('Set Genesis Validator with bad Status', async () => {
            await expect(this.sfc._syncValidator(1, false)).to.be.fulfilled;
        });

        it('should reject sealEpoch if not called by Node', async () => {
            await expect(this.sfc.sealEpoch([1], [1], [1], [1], 0, {
                from: account1,
            })).to.be.rejectedWith('caller is not the NodeDriverAuth contract');
        });

        it('should reject SealEpochValidators if not called by Node', async () => {
            await expect(this.sfc.sealEpochValidators([1], {
                from: account1,
            })).to.be.rejectedWith('caller is not the NodeDriverAuth contract');
        });
    });
});

contract('SFC', async ([firstValidator, secondValidator, thirdValidator]) => {
    beforeEach(async () => {
        this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
        const nodeIRaw = await NodeDriver.new();
        const evmWriter = await StubEvmWriter.new();
        this.nodeI = await NodeDriverAuth.new();
        const initializer = await NetworkInitializer.new();
        this.sfcLib = await UnitTestSFCLib.new();
        await initializer.initializeAll(0, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
        this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
        await this.sfc.rebaseTime();
        this.node = new BlockchainNode(this.sfc, firstValidator);
    });

    describe('Basic functions', () => {
        describe('Constants', () => {
            it('Returns current Epoch', async () => {
                expect((await this.sfc.currentEpoch()).toString()).to.equals('1');
            });

            it('Returns minimum amount to stake for a Validator', async () => {
                expect((await this.consts.minSelfStake()).toString()).to.equals('317500000000000000');
            });

            it('Returns the maximum ratio of delegations a validator can have', async () => {
                expect((await this.consts.maxDelegatedRatio()).toString()).to.equals('16000000000000000000');
            });

            it('Returns commission fee in percentage a validator will get from a delegation', async () => {
                expect((await this.consts.validatorCommission()).toString()).to.equals('150000000000000000');
            });

            it('Returns burntFeeShare', async () => {
                expect((await this.consts.burntFeeShare()).toString()).to.equals('200000000000000000');
            });

            it('Returns treasuryFeeShare', async () => {
                expect((await this.consts.treasuryFeeShare()).toString()).to.equals('100000000000000000');
            });

            it('Returns the ratio of the reward rate at base rate (without lockup)', async () => {
                expect((await this.consts.unlockedRewardRatio()).toString()).to.equals('300000000000000000');
            });

            it('Returns the minimum duration of a stake/delegation lockup', async () => {
                expect((await this.consts.minLockupDuration()).toString()).to.equals('1209600');
            });

            it('Returns the maximum duration of a stake/delegation lockup', async () => {
                expect((await this.consts.maxLockupDuration()).toString()).to.equals('31536000');
            });

            it('Returns the period of time that stake is locked', async () => {
                expect((await this.consts.withdrawalPeriodTime()).toString()).to.equals('604800');
            });

            it('Returns the number of epochs that stake is locked', async () => {
                expect((await this.consts.withdrawalPeriodEpochs()).toString()).to.equals('3');
            });

            it('Returns the version of the current implementation', async () => {
                expect((await this.sfc.version()).toString()).to.equals('0x333035');
            });

            it('Reverts on transfers', async () => {
                await expectRevert(web3.eth.sendTransaction({from: secondValidator, to: this.sfc.address, value: 1 }), 'transfers not allowed');
            });

            it('Should create a Validator and return the ID', async () => {
                await this.sfc.createValidator(pubkey, {
                    from: secondValidator,
                    value: amount18('10'),
                });
                const lastValidatorID = await this.sfc.lastValidatorID();

                expect(lastValidatorID.toString()).to.equals('1');
            });

            it('Should fail to create a Validator insufficient self-stake', async () => {
                await expectRevert(this.sfc.createValidator(pubkey, {
                    from: secondValidator,
                    value: 1,
                }), 'insufficient self-stake');
            });

            it('Should fail if pubkey is empty', async () => {
                await expectRevert(this.sfc.createValidator(web3.utils.stringToHex(''), {
                    from: secondValidator,
                    value: amount18('10'),
                }), 'malformed pubkey');
            });

            it('Should create two Validators and return the correct last validator ID', async () => {
                let lastValidatorID;
                await this.sfc.createValidator(pubkey, {
                    from: secondValidator,
                    value: amount18('10'),
                });
                lastValidatorID = await this.sfc.lastValidatorID();

                expect(lastValidatorID.toString()).to.equals('1');

                await this.sfc.createValidator(pubkey1, {
                    from: thirdValidator,
                    value: amount18('12'),
                });
                lastValidatorID = await this.sfc.lastValidatorID();
                expect(lastValidatorID.toString()).to.equals('2');
            });

            it('Should return Delegation', async () => {
                await this.sfc.createValidator(pubkey, {
                    from: secondValidator,
                    value: amount18('10'),
                });
                (await this.sfc.delegate(1, { from: secondValidator, value: 1 }));
            });

            it('Should reject if amount is insufficient for self-stake', async () => {
                expect((await this.consts.minSelfStake()).toString()).to.equals('317500000000000000');
                await expect(this.sfc.createValidator(pubkey, {
                    from: secondValidator,
                    value: amount18('0.3'),
                })).to.be.rejectedWith("VM Exception while processing transaction: reverted with reason string 'insufficient self-stake'");
            });

            it('Returns current Epoch', async () => {
                expect((await this.sfc.currentEpoch()).toString()).to.equals('1');
            });

            it('Should return current Sealed Epoch', async () => {
                expect((await this.sfc.currentSealedEpoch()).toString()).to.equals('0');
            });

            it('Should return Now()', async () => {
                const now = (await web3.eth.getBlock('latest')).timestamp;
                expect((await this.sfc.getBlockTime()).toNumber()).to.be.within(now - 100, now + 100);
            });

            it('Should return getTime()', async () => {
                const now = (await web3.eth.getBlock('latest')).timestamp;
                expect((await this.sfc.getTime()).toNumber()).to.be.within(now - 100, now + 100);
            });
        });

        describe('Initialize', () => {
            it('Should have been initialized with firstValidator', async () => {
                expect(await this.sfc.owner()).to.equals(firstValidator);
            });
        });

        describe('Ownable', () => {
            it('Should return the owner of the contract', async () => {
                expect(await this.sfc.owner()).to.equals(firstValidator);
            });

            it('Should return true if the caller is the owner of the contract', async () => {
                expect(await this.sfc.isOwner()).to.equals(true);
                expect(await this.sfc.isOwner({ from: thirdValidator })).to.equals(false);
            });

            it('Should return address(0) if owner leaves the contract without owner', async () => {
                expect(await this.sfc.owner()).to.equals(firstValidator);
                expect(await this.sfc.renounceOwnership());
                expect(await this.sfc.owner()).to.equals('0x0000000000000000000000000000000000000000');
            });

            it('Should transfer ownership to the new owner', async () => {
                expect(await this.sfc.owner()).to.equals(firstValidator);
                expect(await this.sfc.transferOwnership(secondValidator));
                expect(await this.sfc.owner()).to.equals(secondValidator);
            });

            it('Should not be able to transfer ownership if not owner', async () => {
                await expect(this.sfc.transferOwnership(secondValidator, { from: secondValidator })).to.be.rejectedWith(Error);
            });

            it('Should not be able to transfer ownership to address(0)', async () => {
                await expect(this.sfc.transferOwnership('0x0000000000000000000000000000000000000000')).to.be.rejectedWith(Error);
            });
        });

        describe('Events emitters', () => {
            it('Should call updateNetworkRules', async () => {
                await this.nodeI.updateNetworkRules('0x7b22446167223a7b224d6178506172656e7473223a357d2c2245636f6e6f6d79223a7b22426c6f636b4d6973736564536c61636b223a377d2c22426c6f636b73223a7b22426c6f636b476173486172644c696d6974223a313030307d7d');
            });

            it('Should call updateOfflinePenaltyThreshold', async () => {
                await this.consts.updateOfflinePenaltyThresholdTime(86400);
                await this.consts.updateOfflinePenaltyThresholdBlocksNum(1000);
            });
        });
    });
});

contract('SFC', async ([firstValidator, secondValidator, thirdValidator, firstDelegator, secondDelegator, thirdDelegator]) => {
    beforeEach(async () => {
        this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
        const nodeIRaw = await NodeDriver.new();
        const evmWriter = await StubEvmWriter.new();
        this.nodeI = await NodeDriverAuth.new();
        this.sfcLib = await UnitTestSFCLib.new();
        const initializer = await NetworkInitializer.new();
        await initializer.initializeAll(10, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
        this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
        await this.sfc.rebaseTime();
        this.node = new BlockchainNode(this.sfc, firstValidator);
    });

    describe('Prevent Genesis Call if not node', () => {
        it('Should not be possible add a Genesis Validator if called not by node', async () => {
            await expect(this.sfc.setGenesisValidator(secondValidator, 1, pubkey, 0, await this.sfc.currentEpoch(), Date.now(), 0, 0)).to.be.rejectedWith('caller is not the NodeDriverAuth contract');
        });

        it('Should not be possible add a Genesis Delegation if called not by node', async () => {
            await expect(this.sfc.setGenesisDelegation(firstDelegator, 1, 100, 0, 0, 0, 0, 0, 1000)).to.be.rejectedWith('caller is not the NodeDriverAuth contract');
        });
    });

    describe('Create validators', () => {
        it('Should create Validators', async () => {
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            await expect(this.sfc.createValidator(pubkey1, {
                from: secondValidator,
                value: amount18('15'),
            })).to.be.fulfilled;
            await expect(this.sfc.createValidator(pubkey2, {
                from: thirdValidator,
                value: amount18('20'),
            })).to.be.fulfilled;
        });

        it('Should return the right ValidatorID by calling getValidatorID', async () => {
            expect((await this.sfc.getValidatorID(firstValidator)).toString()).to.equals('0');
            expect((await this.sfc.getValidatorID(secondValidator)).toString()).to.equals('0');
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            expect((await this.sfc.getValidatorID(firstValidator)).toString()).to.equals('1');
            await expect(this.sfc.createValidator(pubkey1, {
                from: secondValidator,
                value: amount18('15'),
            })).to.be.fulfilled;
            expect((await this.sfc.getValidatorID(secondValidator)).toString()).to.equals('2');
            await expect(this.sfc.createValidator(pubkey2, {
                from: thirdValidator,
                value: amount18('20'),
            })).to.be.fulfilled;
            expect((await this.sfc.getValidatorID(thirdValidator)).toString()).to.equals('3');
        });

        it('Should not be able to stake if Validator not created yet', async () => {
            await expect(this.sfc.delegate(1, {
                from: firstDelegator,
                value: amount18('10'),
            })).to.be.rejectedWith("VM Exception while processing transaction: reverted with reason string 'validator doesn't exist'");
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;

            await expect(this.sfc.delegate(2, {
                from: secondDelegator,
                value: amount18('10'),
            })).to.be.rejectedWith("VM Exception while processing transaction: reverted with reason string 'validator doesn't exist'");
            await expect(this.sfc.createValidator(pubkey1, {
                from: secondValidator,
                value: amount18('15'),
            })).to.be.fulfilled;

            await expect(this.sfc.delegate(3, {
                from: thirdDelegator,
                value: amount18('10'),
            })).to.be.rejectedWith("VM Exception while processing transaction: reverted with reason string 'validator doesn't exist'");
            await expect(this.sfc.createValidator(pubkey2, {
                from: thirdValidator,
                value: amount18('20'),
            })).to.be.fulfilled;
        });

        it('Should stake with different delegators', async () => {
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            expect(await this.sfc.delegate(1, { from: firstDelegator, value: amount18('11') }));

            await expect(this.sfc.createValidator(pubkey1, {
                from: secondValidator,
                value: amount18('15'),
            })).to.be.fulfilled;
            expect(await this.sfc.delegate(2, { from: secondDelegator, value: amount18('10') }));

            await expect(this.sfc.createValidator(pubkey2, {
                from: thirdValidator,
                value: amount18('20'),
            })).to.be.fulfilled;
            expect(await this.sfc.delegate(3, { from: thirdDelegator, value: amount18('10') }));
            expect(await this.sfc.delegate(1, { from: firstDelegator, value: amount18('10') }));
        });

        it('Should return the amount of delegated for each Delegator', async () => {
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            await this.sfc.delegate(1, { from: firstDelegator, value: amount18('11') });
            expect((await this.sfc.getStake(firstDelegator, await this.sfc.getValidatorID(firstValidator))).toString()).to.equals('11000000000000000000');

            await expect(this.sfc.createValidator(pubkey1, {
                from: secondValidator,
                value: amount18('15'),
            })).to.be.fulfilled;
            await this.sfc.delegate(2, { from: secondDelegator, value: amount18('10') });
            expect((await this.sfc.getStake(secondDelegator, await this.sfc.getValidatorID(firstValidator))).toString()).to.equals('0');
            expect((await this.sfc.getStake(secondDelegator, await this.sfc.getValidatorID(secondValidator))).toString()).to.equals('10000000000000000000');

            await expect(this.sfc.createValidator(pubkey2, {
                from: thirdValidator,
                value: amount18('12'),
            })).to.be.fulfilled;
            await this.sfc.delegate(3, { from: thirdDelegator, value: amount18('10') });
            expect((await this.sfc.getStake(thirdDelegator, await this.sfc.getValidatorID(thirdValidator))).toString()).to.equals('10000000000000000000');

            await this.sfc.delegate(3, { from: firstDelegator, value: amount18('10') });

            expect((await this.sfc.getStake(thirdDelegator, await this.sfc.getValidatorID(firstValidator))).toString()).to.equals('0');
            expect((await this.sfc.getStake(firstDelegator, await this.sfc.getValidatorID(thirdValidator))).toString()).to.equals('10000000000000000000');
            await this.sfc.delegate(3, { from: firstDelegator, value: amount18('1') });
            expect((await this.sfc.getStake(firstDelegator, await this.sfc.getValidatorID(thirdValidator))).toString()).to.equals('11000000000000000000');
        });

        it('Should return the total of received Stake', async () => {
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            await this.sfc.delegate(1, { from: firstDelegator, value: amount18('11') });
            await this.sfc.delegate(1, { from: secondDelegator, value: amount18('8') });
            await this.sfc.delegate(1, { from: thirdDelegator, value: amount18('8') });
            const validator = await this.sfc.getValidator(1);

            expect(validator.receivedStake.toString()).to.equals('37000000000000000000');
        });

        it('Should return the total of received Stake', async () => {
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            await this.sfc.delegate(1, { from: firstDelegator, value: amount18('11') });
            await this.sfc.delegate(1, { from: secondDelegator, value: amount18('8') });
            await this.sfc.delegate(1, { from: thirdDelegator, value: amount18('8') });
            const validator = await this.sfc.getValidator(1);

            expect(validator.receivedStake.toString()).to.equals('37000000000000000000');
        });
    });
});

contract('SFC', async ([firstValidator, secondValidator, thirdValidator, firstDelegator, secondDelegator, thirdDelegator]) => {
    describe('Returns Validator', () => {
        let validator;
        beforeEach(async () => {
            this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
            const nodeIRaw = await NodeDriver.new();
            const evmWriter = await StubEvmWriter.new();
            this.nodeI = await NodeDriverAuth.new();
            this.sfcLib = await UnitTestSFCLib.new();
            const initializer = await NetworkInitializer.new();
            await initializer.initializeAll(12, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
            this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
            await this.sfc.rebaseTime();
            await this.sfc.enableNonNodeCalls();
            this.node = new BlockchainNode(this.sfc, firstValidator);
            await expect(this.sfc.createValidator(pubkey, { from: firstValidator, value: amount18('10') })).to.be.fulfilled;
            await this.sfc.delegate(1, { from: firstDelegator, value: amount18('11') });
            await this.sfc.delegate(1, { from: secondDelegator, value: amount18('8') });
            await this.sfc.delegate(1, { from: thirdDelegator, value: amount18('8') });
            validator = await this.sfc.getValidator(1);
        });

        it('Should returns Validator\' status ', async () => {
            expect(validator.status.toString()).to.equals('0');
        });

        it('Should returns Validator\' Deactivated Time', async () => {
            expect(validator.deactivatedTime.toString()).to.equals('0');
        });

        it('Should returns Validator\' Deactivated Epoch', async () => {
            expect(validator.deactivatedEpoch.toString()).to.equals('0');
        });

        it('Should returns Validator\'s Received Stake', async () => {
            expect(validator.receivedStake.toString()).to.equals('37000000000000000000');
        });

        it('Should returns Validator\'s Created Epoch', async () => {
            expect(validator.createdEpoch.toString()).to.equals('13');
        });

        it('Should returns Validator\'s Created Time', async () => {
            const now = (await web3.eth.getBlock('latest')).timestamp;
            expect(validator.createdTime.toNumber()).to.be.within(now - 5, now + 5);
        });

        it('Should returns Validator\'s Auth (address)', async () => {
            expect(validator.auth.toString()).to.equals(firstValidator);
        });
    });

    describe('EpochSnapshot', () => {
        let validator;
        beforeEach(async () => {
            this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
            const nodeIRaw = await NodeDriver.new();
            const evmWriter = await StubEvmWriter.new();
            this.nodeI = await NodeDriverAuth.new();
            this.sfcLib = await UnitTestSFCLib.new();
            const initializer = await NetworkInitializer.new();
            await initializer.initializeAll(12, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
            this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
            await this.sfc.rebaseTime();
            await this.sfc.enableNonNodeCalls();
            this.node = new BlockchainNode(this.sfc, firstValidator);
            await expect(this.sfc.createValidator(pubkey, { from: firstValidator, value: amount18('10') })).to.be.fulfilled;
            await this.sfc.delegate(1, { from: firstDelegator, value: amount18('11') });
            await this.sfc.delegate(1, { from: secondDelegator, value: amount18('8') });
            await this.sfc.delegate(1, { from: thirdDelegator, value: amount18('8') });
            validator = await this.sfc.getValidator(1);
        });

        it('Returns stashedRewardsUntilEpoch', async () => {
            expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('12'));
            expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('13'));
            await this.sfc.sealEpoch([100, 101, 102], [100, 101, 102], [100, 101, 102], [100, 101, 102], 0);
            expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('13'));
            expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('14'));
            await this.sfc.sealEpoch(
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                0,
            );
            await this.sfc.sealEpoch(
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                0,
            );
            await this.sfc.sealEpoch(
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                0,
            );
            await this.sfc.sealEpoch(
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                0,
            );
            expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('17'));
            expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('18'));
        });
    });
    describe('Methods tests', async () => {
        beforeEach(async () => {
            this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
            const nodeIRaw = await NodeDriver.new();
            const evmWriter = await StubEvmWriter.new();
            this.nodeI = await NodeDriverAuth.new();
            this.sfcLib = await UnitTestSFCLib.new();
            const initializer = await NetworkInitializer.new();
            await initializer.initializeAll(10, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
            this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
            await this.sfc.rebaseTime();
            await this.sfc.enableNonNodeCalls();
            this.node = new BlockchainNode(this.sfc, firstValidator);
        });
        it('checking createValidator function', async () => {
            expect(await this.sfc.lastValidatorID.call()).to.be.bignumber.equal(new BN('0'));
            await expectRevert(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('0.3175')
                    .sub(new BN(1)),
            }), 'insufficient self-stake');
            await this.node.handle(await this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('0.3175'),
            }));
            await expectRevert(this.sfc.createValidator(pubkey1, {
                from: firstValidator,
                value: amount18('0.3175'),
            }), 'validator already exists');
            await this.node.handle(await this.sfc.createValidator(pubkey1, {
                from: secondValidator,
                value: amount18('0.5'),
            }));

            expect(await this.sfc.lastValidatorID.call()).to.be.bignumber.equal(new BN('2'));
            expect(await this.sfc.totalStake.call()).to.be.bignumber.equal(amount18('0.8175'));

            const firstValidatorID = await this.sfc.getValidatorID(firstValidator);
            const secondValidatorID = await this.sfc.getValidatorID(secondValidator);
            expect(firstValidatorID).to.be.bignumber.equal(new BN('1'));
            expect(secondValidatorID).to.be.bignumber.equal(new BN('2'));

            expect(await this.sfc.getValidatorPubkey(firstValidatorID)).to.equal(pubkey);
            expect(await this.sfc.getValidatorPubkey(secondValidatorID)).to.equal(pubkey1);

            const firstValidatorObj = await this.sfc.getValidator.call(firstValidatorID);
            const secondValidatorObj = await this.sfc.getValidator.call(secondValidatorID);

            // check first validator object
            expect(firstValidatorObj.receivedStake).to.be.bignumber.equal(amount18('0.3175'));
            expect(firstValidatorObj.createdEpoch).to.be.bignumber.equal(new BN('11'));
            expect(firstValidatorObj.auth).to.equal(firstValidator);
            expect(firstValidatorObj.status).to.be.bignumber.equal(new BN('0'));
            expect(firstValidatorObj.deactivatedTime).to.be.bignumber.equal(new BN('0'));
            expect(firstValidatorObj.deactivatedEpoch).to.be.bignumber.equal(new BN('0'));

            // check second validator object
            expect(secondValidatorObj.receivedStake).to.be.bignumber.equal(amount18('0.5'));
            expect(secondValidatorObj.createdEpoch).to.be.bignumber.equal(new BN('11'));
            expect(secondValidatorObj.auth).to.equal(secondValidator);
            expect(secondValidatorObj.status).to.be.bignumber.equal(new BN('0'));
            expect(secondValidatorObj.deactivatedTime).to.be.bignumber.equal(new BN('0'));
            expect(secondValidatorObj.deactivatedEpoch).to.be.bignumber.equal(new BN('0'));

            // check created delegations
            expect(await this.sfc.getStake.call(firstValidator, firstValidatorID)).to.be.bignumber.equal(amount18('0.3175'));
            expect(await this.sfc.getStake.call(secondValidator, secondValidatorID)).to.be.bignumber.equal(amount18('0.5'));

            // check fired node-related logs
            expect(Object.keys(this.node.nextValidators).length).to.equal(2);
            expect(this.node.nextValidators[firstValidatorID.toString()]).to.be.bignumber.equal(amount18('0.3175'));
            expect(this.node.nextValidators[secondValidatorID.toString()]).to.be.bignumber.equal(amount18('0.5'));
        });

        it('checking sealing epoch', async () => {
            await this.node.handle(await this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('0.3175'),
            }));
            await expect(this.sfc.createValidator(pubkey, {
                from: secondValidator,
                value: amount18('0.6825'),
            })).to.be.rejectedWith('already used');
            await this.node.handle(await this.sfc.createValidator(pubkey1, {
                from: secondValidator,
                value: amount18('0.6825'),
            }));

            await this.node.sealEpoch(new BN('100'));

            const firstValidatorID = await this.sfc.getValidatorID(firstValidator);
            const secondValidatorID = await this.sfc.getValidatorID(secondValidator);
            expect(firstValidatorID).to.be.bignumber.equal(new BN('1'));
            expect(secondValidatorID).to.be.bignumber.equal(new BN('2'));

            const firstValidatorObj = await this.sfc.getValidator.call(firstValidatorID);
            const secondValidatorObj = await this.sfc.getValidator.call(secondValidatorID);

            await this.node.handle(await this.sfc.delegate(firstValidatorID, {
                from: firstValidator,
                value: amount18('0.1'),
            }));
            await expect(this.sfc.createValidator(pubkey, {
                from: thirdValidator,
                value: amount18('0.4'),
            })).to.be.rejectedWith('already used');
            await expect(this.sfc.createValidator(pubkey1, {
                from: thirdValidator,
                value: amount18('0.4'),
            })).to.be.rejectedWith('already used');
            await this.node.handle(await this.sfc.createValidator(pubkey2, {
                from: thirdValidator,
                value: amount18('0.4'),
            }));
            const thirdValidatorID = await this.sfc.getValidatorID(thirdValidator);

            // check fired node-related logs
            expect(Object.keys(this.node.validators).length).to.equal(2);
            expect(this.node.validators[firstValidatorID.toString()]).to.be.bignumber.equal(amount18('0.3175'));
            expect(this.node.validators[secondValidatorID.toString()]).to.be.bignumber.equal(amount18('0.6825'));
            expect(Object.keys(this.node.nextValidators).length).to.equal(3);
            expect(this.node.nextValidators[firstValidatorID.toString()]).to.be.bignumber.equal(amount18('0.4175'));
            expect(this.node.nextValidators[secondValidatorID.toString()]).to.be.bignumber.equal(amount18('0.6825'));
            expect(this.node.nextValidators[thirdValidatorID.toString()]).to.be.bignumber.equal(amount18('0.4'));
        });

        it('balances gas price', async () => {
            await this.consts.updateGasPriceBalancingCounterweight(24 * 60 * 60);
            await this.sfc.rebaseTime();
            await this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('1.0'),
            });

            await this.consts.updateTargetGasPowerPerSecond(1000);

            await this.sfc.sealEpoch([1], [1], [1], [1], 1000);
            await this.sfc.sealEpochValidators([1]);

            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('95000000000'));

            await this.sfc.advanceTime(1);
            await this.sfc.sealEpoch([1], [1], [1], [1], 1000);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('94999998901'));

            await this.sfc.advanceTime(2);
            await this.sfc.sealEpoch([1], [1], [1], [1], 2000);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('94999997802'));

            await this.sfc.advanceTime(1000);
            await this.sfc.sealEpoch([1], [1], [1], [1], 1000000);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('94999996715'));

            await this.sfc.advanceTime(1000);
            await this.sfc.sealEpoch([1], [1], [1], [1], 666666);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('94637676437'));

            await this.sfc.advanceTime(1000);
            await this.sfc.sealEpoch([1], [1], [1], [1], 1500000);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('95179080284'));

            await this.sfc.advanceTime(1);
            await this.sfc.sealEpoch([1], [1], [1], [1], 666);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('95178711617'));

            await this.sfc.advanceTime(1);
            await this.sfc.sealEpoch([1], [1], [1], [1], 1500);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('95179260762'));

            await this.sfc.advanceTime(1000);
            await this.sfc.sealEpoch([1], [1], [1], [1], 10000000000);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('99938223800'));

            await this.sfc.advanceTime(10000);
            await this.sfc.sealEpoch([1], [1], [1], [1], 0);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('94941312610'));

            await this.sfc.advanceTime(100);
            await this.sfc.sealEpoch([1], [1], [1], [1], 200000);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('95051069157'));

            await this.sfc.advanceTime(100);
            await this.sfc.sealEpoch([1], [1], [1], [1], 50000);
            await this.sfc.sealEpochValidators([1]);
            expect(await this.sfc.minGasPrice()).to.be.bignumber.equal(new BN('94996125793'));
        });
    });
});

contract('SFC', async ([firstValidator, secondValidator, thirdValidator, testValidator, firstDelegator, secondDelegator, account1, account2, account3, account4]) => {
    let firstValidatorID;
    let secondValidatorID;
    let thirdValidatorID;

    beforeEach(async () => {
        this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
        const nodeIRaw = await NodeDriver.new();
        const evmWriter = await StubEvmWriter.new();
        this.nodeI = await NodeDriverAuth.new();
        this.sfcLib = await UnitTestSFCLib.new();
        const initializer = await NetworkInitializer.new();
        await initializer.initializeAll(0, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
        this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
        await this.sfc.rebaseTime();
        await this.sfc.enableNonNodeCalls();

        await this.sfc.createValidator(pubkey, {
            from: firstValidator,
            value: amount18('0.4'),
        });
        firstValidatorID = await this.sfc.getValidatorID(firstValidator);

        await this.sfc.createValidator(pubkey1, {
            from: secondValidator,
            value: amount18('0.8'),
        });
        secondValidatorID = await this.sfc.getValidatorID(secondValidator);

        await this.sfc.createValidator(pubkey2, {
            from: thirdValidator,
            value: amount18('0.8'),
        });
        thirdValidatorID = await this.sfc.getValidatorID(thirdValidator);
        await this.sfc.delegate(firstValidatorID, {
            from: firstValidator,
            value: amount18('0.4'),
        });

        await this.sfc.delegate(firstValidatorID, {
            from: firstDelegator,
            value: amount18('0.4'),
        });
        await this.sfc.delegate(secondValidatorID, {
            from: secondDelegator,
            value: amount18('0.4'),
        });

        await sealEpoch(this.sfc, (new BN(0)).toString());
    });

    describe('Staking / Sealed Epoch functions', () => {
        it('Should return claimed Rewards until Epoch', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('1'));
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            expect(await this.sfc.stashedRewardsUntilEpoch(firstDelegator, 1)).to.bignumber.equal(new BN(0));
            await this.sfc.claimRewards(1, { from: firstDelegator });
            expect(await this.sfc.stashedRewardsUntilEpoch(firstDelegator, 1)).to.bignumber.equal(await this.sfc.currentSealedEpoch());
        });

        it('Check pending Rewards of delegators', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('1'));

            expect((await this.sfc.pendingRewards(firstValidator, firstValidatorID)).toString()).to.equals('0');
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString()).to.equals('0');

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());

            expect((await this.sfc.pendingRewards(firstValidator, firstValidatorID)).toString()).to.equals('6966');
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString()).to.equals('2754');
        });

        it('Check if pending Rewards have been increased after sealing Epoch', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('1'));

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            expect((await this.sfc.pendingRewards(firstValidator, firstValidatorID)).toString()).to.equals('6966');
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString()).to.equals('2754');

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            expect((await this.sfc.pendingRewards(firstValidator, firstValidatorID)).toString()).to.equals('13932');
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString()).to.equals('5508');
        });

        it('Should increase balances after claiming Rewards', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('100000000000000'));

            await sealEpoch(this.sfc, (new BN(0)).toString());
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());

            const firstDelegatorPendingRewards = await this.sfc.pendingRewards(firstDelegator, firstValidatorID);
            expect(firstDelegatorPendingRewards).to.be.bignumber.equal(amount18('0.2754'));
            const firstDelegatorBalance = new BN(await web3.eth.getBalance(firstDelegator));

            await this.sfc.claimRewards(1, { from: firstDelegator });

            const delegatorBalance = new BN(await web3.eth.getBalance(firstDelegator));
            expect(firstDelegatorBalance.add(firstDelegatorPendingRewards)).to.be.bignumber.above(delegatorBalance);
            expect(firstDelegatorBalance.add(firstDelegatorPendingRewards)).to.be.bignumber.below(delegatorBalance.add(amount18('0.01')));
        });

        it('Should increase stake after restaking Rewards', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('1'));

            await sealEpoch(this.sfc, (new BN(0)).toString());
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());

            const firstDelegatorPendingRewards = await this.sfc.pendingRewards(firstDelegator, firstValidatorID);
            expect(firstDelegatorPendingRewards).to.be.bignumber.equal(new BN('2754'));
            const firstDelegatorStake = await this.sfc.getStake(firstDelegator, firstValidatorID);
            const firstDelegatorLockupInfo = await this.sfc.getLockupInfo(firstDelegator, firstValidatorID);

            await this.sfc.restakeRewards(1, { from: firstDelegator });

            const delegatorStake = await this.sfc.getStake(firstDelegator, firstValidatorID);
            const delegatorLockupInfo = await this.sfc.getLockupInfo(firstDelegator, firstValidatorID);
            expect(delegatorStake).to.be.bignumber.equal(firstDelegatorStake.add(firstDelegatorPendingRewards));
            expect(delegatorLockupInfo.lockedStake).to.be.bignumber.equal(firstDelegatorLockupInfo.lockedStake);
        });

        it('Should increase locked stake after restaking Rewards', async () => {
            await this.sfc.lockStake(firstValidatorID, new BN(86400 * 219 + 10), amount18('0.2'), {
                from: firstValidator,
            });
            await this.sfc.lockStake(firstValidatorID, new BN(86400 * 219), amount18('0.2'), {
                from: firstDelegator,
            });

            await this.consts.updateBaseRewardPerSecond(new BN('1'));

            await sealEpoch(this.sfc, (new BN(0)).toString());
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());

            const firstDelegatorPendingRewards = await this.sfc.pendingRewards(firstDelegator, firstValidatorID);
            expect(firstDelegatorPendingRewards).to.be.bignumber.equal(new BN('4681'));
            const firstDelegatorPendingLockupRewards = new BN('3304');
            const firstDelegatorStake = await this.sfc.getStake(firstDelegator, firstValidatorID);
            const firstDelegatorLockupInfo = await this.sfc.getLockupInfo(firstDelegator, firstValidatorID);

            await this.sfc.restakeRewards(1, { from: firstDelegator });

            const delegatorStake = await this.sfc.getStake(firstDelegator, firstValidatorID);
            const delegatorLockupInfo = await this.sfc.getLockupInfo(firstDelegator, firstValidatorID);
            expect(delegatorStake).to.be.bignumber.equal(firstDelegatorStake.add(firstDelegatorPendingRewards));
            expect(delegatorLockupInfo.lockedStake).to.be.bignumber.equal(firstDelegatorLockupInfo.lockedStake.add(firstDelegatorPendingLockupRewards));
        });

        it('Should return stashed Rewards', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('1'));

            await sealEpoch(this.sfc, (new BN(0)).toString());
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());

            expect((await this.sfc.rewardsStash(firstDelegator, 1)).toString()).to.equals('0');

            await this.sfc.stashRewards(firstDelegator, 1);
            expect((await this.sfc.rewardsStash(firstDelegator, 1)).toString()).to.equals('2754');
        });

        it('Should update the validator on node', async () => {
            await this.consts.updateOfflinePenaltyThresholdTime(10000);
            await this.consts.updateOfflinePenaltyThresholdBlocksNum(500);

            expect(await this.consts.offlinePenaltyThresholdTime()).to.bignumber.equals(new BN(10000));
            expect(await this.consts.offlinePenaltyThresholdBlocksNum()).to.bignumber.equals(new BN(500));
        });

        it('Should not be able to deactivate validator if not Node', async () => {
            await this.sfc.disableNonNodeCalls();
            await expect(this.sfc.deactivateValidator(1, 0)).to.be.rejectedWith('caller is not the NodeDriverAuth contract');
        });

        it('Should seal Epochs', async () => {
            let validatorsMetrics;
            const validatorIDs = (await this.sfc.lastValidatorID()).toNumber();

            if (validatorsMetrics === undefined) {
                validatorsMetrics = {};
                for (let i = 0; i < validatorIDs; i++) {
                    validatorsMetrics[i] = {
                        offlineTime: new BN('0'),
                        offlineBlocks: new BN('0'),
                        uptime: new BN(24 * 60 * 60).toString(),
                        originatedTxsFee: amount18('100'),
                    };
                }
            }
            const allValidators = [];
            const offlineTimes = [];
            const offlineBlocks = [];
            const uptimes = [];
            const originatedTxsFees = [];
            for (let i = 0; i < validatorIDs; i++) {
                allValidators.push(i + 1);
                offlineTimes.push(validatorsMetrics[i].offlineTime);
                offlineBlocks.push(validatorsMetrics[i].offlineBlocks);
                uptimes.push(validatorsMetrics[i].uptime);
                originatedTxsFees.push(validatorsMetrics[i].originatedTxsFee);
            }

            await expect(this.sfc.advanceTime(new BN(24 * 60 * 60).toString())).to.be.fulfilled;
            await expect(this.sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees, 0)).to.be.fulfilled;
            await expect(this.sfc.sealEpochValidators(allValidators)).to.be.fulfilled;
        });

        it('Should seal Epoch on Validators', async () => {
            let validatorsMetrics;
            const validatorIDs = (await this.sfc.lastValidatorID()).toNumber();

            if (validatorsMetrics === undefined) {
                validatorsMetrics = {};
                for (let i = 0; i < validatorIDs; i++) {
                    validatorsMetrics[i] = {
                        offlineTime: new BN('0'),
                        offlineBlocks: new BN('0'),
                        uptime: new BN(24 * 60 * 60).toString(),
                        originatedTxsFee: amount18('0'),
                    };
                }
            }
            const allValidators = [];
            const offlineTimes = [];
            const offlineBlocks = [];
            const uptimes = [];
            const originatedTxsFees = [];
            for (let i = 0; i < validatorIDs; i++) {
                allValidators.push(i + 1);
                offlineTimes.push(validatorsMetrics[i].offlineTime);
                offlineBlocks.push(validatorsMetrics[i].offlineBlocks);
                uptimes.push(validatorsMetrics[i].uptime);
                originatedTxsFees.push(validatorsMetrics[i].originatedTxsFee);
            }

            await expect(this.sfc.advanceTime(new BN(24 * 60 * 60).toString())).to.be.fulfilled;
            await expect(this.sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees, 0)).to.be.fulfilled;
            await expect(this.sfc.sealEpochValidators(allValidators)).to.be.fulfilled;
        });
    });

    describe('Stake lockup', () => {
        beforeEach('lock stakes', async () => {
            // Lock 75% of stake for 60% of a maximum lockup period
            // Should receive (0.3 * 0.25 + (0.3 + 0.7 * 0.6) * 0.75) / 0.3 = 2.05 times more rewards
            await this.sfc.lockStake(firstValidatorID, new BN(86400 * 219), amount18('0.6'), {
                from: firstValidator,
            });
            // Lock 25% of stake for 20% of a maximum lockup period
            // Should receive (0.3 * 0.75 + (0.3 + 0.7 * 0.2) * 0.25) / 0.3 = 1.1166 times more rewards
            await this.sfc.lockStake(firstValidatorID, new BN(86400 * 73), amount18('0.1'), {
                from: firstDelegator,
            });
        });

        // note: copied from the non-lockup tests
        it('Check pending Rewards of delegators', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('1'));

            expect((await this.sfc.pendingRewards(firstValidator, firstValidatorID)).toString()).to.equals('0');
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString()).to.equals('0');

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());

            expect((await this.sfc.pendingRewards(firstValidator, firstValidatorID)).toString()).to.equals('14279');
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString()).to.equals('3074');
        });

        // note: copied from the non-lockup tests
        it('Check if pending Rewards have been increased after sealing Epoch', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('1'));

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            expect((await this.sfc.pendingRewards(firstValidator, firstValidatorID)).toString()).to.equals('14279');
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString()).to.equals('3074');

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            expect((await this.sfc.pendingRewards(firstValidator, firstValidatorID)).toString()).to.equals('28558');
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString()).to.equals('6150');
        });

        // note: copied from the non-lockup tests
        it('Should increase balances after claiming Rewards', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('1'));

            await sealEpoch(this.sfc, (new BN(0)).toString());
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());

            const firstDelegatorPendingRewards = await this.sfc.pendingRewards(firstDelegator, firstValidatorID);
            const firstDelegatorBalance = await web3.eth.getBalance(firstDelegator);

            await this.sfc.claimRewards(1, { from: firstDelegator });

            expect(new BN(firstDelegatorBalance + firstDelegatorPendingRewards)).to.be.bignumber.above(await web3.eth.getBalance(firstDelegator));
        });

        // note: copied from the non-lockup tests
        it('Should return stashed Rewards', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('1'));

            await sealEpoch(this.sfc, (new BN(0)).toString());
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());

            expect((await this.sfc.rewardsStash(firstDelegator, 1)).toString()).to.equals('0');

            await this.sfc.stashRewards(firstDelegator, 1);
            expect((await this.sfc.rewardsStash(firstDelegator, 1)).toString()).to.equals('3074');
        });

        it('Should return pending rewards after unlocking and re-locking', async () => {
            await this.consts.updateBaseRewardPerSecond(new BN('1'));

            for (let i = 0; i < 2; i++) {
                const epoch = await this.sfc.currentSealedEpoch();
                // delegator 1 is still locked
                // delegator 1 should receive more rewards than delegator 2
                // validator 1 should receive more rewards than validator 2
                await sealEpoch(this.sfc, (new BN(86400 * (73))).toString());

                expect(await this.sfc.pendingRewards(firstDelegator, 1)).to.be.bignumber.equal(new BN(224496));
                expect(await this.sfc.pendingRewards(secondDelegator, 2)).to.be.bignumber.equal(new BN(201042));
                expect(await this.sfc.pendingRewards(firstValidator, 1)).to.be.bignumber.equal(new BN(1042461));
                expect(await this.sfc.pendingRewards(secondValidator, 2)).to.be.bignumber.equal(new BN(508518));

                expect(await this.sfc.highestLockupEpoch(firstDelegator, 1)).to.be.bignumber.equal(epoch.add(new BN(1)));
                expect(await this.sfc.highestLockupEpoch(secondDelegator, 2)).to.be.bignumber.equal(new BN(0));
                expect(await this.sfc.highestLockupEpoch(firstValidator, 1)).to.be.bignumber.equal(epoch.add(new BN(1)));
                expect(await this.sfc.highestLockupEpoch(secondValidator, 2)).to.be.bignumber.equal(new BN(0));

                // delegator 1 isn't locked already
                // delegator 1 should receive the same reward as delegator 2
                // validator 1 should receive more rewards than validator 2
                await sealEpoch(this.sfc, (new BN(86400 * (1))).toString());

                expect(await this.sfc.pendingRewards(firstDelegator, 1)).to.be.bignumber.equal(new BN(224496 + 2754));
                expect(await this.sfc.pendingRewards(secondDelegator, 2)).to.be.bignumber.equal(new BN(201042 + 2754));
                expect(await this.sfc.pendingRewards(firstValidator, 1)).to.be.bignumber.equal(new BN(1042461 + 14279));
                expect(await this.sfc.pendingRewards(secondValidator, 2)).to.be.bignumber.equal(new BN(508518 + 6966));
                expect(await this.sfc.highestLockupEpoch(firstDelegator, 1)).to.be.bignumber.equal(epoch.add(new BN(1)));
                expect(await this.sfc.highestLockupEpoch(firstValidator, 1)).to.be.bignumber.equal(epoch.add(new BN(2)));

                // validator 1 is still locked
                // delegator 1 should receive the same reward as delegator 2
                // validator 1 should receive more rewards than validator 2
                await sealEpoch(this.sfc, (new BN(86400 * (145))).toString());

                expect(await this.sfc.pendingRewards(firstDelegator, 1)).to.be.bignumber.equal(new BN(224496 + 2754 + 399330));
                expect(await this.sfc.pendingRewards(secondDelegator, 2)).to.be.bignumber.equal(new BN(201042 + 2754 + 399330));
                expect(await this.sfc.pendingRewards(firstValidator, 1)).to.be.bignumber.equal(new BN(1042461 + 14279 + 2070643));
                expect(await this.sfc.pendingRewards(secondValidator, 2)).to.be.bignumber.equal(new BN(508518 + 6966 + 1010070));
                expect(await this.sfc.highestLockupEpoch(firstDelegator, 1)).to.be.bignumber.equal(epoch.add(new BN(1)));
                expect(await this.sfc.highestLockupEpoch(firstValidator, 1)).to.be.bignumber.equal(epoch.add(new BN(3)));

                // validator 1 isn't locked already
                // delegator 1 should receive the same reward as delegator 2
                // validator 1 should receive the same reward as validator 2
                await sealEpoch(this.sfc, (new BN(86400 * (1))).toString());

                expect(await this.sfc.pendingRewards(firstDelegator, 1)).to.be.bignumber.equal(new BN(224496 + 2754 + 399330 + 2754));
                expect(await this.sfc.pendingRewards(secondDelegator, 2)).to.be.bignumber.equal(new BN(201042 + 2754 + 399330 + 2754));
                expect(await this.sfc.pendingRewards(firstValidator, 1)).to.be.bignumber.equal(new BN(1042461 + 14279 + 2070643 + 6966));
                expect(await this.sfc.pendingRewards(secondValidator, 2)).to.be.bignumber.equal(new BN(508518 + 6966 + 1010070 + 6966));
                expect(await this.sfc.highestLockupEpoch(firstDelegator, 1)).to.be.bignumber.equal(epoch.add(new BN(1)));
                expect(await this.sfc.highestLockupEpoch(firstValidator, 1)).to.be.bignumber.equal(epoch.add(new BN(3)));

                // re-lock both validator and delegator
                await this.sfc.lockStake(firstValidatorID, new BN(86400 * 219), amount18('0.6'), {
                    from: firstValidator,
                });
                await this.sfc.lockStake(firstValidatorID, new BN(86400 * 73), amount18('0.1'), {
                    from: firstDelegator,
                });
                // check rewards didn't change after re-locking
                expect(await this.sfc.pendingRewards(firstDelegator, 1)).to.be.bignumber.equal(new BN(224496 + 2754 + 399330 + 2754));
                expect(await this.sfc.pendingRewards(secondDelegator, 2)).to.be.bignumber.equal(new BN(201042 + 2754 + 399330 + 2754));
                expect(await this.sfc.pendingRewards(firstValidator, 1)).to.be.bignumber.equal(new BN(1042461 + 14279 + 2070643 + 6966));
                expect(await this.sfc.pendingRewards(secondValidator, 2)).to.be.bignumber.equal(new BN(508518 + 6966 + 1010070 + 6966));
                expect(await this.sfc.highestLockupEpoch(firstDelegator, 1)).to.be.bignumber.equal(new BN(0));
                expect(await this.sfc.highestLockupEpoch(firstValidator, 1)).to.be.bignumber.equal(new BN(0));
                // claim rewards to reset pending rewards
                await this.sfc.claimRewards(1, { from: firstDelegator });
                await this.sfc.claimRewards(2, { from: secondDelegator });
                await this.sfc.claimRewards(1, { from: firstValidator });
                await this.sfc.claimRewards(2, { from: secondValidator });
            }
        });
    });

    describe('NodeDriver', () => {
        it('Should not be able to call `setGenesisValidator` if not NodeDriver', async () => {
            await expectRevert(this.nodeI.setGenesisValidator(account1, 1, pubkey, 1 << 3, await this.sfc.currentEpoch(), Date.now(), 0, 0, {
                from: account2,
            }), 'caller is not the NodeDriver contract');
        });

        it('Should not be able to call `setGenesisDelegation` if not NodeDriver', async () => {
            await expectRevert(this.nodeI.setGenesisDelegation(firstDelegator, 1, 100, 0, 0, 0, 0, 0, 1000, {
                from: account2,
            }), 'caller is not the NodeDriver contract');
        });

        it('Should not be able to call `deactivateValidator` if not NodeDriver', async () => {
            await expectRevert(this.nodeI.deactivateValidator(1, 0, {
                from: account2,
            }), 'caller is not the NodeDriver contract');
        });

        it('Should not be able to call `deactivateValidator` with wrong status', async () => {
            await expectRevert(this.sfc.deactivateValidator(1, 0), 'wrong status');
        });

        it('Should deactivate Validator', async () => {
            await this.sfc.deactivateValidator(1, 1);
        });

        it('Should not be able to call `sealEpochValidators` if not NodeDriver', async () => {
            await expectRevert(this.nodeI.sealEpochValidators([1], {
                from: account2,
            }), 'caller is not the NodeDriver contract');
        });

        it('Should not be able to call `sealEpoch` if not NodeDriver', async () => {
            let validatorsMetrics;
            const validatorIDs = (await this.sfc.lastValidatorID()).toNumber();

            if (validatorsMetrics === undefined) {
                validatorsMetrics = {};
                for (let i = 0; i < validatorIDs; i++) {
                    validatorsMetrics[i] = {
                        offlineTime: new BN('0'),
                        offlineBlocks: new BN('0'),
                        uptime: new BN(24 * 60 * 60).toString(),
                        originatedTxsFee: amount18('0'),
                    };
                }
            }
            const allValidators = [];
            const offlineTimes = [];
            const offlineBlocks = [];
            const uptimes = [];
            const originatedTxsFees = [];
            for (let i = 0; i < validatorIDs; i++) {
                allValidators.push(i + 1);
                offlineTimes.push(validatorsMetrics[i].offlineTime);
                offlineBlocks.push(validatorsMetrics[i].offlineBlocks);
                uptimes.push(validatorsMetrics[i].uptime);
                originatedTxsFees.push(validatorsMetrics[i].originatedTxsFee);
            }

            await expect(this.sfc.advanceTime(new BN(24 * 60 * 60).toString())).to.be.fulfilled;
            await expectRevert(this.nodeI.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees, 0, {
                from: account2,
            }), 'caller is not the NodeDriver contract');
        });
    });

    describe('Epoch getters', () => {
        it('should return EpochvalidatorIds', async () => {
            const currentSealedEpoch = await this.sfc.currentSealedEpoch();
            await this.sfc.getEpochValidatorIDs(currentSealedEpoch);
        });

        it('should return the Epoch Received Stake', async () => {
            const currentSealedEpoch = await this.sfc.currentSealedEpoch();
            await this.sfc.getEpochReceivedStake(currentSealedEpoch, 1);
        });

        it('should return the Epoch Accumulated Reward Per Token', async () => {
            const currentSealedEpoch = await this.sfc.currentSealedEpoch();
            await this.sfc.getEpochAccumulatedRewardPerToken(currentSealedEpoch, 1);
        });

        it('should return the Epoch Accumulated Uptime', async () => {
            const currentSealedEpoch = await this.sfc.currentSealedEpoch();
            await this.sfc.getEpochAccumulatedUptime(currentSealedEpoch, 1);
        });

        it('should return the Epoch Accumulated Originated Txs Fee', async () => {
            const currentSealedEpoch = await this.sfc.currentSealedEpoch();
            await this.sfc.getEpochAccumulatedOriginatedTxsFee(currentSealedEpoch, 1);
        });

        it('should return the Epoch Offline time ', async () => {
            const currentSealedEpoch = await this.sfc.currentSealedEpoch();
            await this.sfc.getEpochOfflineTime(currentSealedEpoch, 1);
        });

        it('should return Epoch Offline Blocks', async () => {
            const currentSealedEpoch = await this.sfc.currentSealedEpoch();
            await this.sfc.getEpochOfflineBlocks(currentSealedEpoch, 1);
        });
    });

    describe('Unlock features', () => {
        it('should fail if trying to unlock stake if not lockedup', async () => {
            await expectRevert(this.sfc.unlockStake(1, 10), 'not locked up');
        });

        it('should fail if trying to unlock stake if amount is 0', async () => {
            await expectRevert(this.sfc.unlockStake(1, 0), 'zero amount');
        });

        it('should return if slashed', async () => {
            console.log(await this.sfc.isSlashed(1));
        });

        it('should fail if delegating to an unexisting validator', async () => {
            await expectRevert(this.sfc.delegate(4), "validator doesn't exist");
        });

        it('should fail if delegating to an unexisting validator (2)', async () => {
            await expectRevert(this.sfc.delegate(4, {
                value: 10000,
            }), "validator doesn't exist");
        });
    });

    describe('SFC Rewards getters / Features', () => {
        it('should return stashed rewards', async () => {
            console.log(await this.sfc.rewardsStash(firstDelegator, 1));
        });

        it('should return locked stake', async () => {
            console.log(await this.sfc.getLockedStake(firstDelegator, 1));
        });

        it('should return locked stake (2)', async () => {
            console.log(await this.sfc.getLockedStake(firstDelegator, 2));
        });
    });
});

contract('SFC', async ([firstValidator, firstDelegator]) => {
    let firstValidatorID;

    beforeEach(async () => {
        this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
        const nodeIRaw = await NodeDriver.new();
        const evmWriter = await StubEvmWriter.new();
        this.nodeI = await NodeDriverAuth.new();
        this.sfcLib = await UnitTestSFCLib.new();
        const initializer = await NetworkInitializer.new();
        await initializer.initializeAll(0, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
        this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
        await this.sfc.enableNonNodeCalls();
        await this.sfc.setGenesisValidator(firstValidator, 1, pubkey, 0, await this.sfc.currentEpoch(), Date.now(), 0, 0);
        firstValidatorID = await this.sfc.getValidatorID(firstValidator);
        await this.sfc.delegate(firstValidatorID, {
            from: firstValidator,
            value: amount18('4'),
        });
        await sealEpoch(this.sfc, new BN(24 * 60 * 60));
    });

    describe('Staking / Sealed Epoch functions', () => {
        it('Should setGenesisDelegation Validator', async () => {
            await this.sfc.setGenesisDelegation(firstDelegator, firstValidatorID, amount18('1'), 0, 0, 0, 0, 0, 100);
            expect(await this.sfc.getStake(firstDelegator, firstValidatorID)).to.bignumber.equals(amount18('1'));
        });
    });
});

contract('SFC', async ([firstValidator, testValidator, firstDelegator, secondDelegator, thirdDelegator, account1, account2, account3]) => {
    let testValidator1ID;
    let testValidator2ID;
    let testValidator3ID;

    beforeEach(async () => {
        this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
        const nodeIRaw = await NodeDriver.new();
        const evmWriter = await StubEvmWriter.new();
        this.nodeI = await NodeDriverAuth.new();
        this.sfcLib = await UnitTestSFCLib.new();
        const initializer = await NetworkInitializer.new();
        await initializer.initializeAll(0, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
        this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
        await this.sfc.rebaseTime();
        await this.sfc.enableNonNodeCalls();

        await this.consts.updateBaseRewardPerSecond(amount18('1'));

        await this.sfc.createValidator(pubkey, {
            from: account1,
            value: amount18('10'),
        });

        await this.sfc.createValidator(pubkey1, {
            from: account2,
            value: amount18('5'),
        });

        await this.sfc.createValidator(pubkey2, {
            from: account3,
            value: amount18('1'),
        });

        testValidator1ID = await this.sfc.getValidatorID(account1);
        testValidator2ID = await this.sfc.getValidatorID(account2);
        testValidator3ID = await this.sfc.getValidatorID(account3);

        await this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * 364), amount18('1'),
            { from: account3 });

        await sealEpoch(this.sfc, (new BN(0)).toString());
    });

    describe('Test Rewards Calculation', () => {
        it('Calculation of validators rewards should be equal to 30%', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            const rewardAcc1 = (await this.sfc.pendingRewards(account1, testValidator1ID)).toString().slice(0, -16);
            const rewardAcc2 = (await this.sfc.pendingRewards(account2, testValidator2ID)).toString().slice(0, -16);
            const rewardAcc3 = (await this.sfc.pendingRewards(account3, testValidator3ID)).toString().slice(0, -16);

            expect(parseInt(rewardAcc1) + parseInt(rewardAcc2) + parseInt(rewardAcc3)).to.equal(34363);
        });

        it('Should not be able withdraw if request does not exist', async () => {
            await expectRevert(this.sfc.withdraw(testValidator1ID, 0), "request doesn't exist");
        });

        it('Should not be able to undelegate 0 amount', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await expectRevert(this.sfc.undelegate(testValidator1ID, 0, 0), 'zero amount');
        });

        it('Should not be able to undelegate if not enough unlocked stake', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await expectRevert(this.sfc.undelegate(testValidator1ID, 0, 10), 'not enough unlocked stake');
        });

        it('Should not be able to unlock if not enough unlocked stake', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator1ID, {
                from: thirdDelegator,
                value: amount18('1'),
            });
            await expectRevert(this.sfc.unlockStake(testValidator1ID, 10, { from: thirdDelegator }), 'not locked up');
        });

        it('should return the unlocked stake', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator3ID, {
                from: thirdDelegator,
                value: amount18('1'),
            });
            const unlockedStake = await this.sfc.getUnlockedStake(thirdDelegator, testValidator3ID, { from: thirdDelegator });
            expect(unlockedStake.toString()).to.equal('1000000000000000000');
        });

        it('Should not be able to claim Rewards if 0 rewards', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator3ID, {
                from: thirdDelegator,
                value: amount18('10'),
            });

            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await expectRevert(this.sfc.claimRewards(testValidator1ID, { from: thirdDelegator }), 'zero rewards');
        });
    });
});

contract('SFC', async ([firstValidator, testValidator, firstDelegator, secondDelegator, thirdDelegator, account1, account2, account3]) => {
    let testValidator1ID;
    let testValidator2ID;
    let testValidator3ID;

    beforeEach(async () => {
        this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
        const nodeIRaw = await NodeDriver.new();
        const evmWriter = await StubEvmWriter.new();
        this.nodeI = await NodeDriverAuth.new();
        this.sfcLib = await UnitTestSFCLib.new();
        const initializer = await NetworkInitializer.new();
        await initializer.initializeAll(0, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
        this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
        await this.sfc.rebaseTime();
        await this.sfc.enableNonNodeCalls();

        await this.consts.updateBaseRewardPerSecond(amount18('1'));

        await this.sfc.createValidator(pubkey, {
            from: account1,
            value: amount18('10'),
        });

        await this.sfc.createValidator(pubkey1, {
            from: account2,
            value: amount18('5'),
        });

        await this.sfc.createValidator(pubkey2, {
            from: account3,
            value: amount18('1'),
        });

        await sealEpoch(this.sfc, (new BN(0)).toString());

        testValidator1ID = await this.sfc.getValidatorID(account1);
        testValidator2ID = await this.sfc.getValidatorID(account2);
        testValidator3ID = await this.sfc.getValidatorID(account3);

        await this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * (365 - 31)), amount18('1'),
            { from: account3 });

        await sealEpoch(this.sfc, (new BN(0)).toString());
    });

    describe('Test Calculation Rewards with Lockup', () => {
        it('Should not be able to lock 0 amount', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await expectRevert(this.sfc.lockStake(testValidator1ID, (2 * 60 * 60 * 24 * 365), amount18('0'), {
                from: thirdDelegator,
            }), 'zero amount');
        });

        it('Should not be able to lock more than a year', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator3ID, {
                from: thirdDelegator,
                value: amount18('10'),
            });

            await expectRevert(this.sfc.lockStake(testValidator3ID, (2 * 60 * 60 * 24 * 365), amount18('1'), {
                from: thirdDelegator,
            }), 'incorrect duration');
        });

        it('Should not be able to lock more than validator lockup period', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator3ID, {
                from: thirdDelegator,
                value: amount18('10'),
            });

            await expectRevert(this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * 364), amount18('1'),
                { from: thirdDelegator }), 'validator\'s lockup will end too early');

            await this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * 363), amount18('1'),
                { from: thirdDelegator });
        });

        it('Should be able to lock for 1 month', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator3ID, {
                from: thirdDelegator,
                value: amount18('10'),
            });

            await this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * 14), amount18('1'),
                { from: thirdDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 14)).toString());
        });

        it('Should not unlock if not locked up FTM', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator3ID, {
                from: thirdDelegator,
                value: amount18('10'),
            });

            await this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * 14), amount18('1'),
                { from: thirdDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 14)).toString());

            await expectRevert(this.sfc.unlockStake(testValidator3ID, amount18('10')), 'not locked up');
        });

        it('Should not be able to unlock more than locked stake', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator3ID, {
                from: thirdDelegator,
                value: amount18('10'),
            });

            await this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * 14), amount18('1'),
                { from: thirdDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 14)).toString());

            await expectRevert(this.sfc.unlockStake(testValidator3ID, amount18('10'), { from: thirdDelegator }), 'not enough locked stake');
        });

        it('Should scale unlocking penalty', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator3ID, {
                from: thirdDelegator,
                value: amount18('10'),
            });

            await this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * 60), amount18('1'),
                { from: thirdDelegator });

            await sealEpoch(this.sfc, (new BN(1)).toString());

            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('1'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.001280160336239103'));
            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('0.5'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000640080168119551'));
            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('0.01'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000012801603362390'));
            await this.sfc.unlockStake(testValidator3ID, amount18('0.5'), { from: thirdDelegator });
            await expectRevert(this.sfc.unlockStake(testValidator3ID, amount18('0.51'), { from: thirdDelegator }), 'not enough locked stake');
            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('0.5'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000640080168119552'));
            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('0.01'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000012801603362390'));
        });

        it('Should scale unlocking penalty with limiting to reasonable value', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator3ID, {
                from: thirdDelegator,
                value: amount18('10'),
            });

            await this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * 14), amount18('1'),
                { from: thirdDelegator });

            await sealEpoch(this.sfc, (new BN(100)).toString());

            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('1'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000380540964546690'));
            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('0.5'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000190270482273344'));
            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('0.01'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000003805409645466'));
            await this.sfc.unlockStake(testValidator3ID, amount18('0.5'), { from: thirdDelegator });
            await expectRevert(this.sfc.unlockStake(testValidator3ID, amount18('0.51'), { from: thirdDelegator }), 'not enough locked stake');
            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('0.5'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000190270482273344'));
            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('0.01'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000003805409645466'));

            await this.sfc.relockStake(testValidator3ID, (60 * 60 * 24 * 14), amount18('1'),
                { from: thirdDelegator });

            await expectRevert(this.sfc.unlockStake(testValidator3ID, amount18('1.51'), { from: thirdDelegator }), 'not enough locked stake');
            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('1.5'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000190270482273344'));
            expect(await this.sfc.unlockStake.call(testValidator3ID, amount18('0.5'), { from: thirdDelegator })).to.be.bignumber.equal(amount18('0.000063423494091114')); // 3 times smaller
        });

        it('Should unlock after period ended and stash rewards', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await this.sfc.delegate(testValidator3ID, {
                from: thirdDelegator,
                value: amount18('10'),
            });

            let unlockedStake = await this.sfc.getUnlockedStake(thirdDelegator, testValidator3ID, { from: thirdDelegator });
            let pendingRewards = await this.sfc.pendingRewards(thirdDelegator, testValidator3ID, { from: thirdDelegator });

            expect(unlockedStake.toString()).to.equal('10000000000000000000');
            expect(web3.utils.fromWei(pendingRewards.toString(), 'ether')).to.equal('0');
            await this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * 14), amount18('1'),
                { from: thirdDelegator });

            unlockedStake = await this.sfc.getUnlockedStake(thirdDelegator, testValidator3ID, { from: thirdDelegator });
            pendingRewards = await this.sfc.pendingRewards(thirdDelegator, testValidator3ID, { from: thirdDelegator });

            expect(unlockedStake.toString()).to.equal('9000000000000000000');
            expect(web3.utils.fromWei(pendingRewards.toString(), 'ether')).to.equal('0');
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 14)).toString());

            unlockedStake = await this.sfc.getUnlockedStake(thirdDelegator, testValidator3ID, { from: thirdDelegator });
            pendingRewards = await this.sfc.pendingRewards(thirdDelegator, testValidator3ID, { from: thirdDelegator });

            expect(unlockedStake.toString()).to.equal('9000000000000000000');
            expect(web3.utils.fromWei(pendingRewards.toString(), 'ether')).to.equal('17682.303362391033619905');

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 14)).toString());
            pendingRewards = await this.sfc.pendingRewards(thirdDelegator, testValidator3ID, { from: thirdDelegator });

            unlockedStake = await this.sfc.getUnlockedStake(thirdDelegator, testValidator3ID, { from: thirdDelegator });
            expect(unlockedStake.toString()).to.equal('10000000000000000000');
            expect(web3.utils.fromWei(pendingRewards.toString(), 'ether')).to.equal('136316.149516237187466057');

            await this.sfc.stashRewards(thirdDelegator, testValidator3ID, { from: thirdDelegator });
        });
    });
});

contract('SFC', async ([firstValidator, testValidator, firstDelegator, secondDelegator, thirdDelegator, account1, account2, account3]) => {
    let testValidator1ID;
    let testValidator2ID;
    let testValidator3ID;

    beforeEach(async () => {
        this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
        const nodeIRaw = await NodeDriver.new();
        const evmWriter = await StubEvmWriter.new();
        this.nodeI = await NodeDriverAuth.new();
        this.sfcLib = await UnitTestSFCLib.new();
        const initializer = await NetworkInitializer.new();
        await initializer.initializeAll(0, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
        this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
        await this.sfc.rebaseTime();
        await this.sfc.enableNonNodeCalls();

        await this.consts.updateBaseRewardPerSecond(amount18('1'));

        await this.sfc.createValidator(pubkey, {
            from: account1,
            value: amount18('10'),
        });

        await this.sfc.createValidator(pubkey1, {
            from: account2,
            value: amount18('5'),
        });

        await this.sfc.createValidator(pubkey2, {
            from: account3,
            value: amount18('1'),
        });

        await sealEpoch(this.sfc, (new BN(0)).toString());

        testValidator1ID = await this.sfc.getValidatorID(account1);
        testValidator2ID = await this.sfc.getValidatorID(account2);
        testValidator3ID = await this.sfc.getValidatorID(account3);

        await this.sfc.lockStake(testValidator3ID, (60 * 60 * 24 * 364), amount18('1'),
            { from: account3 });

        await sealEpoch(this.sfc, (new BN(0)).toString());
    });

    describe('Test Rewards with lockup Calculation', () => {
        it('Should not update slashing refund ratio', async () => {
            await sealEpoch(this.sfc, (new BN(1000)).toString());

            await expectRevert(this.sfc.updateSlashingRefundRatio(testValidator3ID, 1, {
                from: firstValidator,
            }), "validator isn't slashed");

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 14)).toString());
        });

        it('Should not sync if validator does not exist', async () => {
            await expectRevert(this.sfc._syncValidator(33, false), "validator doesn't exist");
        });
    });
});

// calc rewards in ether with a round down
const calcRewardsJs = (lockDuration, lockedAmount, stakedAmount, totalStakedAmount, rawReward) => {
    let rewards = {extra: 0, base: 0, unlocked: 0, penalty: 0, sum: 0};
    // note: calculation for commission isn't accurate
    let commissionFull = Math.floor(rawReward * 15 / 100);
    // let commissionFullLocked = Math.floor(commissionFull * lockedAmount / stakedAmount);
    // let commissionFullUnlocked = commissionFull - commissionFullLocked;
    // if (isValidator) {
    //     rewards.extra = Math.floor(commissionFullLocked * 0.7 * lockDuration / (86400 * 365));
    //     rewards.base = Math.floor(commissionFullLocked * 0.3);
    //     rewards.unlocked = Math.floor(commissionFullUnlocked * 0.3);
    // }
    let delegatorRewards = rawReward - commissionFull;
    let accRate = Math.floor(delegatorRewards / totalStakedAmount);
    rewards.extra += Math.floor(accRate * lockedAmount * 0.7 * lockDuration / (86400 * 365));
    rewards.base += Math.floor(accRate * lockedAmount * 0.3);
    rewards.unlocked += Math.floor(accRate * (stakedAmount - lockedAmount)  * 0.3);
    rewards.penalty = Math.floor(rewards.extra + rewards.base/2);
    rewards.sum = rewards.extra + rewards.base + rewards.unlocked;
    return rewards;
}

contract('SFC', async ([firstValidator, secondValidator, firstDelegator, secondDelegator, thirdDelegator, account1, account2, account3]) => {
    let testValidator1ID;
    let testValidator2ID;
    let testValidator3ID;
    beforeEach(async () => {
        this.sfc = await SFCI.at((await UnitTestSFC.new()).address);
        const nodeIRaw = await NodeDriver.new();
        const evmWriter = await StubEvmWriter.new();
        this.nodeI = await NodeDriverAuth.new();
        this.sfcLib = await UnitTestSFCLib.new();
        const initializer = await NetworkInitializer.new();
        await initializer.initializeAll(0, 0, this.sfc.address, this.sfcLib.address, this.nodeI.address, nodeIRaw.address, evmWriter.address, firstValidator);
        this.consts = await ConstantsManager.at(await this.sfc.constsAddress.call());
        await this.sfc.rebaseTime();
        await this.sfc.enableNonNodeCalls();

        await this.consts.updateBaseRewardPerSecond('1');

        await this.sfc.createValidator(pubkey, {
            from: firstValidator,
            value: amount18('10')
        });
        firstValidatorID = await this.sfc.getValidatorID(firstValidator);
        await this.sfc.delegate(firstValidatorID, {
            from: firstDelegator,
            value: amount18('10')
        });
        await this.sfc.lockStake(firstValidatorID, (60 * 60 * 24 * 365), amount18('5'),
            { from: firstValidator });
        await sealEpoch(this.sfc, (new BN(0)).toString());
    });

    describe('Test fluid relocks', () => {
        // orig lock T1 -------------t1----> T2
        // relock           T3---------------------t2------>T3
        it('Relock happy path, lock, relock, no premature unlocks', async () => {
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

            await this.sfc.lockStake(firstValidatorID, (60 * 60 * 24 * 14), amount18('5'),
                { from: firstDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 7)).toString());
            rewardBeforeRelock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 7);
            await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 14), amount18('5'),
                { from: firstDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 14)).toString());
            rewardAfterUnlock = calcRewardsJs(86400 * 14, 10, 10, 20, 86400 * 14);

            expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString())
                .to.equals(expectedReward.toString());
        });
        it('Relock happy path, lock, relock no amount added, no premature unlocks', async () => {
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

            await this.sfc.lockStake(firstValidatorID, (60 * 60 * 24 * 14), amount18('5'),
                { from: firstDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 7)).toString());
            rewardBeforeRelock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 7);
            await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 14), amount18('0'),
                { from: firstDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 14)).toString());
            rewardAfterUnlock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 14);

            expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString())
                .to.equals(expectedReward.toString());
        });
        it('Relock happy path, lock, relock, unlock at t1', async () => {
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

            await this.sfc.lockStake(firstValidatorID, (60 * 60 * 24 * 14), amount18('5'),
                { from: firstDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 7)).toString());
            rewardBeforeRelock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 7);
            await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 14), amount18('5'),
                { from: firstDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 2)).toString());
            rewardAfterUnlock = calcRewardsJs(86400 * 14, 10, 10, 20, 86400 * 2);
            let expectedPenalty = rewardBeforeRelock.penalty + rewardAfterUnlock.penalty;

            expect((await this.sfc.unlockStake.call(firstValidatorID, amount18('10'), { from: firstDelegator })).toString())
                .to.equals(expectedPenalty.toString());

            expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString())
                .to.equals(expectedReward.toString());
        });
        it('Relock happy path, lock, relock, unlock at t2', async () => {
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

            await this.sfc.lockStake(firstValidatorID, (60 * 60 * 24 * 14), amount18('5'),
                { from: firstDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 7)).toString());
            rewardBeforeRelock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 7);
            await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 14), amount18('5'),
                { from: firstDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 12)).toString());
            rewardAfterUnlock = calcRewardsJs(86400 * 14, 10, 10, 20, 86400 * 12);
            let expectedPenalty = rewardAfterUnlock.penalty;
            expect((await this.sfc.unlockStake.call(firstValidatorID, amount18('10'), { from: firstDelegator })).toString())
                .to.equals(expectedPenalty.toString());

            expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString())
                .to.equals(expectedReward.toString());
        });
        it('Cannot relock if relock limit is exceeded', async () => {
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

            await this.sfc.lockStake(firstValidatorID, (60 * 60 * 24 * 20), amount18('5'),
                { from: firstDelegator });
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());

            { // 1
                await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 20), amount18('0'),
                    { from: firstDelegator });
                await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            }
            { // 2
                await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 20), amount18('0'),
                    { from: firstDelegator });
                await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            }
            { // 3
                await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 20), amount18('0'),
                    { from: firstDelegator });
                await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            }
            {
                await expectRevert(this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 20), amount18('0'),
                    { from: firstDelegator }), "too frequent relocks");
            }
            { // 4
                await this.sfc.advanceTime(60 * 60 * 24 * 14);
                await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 20), amount18('0'),
                    { from: firstDelegator });
                await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            }
            {
                await expectRevert(this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 20), amount18('0'),
                    { from: firstDelegator }), "too frequent relocks");
            }
            for (i = 5; i <= 40; i++) { // 5-40
                await this.sfc.advanceTime(60 * 60 * 24 * 14);
                await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 20), amount18('0'),
                    { from: firstDelegator });
                await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
                // ensure validator's lockup period doesn't end too early
                await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 365), amount18('0'),
                    { from: firstValidator });
            }
        });
        it('Partial unlock at t1, unlock amount < original lock amount', async () => {
            await sealEpoch(this.sfc, (new BN(60 * 60 * 24)).toString());
            rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

            await this.sfc.lockStake(firstValidatorID, (60 * 60 * 24 * 14), amount18('5'),
                { from: firstDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 7)).toString());
            rewardBeforeRelock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 7);
            await this.sfc.relockStake(firstValidatorID, (60 * 60 * 24 * 14), amount18('5'),
                { from: firstDelegator });

            await sealEpoch(this.sfc, (new BN(60 * 60 * 24 * 2)).toString());
            rewardAfterUnlock = calcRewardsJs(86400 * 14, 10, 10, 20, 86400 * 2);
            let penaltyShareBeforeRelock = Math.floor(rewardBeforeRelock.penalty * 2 / 10);
            let penaltyShareAfterUnlock = Math.floor(rewardAfterUnlock.penalty * 2 / 10);
            expectedPenalty = penaltyShareBeforeRelock + penaltyShareAfterUnlock;

            expect((await this.sfc.unlockStake.call(firstValidatorID, amount18('2'), { from: firstDelegator })).toString())
                .to.equals(expectedPenalty.toString());
            expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString())
                .to.equals(expectedReward.toString());

            await this.sfc.advanceTime(60 * 60 * 24 * 5 - 1);

            expect((await this.sfc.unlockStake.call(firstValidatorID, amount18('2'), { from: firstDelegator })).toString())
                .to.equals(expectedPenalty.toString());
            expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString())
                .to.equals(expectedReward.toString());

            await this.sfc.advanceTime(2);

            expectedPenalty = penaltyShareAfterUnlock;
            expect((await this.sfc.unlockStake.call(firstValidatorID, amount18('2'), { from: firstDelegator })).toString())
                .to.equals(expectedPenalty.toString());
            expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
            expect((await this.sfc.pendingRewards(firstDelegator, firstValidatorID)).toString())
                .to.equals(expectedReward.toString());

        });
    });
});
