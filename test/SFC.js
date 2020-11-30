const {
    BN,
    expectRevert,
    expectEvent,
    time,
    balance,
} = require('openzeppelin-test-helpers');
const chai = require('chai');
const { expect } = require('chai');
const chaiAsPromised = require('chai-as-promised');

chai.use(chaiAsPromised);
const UnitTestSFC = artifacts.require('UnitTestSFC');
const StakersConstants = artifacts.require('StakersConstants');

function amount18(n) {
    return new BN(web3.utils.toWei(n, 'ether'));
}

class BlockchainNode {
    constructor(sfc, minter) {
        this.validators = {};
        this.nextValidators = {};
        this.sfc = sfc;
        this.minter = minter;
    }

    async handle(tx) {
        for (let i = 0; i < tx.logs.length; i += 1) {
            if (tx.logs[i].event === 'UpdatedValidatorWeight') {
                if (tx.logs[i].args.weight.isZero()) {
                    delete this.nextValidators[tx.logs[i].args.validatorID.toString()];
                } else {
                    this.nextValidators[tx.logs[i].args.validatorID.toString()] = tx.logs[i].args.weight;
                }
            }
            if (tx.logs[i].event === 'IncBalance') {
                if (tx.logs[i].args.acc !== this.sfc.address) {
                    throw 'unexpected IncBalance account';
                }
                await this.sfc.sendTransaction({
                    from: this.minter,
                    value: tx.logs[i].args.value,
                });
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
        await this.handle(await this.sfc._sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees));
        await this.handle(await this.sfc._sealEpochValidators(nextValidatorIDs));
        this.validators = this.nextValidators;
        // clone this.nextValidators
        this.nextValidators = {};
        for (const vid in this.validators) {
            this.nextValidators[vid] = this.validators[vid];
        }
    }
}

const pubkey = '0x00a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc525f';

contract('SFC', async() => {
    describe('Test minSelfStake from StakersConstants', () => {
        it('Should not be possible to call function with modifier NotInitialized if contract is not initialized', async() => {
            this.sfc = await StakersConstants.new();
            expect((await this.sfc.minSelfStake()).toString()).to.equals('3175000000000000000000000');
        });
    });
})

contract('SFC', async([account1]) => {
    beforeEach(async () => {
        this.sfc = await UnitTestSFC.new();
    });

    describe('Test initializable', () => {
        it('Should not be possible to call function with modifier NotInitialized if contract is not initialized', async() => {
            await expect(this.sfc._setGenesisValidator(account1, 1, pubkey, 0, await this.sfc.currentEpoch(), Date.now(), 0, 0)).to.be.fulfilled
        });
    });
});

contract('SFC', async ([firstValidator, secondValidator, thirdValidator]) => {
    beforeEach(async () => {
        this.sfc = await UnitTestSFC.new();
        await this.sfc.initialize(0);
        await this.sfc.rebaseTime();
        this.node = new BlockchainNode(this.sfc, firstValidator);
    });

    describe('Basic functions', () => {
        describe('Constants', () => {
            it('Returns current Epoch', async () => {
                expect((await this.sfc.currentEpoch()).toString()).to.equals('1');
            });

            it('Returns minimum amount to stake for a Validator', async () => {
                expect((await this.sfc.minSelfStake()).toString()).to.equals('3175000000000000000');
            });

            it('Returns the maximum ratio of delegations a validator can have', async () => {
                expect((await this.sfc.maxDelegatedRatio()).toString()).to.equals('16000000000000000000');
            });

            it('Returns commission fee in percentage a validator will get from a delegation', async () => {
                expect((await this.sfc.validatorCommission()).toString()).to.equals('150000000000000000');
            });

            it('Returns commission fee in percentage a validator will get from a contract', async () => {
                expect((await this.sfc.contractCommission()).toString()).to.equals('300000000000000000');
            });

            it('Returns the ratio of the reward rate at base rate (without lockup)', async () => {
                expect((await this.sfc.unlockedRewardRatio()).toString()).to.equals('300000000000000000');
            });

            it('Returns the minimum duration of a stake/delegation lockup', async () => {
                expect((await this.sfc.minLockupDuration()).toString()).to.equals('1209600');
            });

            it('Returns the maximum duration of a stake/delegation lockup', async () => {
                expect((await this.sfc.maxLockupDuration()).toString()).to.equals('31536000');
            });

            it('Returns the period of time that stake is locked', async () => {
                expect((await this.sfc.stakeLockPeriodTime()).toString()).to.equals('604800');
            });

            it('Returns the number of epochs that stake is locked', async () => {
                expect((await this.sfc.unstakePeriodEpochs()).toString()).to.equals('3');
            });

            it('Returns the period of time that stake is locked', async () => {
                expect((await this.sfc.stakeLockPeriodTime()).toString()).to.equals('604800');
            });

            it('Returns the number of Time that stake is locked', async () => {
                expect((await this.sfc.unstakePeriodTime()).toString()).to.equals('604800');
            });

            it('Returns the number of epochs to lock a delegation', async () => {
                expect((await this.sfc.delegationLockPeriodEpochs()).toString()).to.equals('3');
            });

            it('Returns the version of the current implementation', async () => {
                expect((await this.sfc.version()).toString()).to.equals('0x323032');
            });

            it('Should create a Validator and return the ID', async () => {
                await this.sfc.createValidator(pubkey, {
                    from: secondValidator,
                    value: amount18('10'),
                });
                const lastValidatorID = await this.sfc.lastValidatorID();

                expect(lastValidatorID.toString()).to.equals('1');
            });

            it('Should create two Validators and return the correct last validator ID', async () => {
                let lastValidatorID;
                await this.sfc.createValidator(pubkey, {
                    from: secondValidator,
                    value: amount18('10'),
                });
                lastValidatorID = await this.sfc.lastValidatorID();

                expect(lastValidatorID.toString()).to.equals('1');

                await this.sfc.createValidator(pubkey, {
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
                (await this.sfc.stake(1, { from: secondValidator, value: 1 }));
            });

            it('Should reject if amount is insufficient for self-stake', async () => {
                expect((await this.sfc.minSelfStake()).toString()).to.equals('3175000000000000000');
                await expect(this.sfc.createValidator(pubkey, {
                    from: secondValidator,
                    value: amount18('3'),
                })).to.be.rejectedWith('Returned error: VM Exception while processing transaction: revert insufficient self-stake -- Reason given: insufficient self-stake.');
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
                expect(await this.sfc.isOwner({ from: thirdValidator})).to.equals(false);
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

            it('Should not be able to transfer ownership if not owner', async() => {
                await expect( this.sfc.transferOwnership(secondValidator, {from: secondValidator})).to.be.rejectedWith(Error);
            });

            it('Should not be able to transfer ownership to address(0)', async() => {
                await expect( this.sfc.transferOwnership('0x0000000000000000000000000000000000000000')).to.be.rejectedWith(Error);
            });

        });
    });
});

contract('SFC', async ([firstValidator, secondValidator, thirdValidator, firstDelegator, secondDelegator, thirdDelegator]) => {
    beforeEach(async () => {
        this.sfc = await UnitTestSFC.new();
        await this.sfc.initialize(10);
        await this.sfc.rebaseTime();
        this.node = new BlockchainNode(this.sfc, firstValidator);
    });

    describe('Prevent Genesis Call if not Initialized', () => {
        it('Should not be possible add a Genesis Validator if contract has been initialized', async () => {
            await expect(this.sfc._setGenesisValidator(secondValidator, 1, pubkey, 0, await this.sfc.currentEpoch(), Date.now(), 0, 0)).to.be.rejectedWith('Returned error: VM Exception while processing transaction: revert Contract instance has already been initialized -- Reason given: Contract instance has already been initialized.');
        });

        it('Should not be possible add a Genesis Delegation if contract has been initialized', async () => {
            await expect(this.sfc._setGenesisDelegation(firstDelegator, 1, 100, 1000)).to.be.rejectedWith('Returned error: VM Exception while processing transaction: revert Contract instance has already been initialized -- Reason given: Contract instance has already been initialized.');
        });
    });

    describe('Create validators', () => {
        it('Should create Validators', async () => {
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            await expect(this.sfc.createValidator(pubkey, {
                from: secondValidator,
                value: amount18('15'),
            })).to.be.fulfilled;
            await expect(this.sfc.createValidator(pubkey, {
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
            await expect(this.sfc.createValidator(pubkey, {
                from: secondValidator,
                value: amount18('15'),
            })).to.be.fulfilled;
            expect((await this.sfc.getValidatorID(secondValidator)).toString()).to.equals('2');
            await expect(this.sfc.createValidator(pubkey, {
                from: thirdValidator,
                value: amount18('20'),
            })).to.be.fulfilled;
            expect((await this.sfc.getValidatorID(thirdValidator)).toString()).to.equals('3');
        });

        it('Should not be able to stake if Validator not created yet', async () => {
            await expect(this.sfc.stake(1, {
                from: firstDelegator,
                value: amount18('10'),
            })).to.be.rejectedWith('Returned error: VM Exception while processing transaction: revert validator doesn\'t exist -- Reason given: validator doesn\'t exist');
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;

            await expect(this.sfc.stake(2, {
                from: secondDelegator,
                value: amount18('10'),
            })).to.be.rejectedWith('Returned error: VM Exception while processing transaction: revert validator doesn\'t exist -- Reason given: validator doesn\'t exist');
            await expect(this.sfc.createValidator(pubkey, {
                from: secondValidator,
                value: amount18('15'),
            })).to.be.fulfilled;

            await expect(this.sfc.stake(3, {
                from: thirdDelegator,
                value: amount18('10'),
            })).to.be.rejectedWith('Returned error: VM Exception while processing transaction: revert validator doesn\'t exist -- Reason given: validator doesn\'t exist');
            await expect(this.sfc.createValidator(pubkey, {
                from: thirdValidator,
                value: amount18('20'),
            })).to.be.fulfilled;
        });

        it('Should stake with different delegators', async () => {
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            expect(await this.sfc.stake(1, { from: firstDelegator, value: amount18('11') }));

            await expect(this.sfc.createValidator(pubkey, {
                from: secondValidator,
                value: amount18('15'),
            })).to.be.fulfilled;
            expect(await this.sfc.stake(2, { from: secondDelegator, value: amount18('10') }));

            await expect(this.sfc.createValidator(pubkey, {
                from: thirdValidator,
                value: amount18('20'),
            })).to.be.fulfilled;
            expect(await this.sfc.stake(3, { from: thirdDelegator, value: amount18('10') }));
            expect(await this.sfc.stake(1, { from: firstDelegator, value: amount18('10') }));
        });

        it('Should return the amount of delegated for each Delegator', async () => {
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            await this.sfc.stake(1, { from: firstDelegator, value: amount18('11') });
            expect((await this.sfc.getDelegation(firstDelegator, await this.sfc.getValidatorID(firstValidator))).toString()).to.equals('11000000000000000000');

            await expect(this.sfc.createValidator(pubkey, {
                from: secondValidator,
                value: amount18('15'),
            })).to.be.fulfilled;
            await this.sfc.stake(2, { from: secondDelegator, value: amount18('10') });
            expect((await this.sfc.getDelegation(secondDelegator, await this.sfc.getValidatorID(firstValidator))).toString()).to.equals('0');
            expect((await this.sfc.getDelegation(secondDelegator, await this.sfc.getValidatorID(secondValidator))).toString()).to.equals('10000000000000000000');


            await expect(this.sfc.createValidator(pubkey, {
                from: thirdValidator,
                value: amount18('12'),
            })).to.be.fulfilled;
            await this.sfc.stake(3, { from: thirdDelegator, value: amount18('10') });
            expect((await this.sfc.getDelegation(thirdDelegator, await this.sfc.getValidatorID(thirdValidator))).toString()).to.equals('10000000000000000000');

            await this.sfc.stake(3, { from: firstDelegator, value: amount18('10') });

            expect((await this.sfc.getDelegation(thirdDelegator, await this.sfc.getValidatorID(firstValidator))).toString()).to.equals('0');
            expect((await this.sfc.getDelegation(firstDelegator, await this.sfc.getValidatorID(thirdValidator))).toString()).to.equals('10000000000000000000');
            await this.sfc.stake(3, { from: firstDelegator, value: amount18('1') });
            expect((await this.sfc.getDelegation(firstDelegator, await this.sfc.getValidatorID(thirdValidator))).toString()).to.equals('11000000000000000000');
        });

        it('Should return the total of received Stake', async () => {
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            await this.sfc.stake(1, { from: firstDelegator, value: amount18('11') });
            await this.sfc.stake(1, { from: secondDelegator, value: amount18('8') });
            await this.sfc.stake(1, { from: thirdDelegator, value: amount18('8') });
            const validator = await this.sfc.getValidator(1);

            expect(validator.receivedStake.toString()).to.equals('37000000000000000000');
            // expect(validator.status.toString()).to.equals('0');
            // expect(validator.deactivatedTime.toString()).to.equals('0');
            // expect(validator.deactivatedEpoch.toString()).to.equals('0');
            // expect(validator.receivedStake.toString()).to.equals('37000000000000000000');
            // expect(validator.createdEpoch.toString()).to.equals('0');
            // expect(validator.createdTime.toString()).to.equals('0');
            // expect(validator.auth.toString()).to.equals('0');
        });

        it('Should return the total of received Stake', async () => {
            await expect(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('10'),
            })).to.be.fulfilled;
            await this.sfc.stake(1, { from: firstDelegator, value: amount18('11') });
            await this.sfc.stake(1, { from: secondDelegator, value: amount18('8') });
            await this.sfc.stake(1, { from: thirdDelegator, value: amount18('8') });
            const validator = await this.sfc.getValidator(1);

            expect(validator.receivedStake.toString()).to.equals('37000000000000000000');
        });
    });
});

contract('SFC', async ([firstValidator, secondValidator, thirdValidator, firstDelegator, secondDelegator, thirdDelegator]) => {
    beforeEach(async () => {
        this.sfc = await UnitTestSFC.new();
        await this.sfc.initialize(10);
        await this.sfc.rebaseTime();
        this.node = new BlockchainNode(this.sfc, firstValidator);
    });
    describe('Returns Validator', () => {
        let validator;
        beforeEach(async () => {
            this.sfc = await UnitTestSFC.new();
            await this.sfc.initialize(12);
            await this.sfc.rebaseTime();
            this.node = new BlockchainNode(this.sfc, firstValidator);
            await expect(this.sfc.createValidator(pubkey, { from: firstValidator, value: amount18('10') })).to.be.fulfilled;
            await this.sfc.stake(1, { from: firstDelegator, value: amount18('11') });
            await this.sfc.stake(1, { from: secondDelegator, value: amount18('8') });
            await this.sfc.stake(1, { from: thirdDelegator, value: amount18('8') });
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
            const now = Math.trunc((Date.now()) / 1000);
            expect(validator.createdTime.toNumber()).to.be.within(now - 2, now + 2);
        });

        it('Should returns Validator\'s Auth (address)', async () => {
            expect(validator.auth.toString()).to.equals(firstValidator);
        });
    });

    describe('EpochSnapshot', () => {
        let validator;
        beforeEach(async () => {
            this.sfc = await UnitTestSFC.new();
            await this.sfc.initialize(12);
            await this.sfc.rebaseTime();
            this.node = new BlockchainNode(this.sfc, firstValidator);
            await expect(this.sfc.createValidator(pubkey, { from: firstValidator, value: amount18('10') })).to.be.fulfilled;
            await this.sfc.stake(1, { from: firstDelegator, value: amount18('11') });
            await this.sfc.stake(1, { from: secondDelegator, value: amount18('8') });
            await this.sfc.stake(1, { from: thirdDelegator, value: amount18('8') });
            validator = await this.sfc.getValidator(1);
        });

        it('Returns claimedRewardUntilEpoch', async () => {
            // await this.sfc._updateBaseRewardPerSecond(amount18('0.01'));

            expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('12'));
            expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('13'));
            await this.sfc._sealEpoch([100, 101, 102], [100, 101, 102], [100, 101, 102], [100, 101, 102]);
            expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('13'));
            expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('14'));
            await this.sfc._sealEpoch(
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102]);
            await this.sfc._sealEpoch(
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102]);
            await this.sfc._sealEpoch(
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102]);
            await this.sfc._sealEpoch(
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102],
                [100, 101, 102]);
            expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('17'));
            expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('18'));
            // await this.sfc.advanceTime((24*60*60*30));
            // await this.sfc.stashRewards(firstDelegator, 1);
            // console.log(await this.sfc.pendingRewards(firstDelegator, 1));
            // console.log((await this.sfc.claimedRewardUntilEpoch(firstDelegator, firstValidator)).toString());
        });
    });
    describe('Methods tests', async () => {
        it('checking createValidator function', async () => {
            expect(await this.sfc.lastValidatorID.call()).to.be.bignumber.equal(new BN('0'));
            await expectRevert(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('3.175')
                    .sub(new BN(1)),
            }), 'insufficient self-stake');
            await this.node.handle(await this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('3.175'),
            }));
            await expectRevert(this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('3.175'),
            }), 'validator already exists');
            await this.node.handle(await this.sfc.createValidator(pubkey, {
                from: secondValidator,
                value: amount18('5'),
            }));

            expect(await this.sfc.lastValidatorID.call()).to.be.bignumber.equal(new BN('2'));
            expect(await this.sfc.totalStake.call()).to.be.bignumber.equal(amount18('8.175'));

            const firstValidatorID = await this.sfc.getValidatorID(firstValidator);
            const secondValidatorID = await this.sfc.getValidatorID(secondValidator);
            expect(firstValidatorID).to.be.bignumber.equal(new BN('1'));
            expect(secondValidatorID).to.be.bignumber.equal(new BN('2'));

            expect(await this.sfc.getValidatorPubkey(firstValidatorID)).to.equal(pubkey);
            expect(await this.sfc.getValidatorPubkey(secondValidatorID)).to.equal(pubkey);

            const firstValidatorObj = await this.sfc.getValidator.call(firstValidatorID);
            const secondValidatorObj = await this.sfc.getValidator.call(secondValidatorID);

            // check first validator object
            expect(firstValidatorObj.receivedStake).to.be.bignumber.equal(amount18('3.175'));
            expect(firstValidatorObj.createdEpoch).to.be.bignumber.equal(new BN('11'));
            expect(firstValidatorObj.auth).to.equal(firstValidator);
            expect(firstValidatorObj.status).to.be.bignumber.equal(new BN('0'));
            expect(firstValidatorObj.deactivatedTime).to.be.bignumber.equal(new BN('0'));
            expect(firstValidatorObj.deactivatedEpoch).to.be.bignumber.equal(new BN('0'));

            // check second validator object
            expect(secondValidatorObj.receivedStake).to.be.bignumber.equal(amount18('5'));
            expect(secondValidatorObj.createdEpoch).to.be.bignumber.equal(new BN('11'));
            expect(secondValidatorObj.auth).to.equal(secondValidator);
            expect(secondValidatorObj.status).to.be.bignumber.equal(new BN('0'));
            expect(secondValidatorObj.deactivatedTime).to.be.bignumber.equal(new BN('0'));
            expect(secondValidatorObj.deactivatedEpoch).to.be.bignumber.equal(new BN('0'));

            // check created delegations
            expect(await this.sfc.getDelegation.call(firstValidator, firstValidatorID)).to.be.bignumber.equal(amount18('3.175'));
            expect(await this.sfc.getDelegation.call(secondValidator, secondValidatorID)).to.be.bignumber.equal(amount18('5'));

            // check fired node-related logs
            expect(Object.keys(this.node.nextValidators).length).to.equal(2);
            expect(this.node.nextValidators[firstValidatorID.toString()]).to.be.bignumber.equal(amount18('3.175'));
            expect(this.node.nextValidators[secondValidatorID.toString()]).to.be.bignumber.equal(amount18('5'));
        });

        it('checking sealing epoch', async () => {
            await this.node.handle(await this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('3.175'),
            }));
            await this.node.handle(await this.sfc.createValidator(pubkey, {
                from: secondValidator,
                value: amount18('6.825'),
            }));

            await this.node.sealEpoch(new BN('100'));

            const firstValidatorID = await this.sfc.getValidatorID(firstValidator);
            const secondValidatorID = await this.sfc.getValidatorID(secondValidator);
            expect(firstValidatorID).to.be.bignumber.equal(new BN('1'));
            expect(secondValidatorID).to.be.bignumber.equal(new BN('2'));

            const firstValidatorObj = await this.sfc.getValidator.call(firstValidatorID);
            const secondValidatorObj = await this.sfc.getValidator.call(secondValidatorID);

            await this.node.handle(await this.sfc.stake(firstValidatorID, {
                from: firstValidator,
                value: amount18('1'),
            }));
            await this.node.handle(await this.sfc.createValidator(pubkey, {
                from: thirdValidator,
                value: amount18('4'),
            }));
            const thirdValidatorID = await this.sfc.getValidatorID(thirdValidator);

            // check fired node-related logs
            expect(Object.keys(this.node.validators).length).to.equal(2);
            expect(this.node.validators[firstValidatorID.toString()]).to.be.bignumber.equal(amount18('3.175'));
            expect(this.node.validators[secondValidatorID.toString()]).to.be.bignumber.equal(amount18('6.825'));
            expect(Object.keys(this.node.nextValidators).length).to.equal(3);
            expect(this.node.nextValidators[firstValidatorID.toString()]).to.be.bignumber.equal(amount18('4.175'));
            expect(this.node.nextValidators[secondValidatorID.toString()]).to.be.bignumber.equal(amount18('6.825'));
            expect(this.node.nextValidators[thirdValidatorID.toString()]).to.be.bignumber.equal(amount18('4'));
        });

        it('checking pendingRewards function', async () => {
            await this.sfc._updateBaseRewardPerSecond(amount18('0.01'));

            await this.node.handle(await this.sfc.createValidator(pubkey, {
                from: firstValidator,
                value: amount18('3.175'),
            }));

            expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('10'));
            expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('11'));
            await this.node.sealEpoch(new BN('100'));
            expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('11'));
            expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('12'));

            let firstValidatorID = await this.sfc.getValidatorID(firstValidator);
            await this.node.handle(await this.sfc.stake(firstValidatorID, {
                from: firstDelegator,
                value: amount18('5.0'),
            }));

            const epochMetrics1 = {
                1: {
                    offlineTime: new BN('0'),
                    offlineBlocks: new BN('0'),
                    uptime: new BN('100'),
                    originatedTxsFee: amount18('0.0234'),
                },
            };
            console.log('1');
            console.log((await this.sfc.pendingRewards.call(firstValidator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(firstDelegator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(secondDelegator, firstValidatorID)).toString());
            console.log('----');
            await this.node.sealEpoch(new BN('100'), epochMetrics1);
            expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('12'));
            expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('13'));
            console.log('2');

            console.log((await this.sfc.pendingRewards.call(firstValidator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(firstDelegator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(secondDelegator, firstValidatorID)).toString());
            console.log('----');
            console.log((await this.sfc.getEpochSnapshot.call(new BN('1'))));
            console.log((await this.sfc.getEpochSnapshot.call(new BN('2'))));

            await this.node.handle(await this.sfc.createValidator(pubkey, {
                from: secondValidator,
                value: amount18('3.175'),
            }));
            let secondValidatorID = await this.sfc.getValidatorID(secondValidator);

            await this.node.handle(await this.sfc.createValidator(pubkey, {
                from: thirdValidator,
                value: amount18('10.0'),
            }));
            let thirdValidatorID = await this.sfc.getValidatorID(thirdValidator);

            await this.node.handle(await this.sfc.stake(secondValidatorID, {
                from: firstDelegator,
                value: amount18('3.0'),
            }));
            await this.node.handle(await this.sfc.stake(firstValidatorID, {
                from: secondDelegator,
                value: amount18('10.0'),
            }));

            const epochMetrics2 = {
                1: {
                    offlineTime: new BN('0'),
                    offlineBlocks: new BN('0'),
                    uptime: new BN('50'),
                    originatedTxsFee: amount18('0.0234'),
                },
            };
            await this.node.sealEpoch(new BN('100'), epochMetrics2);
            console.log('3');

            console.log((await this.sfc.getEpochSnapshot.call(new BN('3'))));
            console.log((await this.sfc.pendingRewards.call(firstValidator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(firstDelegator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(secondDelegator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(secondValidator, secondValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(thirdValidator, thirdValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(firstDelegator, secondValidatorID)).toString());
            console.log('----');

            // stash rewards
            console.log('4', 'stashRewards');

            await this.sfc.stashRewards(firstValidator, firstValidatorID);
            await this.sfc.stashRewards(firstDelegator, firstValidatorID);
            console.log((await this.sfc.pendingRewards.call(firstValidator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(firstDelegator, firstValidatorID)).toString());
            console.log('----');

            const epochMetrics3 = {
                1: {
                    offlineTime: new BN('0'),
                    offlineBlocks: new BN('0'),
                    uptime: new BN('50'),
                    originatedTxsFee: amount18('0.01'),
                },
                2: {
                    offlineTime: new BN('0'),
                    offlineBlocks: new BN('0'),
                    uptime: new BN('500'),
                    originatedTxsFee: amount18('0.1'),
                },
                3: {
                    offlineTime: new BN('500'),
                    offlineBlocks: new BN('10'),
                    uptime: new BN('0'),
                    originatedTxsFee: amount18('0.0'),
                },
            };
            await this.node.sealEpoch(new BN('500'), epochMetrics3);
            console.log('5');

            console.log((await this.sfc.getEpochSnapshot.call(new BN('4'))));
            console.log((await this.sfc.pendingRewards.call(firstValidator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(firstDelegator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(secondDelegator, firstValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(secondValidator, secondValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(thirdValidator, thirdValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(firstDelegator, secondValidatorID)).toString());
            console.log((await this.sfc.pendingRewards.call(secondDelegator, secondValidatorID)).toString());

        });
    });
});



contract('SFC', async ([firstValidator, secondValidator, thirdValidator, firstDelegator, secondDelegator, thirdDelegator]) => {
    beforeEach(async () => {
        this.firstEpoch = 10;
        this.sfc = await UnitTestSFC.new();
        await this.sfc.initialize(0);
        await this.sfc.rebaseTime();
        // this.node = new BlockchainNode(this.sfc, firstValidator);
        // this.validatorComission = new BN('150000'); // 0.15
        await this.sfc.createValidator(pubkey, {
            from: firstValidator,
            value: amount18('10'),
        });
        await this.sfc.createValidator(pubkey, {
            from: secondValidator,
            value: amount18('10'),
        });
        await this.sfc.createValidator(pubkey, {
            from: thirdValidator,
            value: amount18('10'),
        });
    });

    describe('Basic functions', () => {
        it('Returns current Epoch', async () => {
            expect((await this.sfc.currentEpoch()).toString()).to.equals('1');
        });

        // it('Should create a Validator and return the ID', async () => {
        //     await this.sfc.createValidator(pubkey, {
        //         from: secondValidator,
        //         value: amount18('10'),
        //     });
        //     const lastValidatorID = await this.sfc.lastValidatorID();
        //
        //     expect(lastValidatorID.toString()).to.equals('1');
        // });

        // it('Should create two Validators and return the correct last validator ID', async () => {
        //     let lastValidatorID;
        //     await this.sfc.createValidator(pubkey, {
        //         from: secondValidator,
        //         value: amount18('10'),
        //     });
        //     lastValidatorID = await this.sfc.lastValidatorID();
        //
        //     expect(lastValidatorID.toString()).to.equals('1');
        //
        //     await this.sfc.createValidator(pubkey, {
        //         from: thirdValidator,
        //         value: amount18('12'),
        //     });
        //     lastValidatorID = await this.sfc.lastValidatorID();
        //     expect(lastValidatorID.toString()).to.equals('2');
        // });

        // it('Should returns Delegation', async () => {
        //     await this.sfc.createValidator(pubkey, {
        //         from: secondValidator,
        //         value: amount18('10'),
        //     });
        //
        //     (await this.sfc.stake(1, { from: secondValidator, value: 1 }));
        //
        //     console.log((await this.sfc.getDelegation(secondValidator, 1)).toString());
        //     await time.increase(60 * 60 * 24);
        //     console.log((await this.sfc.getDelegation(secondValidator, 1)).toString());
        //     // console.log((await this.sfc.getValidator(1)).receivedStake().toString());
        //
        //     let validator = await this.sfc.getValidator(1);
        //     console.log(validator.receivedStake.toString());
        //     await time.increase(60 * 60 * 24);
        //     validator = await this.sfc.getValidator(1);
        //     console.log(validator.receivedStake.toString());
        //
        //     console.log((await this.sfc.pendingRewards(secondValidator, 1)).toString());
        // });
    });
});
