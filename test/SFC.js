const {
    BN,
    expectRevert,
    expectEvent,
    time,
    balance,
} = require('openzeppelin-test-helpers');
const { expect } = require('chai');

const UnitTestSFC = artifacts.require('UnitTestSFC');

function amount18(n) {
    return new BN(web3.utils.toWei(n, 'ether'));
}

function ratio18(n) {
    return new BN(web3.utils.toWei(n, 'ether'));
}

const wei1 = new BN('1');
const wei2 = new BN('2');
const wei3 = new BN('3');

function toValidatorIDs(validators) {
    const arr = [];
    for (const vid in validators) {
        arr.push(vid);
    }
    return arr;
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


contract('SFC', async ([firstValidator, secondValidator, thirdValidator, firstDelegator, secondDelegator, thirdDelegator]) => {
    beforeEach(async () => {
        this.firstEpoch = 0;
        this.sfc = await UnitTestSFC.new();
        await this.sfc.initialize(0);
        await this.sfc.rebaseTime();
        this.node = new BlockchainNode(this.sfc, firstValidator);
        this.validatorComission = new BN('150000'); // 0.15
    });

    describe('Basic functions', () => {
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

        it('Should returns Delegation', async () => {
            await this.sfc.createValidator(pubkey, {
                from: secondValidator,
                value: amount18('10'),
            });

            (await this.sfc.stake(1, { from: secondValidator, value: 1 }));

            // console.log((await this.sfc.getDelegation(secondValidator, 1)).toString());
            // await time.increase(60 * 60 * 24);
            // console.log((await this.sfc.getDelegation(secondValidator, 1)).toString());
            // console.log((await this.sfc.getValidator(1)).receivedStake().toString());
            //
            // let validator = await this.sfc.getValidator(1);
            // console.log(validator.receivedStake.toString());
            // await time.increase(60 * 60 * 24);
            // validator = await this.sfc.getValidator(1);
            // console.log(validator.receivedStake.toString());
            //
            // console.log((await this.sfc.pendingRewards(secondValidator, 1)).toString());
        });

        // it('CHECK IF AMOUNT LESS THAN MINSELFSTAKE', async () => {
        //     expect((await this.sfc.minSelfStake()).toString()).to.equals('3175000000000000000');
        //     await this.sfc.createValidator(pubkey, {
        //         from: secondValidator,
        //         value: amount18('10'),
        //     });
        // });

    });
    // describe('Methods tests', async () => {
    //     it('checking createValidator function', async () => {
    //         const pubkey = '0x00a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc525f';
    //         expect(await this.sfc.lastValidatorID.call()).to.be.bignumber.equal(new BN('0'));
    //         await expectRevert(this.sfc.createValidator(pubkey, {
    //             from: firstValidator,
    //             value: amount18('3.175')
    //                 .sub(wei1),
    //         }), 'insufficient self-stake');
    //         await this.node.handle(await this.sfc.createValidator(pubkey, {
    //             from: firstValidator,
    //             value: amount18('3.175'),
    //         }));
    //         await expectRevert(this.sfc.createValidator(pubkey, {
    //             from: firstValidator,
    //             value: amount18('3.175'),
    //         }), 'validator already exists');
    //         await this.node.handle(await this.sfc.createValidator(pubkey, {
    //             from: secondValidator,
    //             value: amount18('5'),
    //         }));
    //
    //         expect(await this.sfc.lastValidatorID.call()).to.be.bignumber.equal(new BN('2'));
    //         expect(await this.sfc.totalStake.call()).to.be.bignumber.equal(amount18('8.175'));
    //
    //         const firstValidatorID = await this.sfc.getValidatorID(firstValidator);
    //         const secondValidatorID = await this.sfc.getValidatorID(secondValidator);
    //         expect(firstValidatorID).to.be.bignumber.equal(new BN('1'));
    //         expect(secondValidatorID).to.be.bignumber.equal(new BN('2'));
    //
    //         expect(await this.sfc.getValidatorPubkey(firstValidatorID)).to.equal(pubkey);
    //         expect(await this.sfc.getValidatorPubkey(secondValidatorID)).to.equal(pubkey);
    //
    //         const firstValidatorObj = await this.sfc.getValidator.call(firstValidatorID);
    //         const secondValidatorObj = await this.sfc.getValidator.call(secondValidatorID);
    //
    //         // check first validator object
    //         expect(firstValidatorObj.receivedStake).to.be.bignumber.equal(amount18('3.175'));
    //         expect(firstValidatorObj.createdEpoch).to.be.bignumber.equal(new BN('1'));
    //         expect(firstValidatorObj.auth).to.equal(firstValidator);
    //         expect(firstValidatorObj.status).to.be.bignumber.equal(new BN('0'));
    //         expect(firstValidatorObj.deactivatedTime).to.be.bignumber.equal(new BN('0'));
    //         expect(firstValidatorObj.deactivatedEpoch).to.be.bignumber.equal(new BN('0'));
    //
    //         // check second validator object
    //         expect(secondValidatorObj.receivedStake).to.be.bignumber.equal(amount18('5'));
    //         expect(secondValidatorObj.createdEpoch).to.be.bignumber.equal(new BN('1'));
    //         expect(secondValidatorObj.auth).to.equal(secondValidator);
    //         expect(secondValidatorObj.status).to.be.bignumber.equal(new BN('0'));
    //         expect(secondValidatorObj.deactivatedTime).to.be.bignumber.equal(new BN('0'));
    //         expect(secondValidatorObj.deactivatedEpoch).to.be.bignumber.equal(new BN('0'));
    //
    //         // check created delegations
    //         expect(await this.sfc.getDelegation.call(firstValidator, firstValidatorID)).to.be.bignumber.equal(amount18('3.175'));
    //         expect(await this.sfc.getDelegation.call(secondValidator, secondValidatorID)).to.be.bignumber.equal(amount18('5'));
    //
    //         // check fired node-related logs
    //         expect(Object.keys(this.node.nextValidators).length).to.equal(2);
    //         expect(this.node.nextValidators[firstValidatorID.toString()]).to.be.bignumber.equal(amount18('3.175'));
    //         expect(this.node.nextValidators[secondValidatorID.toString()]).to.be.bignumber.equal(amount18('5'));
    //     });
    //
    //     it('checking sealing epoch', async () => {
    //         await this.node.handle(await this.sfc.createValidator(pubkey, {
    //             from: firstValidator,
    //             value: amount18('3.175'),
    //         }));
    //         await this.node.handle(await this.sfc.createValidator(pubkey, {
    //             from: secondValidator,
    //             value: amount18('6.825'),
    //         }));
    //
    //         await this.node.sealEpoch(new BN('100'));
    //
    //         const firstValidatorID = await this.sfc.getValidatorID(firstValidator);
    //         const secondValidatorID = await this.sfc.getValidatorID(secondValidator);
    //         expect(firstValidatorID).to.be.bignumber.equal(new BN('1'));
    //         expect(secondValidatorID).to.be.bignumber.equal(new BN('2'));
    //
    //         const firstValidatorObj = await this.sfc.getValidator.call(firstValidatorID);
    //         const secondValidatorObj = await this.sfc.getValidator.call(secondValidatorID);
    //
    //         await this.node.handle(await this.sfc.stake(firstValidatorID, {
    //             from: firstValidator,
    //             value: amount18('1'),
    //         }));
    //         await this.node.handle(await this.sfc.createValidator(pubkey, {
    //             from: thirdValidator,
    //             value: amount18('4'),
    //         }));
    //         const thirdValidatorID = await this.sfc.getValidatorID(thirdValidator);
    //
    //         // check fired node-related logs
    //         expect(Object.keys(this.node.validators).length).to.equal(2);
    //         expect(this.node.validators[firstValidatorID.toString()]).to.be.bignumber.equal(amount18('3.175'));
    //         expect(this.node.validators[secondValidatorID.toString()]).to.be.bignumber.equal(amount18('6.825'));
    //         expect(Object.keys(this.node.nextValidators).length).to.equal(3);
    //         expect(this.node.nextValidators[firstValidatorID.toString()]).to.be.bignumber.equal(amount18('4.175'));
    //         expect(this.node.nextValidators[secondValidatorID.toString()]).to.be.bignumber.equal(amount18('6.825'));
    //         expect(this.node.nextValidators[thirdValidatorID.toString()]).to.be.bignumber.equal(amount18('4'));
    //     });
    //
    //     it('checking pendingRewards function', async () => {
    //         await this.sfc._updateBaseRewardPerSecond(amount18('0.01'));
    //
    //         await this.node.handle(await this.sfc.createValidator(pubkey, {
    //             from: firstValidator,
    //             value: amount18('3.175'),
    //         }));
    //
    //         expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('0'));
    //         expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('1'));
    //         await this.node.sealEpoch(new BN('100'));
    //         expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('1'));
    //         expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('2'));
    //
    //         let firstValidatorID = await this.sfc.getValidatorID(firstValidator);
    //         await this.node.handle(await this.sfc.stake(firstValidatorID, {
    //             from: firstDelegator,
    //             value: amount18('5.0'),
    //         }));
    //
    //         const epochMetrics1 = {
    //             1: {
    //                 offlineTime: new BN('0'),
    //                 offlineBlocks: new BN('0'),
    //                 uptime: new BN('100'),
    //                 originatedTxsFee: amount18('0.0234'),
    //             },
    //         };
    //         // console.log((await this.sfc.pendingRewards.call(firstValidator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(firstDelegator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(secondDelegator, firstValidatorID)).toString());
    //         // console.log('----');
    //         await this.node.sealEpoch(new BN('100'), epochMetrics1);
    //         expect(await this.sfc.currentSealedEpoch.call()).to.be.bignumber.equal(new BN('2'));
    //         expect(await this.sfc.currentEpoch.call()).to.be.bignumber.equal(new BN('3'));
    //         // console.log((await this.sfc.pendingRewards.call(firstValidator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(firstDelegator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(secondDelegator, firstValidatorID)).toString());
    //         // console.log('----');
    //         // console.log((await this.sfc.getEpochSnapshot.call(new BN('1'))));
    //         // console.log((await this.sfc.getEpochSnapshot.call(new BN('2'))));
    //
    //         await this.node.handle(await this.sfc.createValidator(pubkey, {
    //             from: secondValidator,
    //             value: amount18('3.175'),
    //         }));
    //         let secondValidatorID = await this.sfc.getValidatorID(secondValidator);
    //
    //         await this.node.handle(await this.sfc.createValidator(pubkey, {
    //             from: thirdValidator,
    //             value: amount18('10.0'),
    //         }));
    //         let thirdValidatorID = await this.sfc.getValidatorID(thirdValidator);
    //
    //         await this.node.handle(await this.sfc.stake(secondValidatorID, {
    //             from: firstDelegator,
    //             value: amount18('10.0'),
    //         }));
    //         await this.node.handle(await this.sfc.stake(firstValidatorID, {
    //             from: secondDelegator,
    //             value: amount18('10.0'),
    //         }));
    //
    //         const epochMetrics2 = {
    //             1: {
    //                 offlineTime: new BN('0'),
    //                 offlineBlocks: new BN('0'),
    //                 uptime: new BN('50'),
    //                 originatedTxsFee: amount18('0.0234'),
    //             },
    //         };
    //         await this.node.sealEpoch(new BN('100'), epochMetrics2);
    //         // console.log((await this.sfc.getEpochSnapshot.call(new BN('3'))));
    //         // console.log((await this.sfc.pendingRewards.call(firstValidator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(firstDelegator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(secondDelegator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(secondValidator, secondValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(thirdValidator, thirdValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(firstDelegator, secondValidatorID)).toString());
    //         // console.log('----');
    //
    //         // stash rewards
    //         await this.sfc.stashRewards(firstValidator, firstValidatorID);
    //         await this.sfc.stashRewards(firstDelegator, firstValidatorID);
    //         // console.log((await this.sfc.pendingRewards.call(firstValidator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(firstDelegator, firstValidatorID)).toString());
    //         // console.log('----');
    //
    //         const epochMetrics3 = {
    //             1: {
    //                 offlineTime: new BN('0'),
    //                 offlineBlocks: new BN('0'),
    //                 uptime: new BN('50'),
    //                 originatedTxsFee: amount18('0.01'),
    //             },
    //             2: {
    //                 offlineTime: new BN('0'),
    //                 offlineBlocks: new BN('0'),
    //                 uptime: new BN('500'),
    //                 originatedTxsFee: amount18('0.1'),
    //             },
    //             3: {
    //                 offlineTime: new BN('500'),
    //                 offlineBlocks: new BN('10'),
    //                 uptime: new BN('0'),
    //                 originatedTxsFee: amount18('0.0'),
    //             },
    //         };
    //         await this.node.sealEpoch(new BN('500'), epochMetrics3);
    //         // console.log((await this.sfc.getEpochSnapshot.call(new BN('4'))));
    //         // console.log((await this.sfc.pendingRewards.call(firstValidator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(firstDelegator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(secondDelegator, firstValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(secondValidator, secondValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(thirdValidator, thirdValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(firstDelegator, secondValidatorID)).toString());
    //         // console.log((await this.sfc.pendingRewards.call(secondDelegator, secondValidatorID)).toString());
    //
    //     });
    // });
});


// contract('SFC', async ([firstValidator, secondValidator, thirdValidator, firstDelegator, secondDelegator, thirdDelegator]) => {
//     beforeEach(async () => {
//         this.firstEpoch = 10;
//         this.sfc = await UnitTestSFC.new();
//         await this.sfc.initialize(0);
//         await this.sfc.rebaseTime();
//         // this.node = new BlockchainNode(this.sfc, firstValidator);
//         // this.validatorComission = new BN('150000'); // 0.15
//         await this.sfc.createValidator(pubkey, {
//             from: firstValidator,
//             value: amount18('10'),
//         });
//         await this.sfc.createValidator(pubkey, {
//             from: secondValidator,
//             value: amount18('10'),
//         });
//         await this.sfc.createValidator(pubkey, {
//             from: thirdValidator,
//             value: amount18('10'),
//         });
//     });
//
//     describe('Basic functions', () => {
//         it('Returns current Epoch', async () => {
//             expect((await this.sfc.currentEpoch()).toString()).to.equals('1');
//         });
//
//         it('Should create a Validator and return the ID', async () => {
//             await this.sfc.createValidator(pubkey, {
//                 from: secondValidator,
//                 value: amount18('10'),
//             });
//             const lastValidatorID = await this.sfc.lastValidatorID();
//
//             expect(lastValidatorID.toString()).to.equals('1');
//         });
//
//         it('Should create two Validators and return the correct last validator ID', async () => {
//             let lastValidatorID;
//             await this.sfc.createValidator(pubkey, {
//                 from: secondValidator,
//                 value: amount18('10'),
//             });
//             lastValidatorID = await this.sfc.lastValidatorID();
//
//             expect(lastValidatorID.toString()).to.equals('1');
//
//             await this.sfc.createValidator(pubkey, {
//                 from: thirdValidator,
//                 value: amount18('12'),
//             });
//             lastValidatorID = await this.sfc.lastValidatorID();
//             expect(lastValidatorID.toString()).to.equals('2');
//         });
//
//         it('Should returns Delegation', async () => {
//             await this.sfc.createValidator(pubkey, {
//                 from: secondValidator,
//                 value: amount18('10'),
//             });
//
//             (await this.sfc.stake(1, { from: secondValidator, value: 1 }));
//
//             console.log((await this.sfc.getDelegation(secondValidator, 1)).toString());
//             await time.increase(60 * 60 * 24);
//             console.log((await this.sfc.getDelegation(secondValidator, 1)).toString());
//             // console.log((await this.sfc.getValidator(1)).receivedStake().toString());
//
//             let validator = await this.sfc.getValidator(1);
//             console.log(validator.receivedStake.toString());
//             await time.increase(60 * 60 * 24);
//             validator = await this.sfc.getValidator(1);
//             console.log(validator.receivedStake.toString());
//
//             console.log((await this.sfc.pendingRewards(secondValidator, 1)).toString());
//         });
//     });
// });
