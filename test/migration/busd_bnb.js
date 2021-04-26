// Utilities
const Utils = require("../utilities/Utils.js");
const { impersonates, setupCoreProtocol, depositVault } = require("../utilities/hh-utils.js");

const addresses = require("../../../bsc-config/bsc-addresses.json");

const { send, time, expectRevert } = require("@openzeppelin/test-helpers");
const BigNumber = require("bignumber.js");
const IBEP20 = artifacts.require("IBEP20");

const Vault = artifacts.require("Vault");

const VaultMigratable_Pancake_BUSD_BNB = artifacts.require("VaultMigratable_Pancake_BUSD_BNB");
const VaultProxy = artifacts.require("VaultProxy");

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Pancake BUSD_BNB Migration", function() {
  let accounts;

  // external contracts
  let underlying;

  // external setup, block: 6910211
  let underlyingWhale = "0x63286282fe46eed057c18e108ecf27bd3089c847";

  // parties in the protocol
  let governance;
  let farmer1;

  // numbers used in tests
  let farmerBalance;

  // Core protocol contracts
  let vault;
  let farm;
  let newImplementation;
  let vaultAsProxy;

  async function setupExternalContracts() {
    underlying = await IBEP20.at("0x1B96B92314C44b159149f7E0303511fB2Fc4774f");
    console.log("Fetching Underlying at: ", underlying.address);
  }

  async function setupBalance(){
    let etherGiver = accounts[9];
    // Give whale some ether to make sure the following actions are good
    await send.ether(etherGiver, underlyingWhale, "1" + "000000000000000000");

    farmerBalance = await underlying.balanceOf(underlyingWhale);
    await underlying.transfer(farmer1, farmerBalance, { from: underlyingWhale });
  }

  before(async function() {
    governance = "0xf00dD244228F51547f0563e60bCa65a30FBF5f7f";
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    // impersonate accounts
    await impersonates([governance, underlyingWhale]);

    await setupExternalContracts();
    newImplementation = await VaultMigratable_Pancake_BUSD_BNB.new({
      gas: 5000000
    });

    vault = await Vault.at("0xF7A3a95d0f7E8A5EEaE483Cdd7b76aF287283D34");
    vaultAsNewImplementation = await VaultMigratable_Pancake_BUSD_BNB.at("0xF7A3a95d0f7E8A5EEaE483Cdd7b76aF287283D34");

    vaultAsProxy = await VaultProxy.at(vault.address);

    farm = await IBEP20.at(addresses.bFARM);
    // whale send underlying to farmers
    // await setupBalance();
  });

  describe("Happy path", function() {
    it("Upgrade must succeed and Farmer should earn money", async function() {
      // first, migrating...
      let oldSharePrice;
      let newSharePrice;

      // let farmerOldBalance = new BigNumber(await underlying.balanceOf(farmer1));
      // await depositVault(farmer1, underlying, vault, farmerBalance);

     await vault.scheduleUpgrade(newImplementation.address, {from: governance});
     await Utils.waitHours(13);
      oldSharePrice = new BigNumber(await vault.getPricePerFullShare());
      const oldUnderlyingBalanceWithInvestment = new BigNumber(await vault.underlyingBalanceWithInvestment());
      const oldUnderlying = await vault.underlying();
      const oldStrategy = await vault.strategy();

      await vaultAsProxy.upgrade({from: governance});
      console.log("====Upgraded!! Calling Migrate...");
      const output = await vaultAsNewImplementation.migrateUnderlying(
        "0",
        "0",
        "0",
        "0", {from: governance});
      const logs = output.logs;

      const Migrated = logs.find(e => e.event === 'Migrated');
      const LiquidityRemoved = logs.find(e => e.event === 'LiquidityRemoved');
      const LiquidityProvided = logs.find(e => e.event === 'LiquidityProvided');

      console.log('Migrated');
      console.log('v1Liquidity', Migrated.args[0].toString());
      console.log('v2Liquidity', Migrated.args[1].toString());

      console.log('LiquidityRemoved');
      console.log('v1Liquidity', LiquidityRemoved.args[0].toString());
      console.log('amountDai', LiquidityRemoved.args[1].toString());
      console.log('amountBas', LiquidityRemoved.args[2].toString());

      console.log('LiquidityProvided');
      console.log('basV2Contributed', LiquidityProvided.args[0].toString());
      console.log('daiContributed', LiquidityProvided.args[1].toString());
      console.log('v2Liquidity', LiquidityProvided.args[2].toString());

      newSharePrice = new BigNumber(await vault.getPricePerFullShare());
      const newUnderlyingBalanceWithInvestment = new BigNumber(await vault.underlyingBalanceWithInvestment());
      const newUnderlying = await vault.underlying();
      const newStrategy = await vault.strategy();

      console.log("====Migrated!!");
      console.log(`Underlying: ${oldUnderlying} => ${newUnderlying}`);
      console.log(`Strategy: ${oldStrategy} => ${newStrategy}`);
      console.log(`Underlying balance: ${oldUnderlyingBalanceWithInvestment.toFixed()} => ${newUnderlyingBalanceWithInvestment.toFixed()}`);
      console.log(`Share price: ${oldSharePrice.toFixed()} => ${newSharePrice.toFixed()}`);


      busd = await IBEP20.at("0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56");
      bnb = await IBEP20.at("0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c");
      const f00dBUSD = await busd.balanceOf(governance);
      const f00dBNB = await bnb.balanceOf(governance);

      console.log("f00dBUSD: ", f00dBUSD.toString());
      console.log("f00dBNB:  ", f00dBNB.toString());

      await expectRevert(
        vault.initializeVault(addresses.Storage, addresses.bFARM, 1, 100, {from:farmer1}),
        "Initializable: contract is already initialized"
      );


    });
  });
});
