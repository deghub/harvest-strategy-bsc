//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./interface/IMultiStrategyToken.sol";
import "./interface/IMultiStrategyTokenImpl.sol";
import "./interface/IDepositor.sol";

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/pancakeswap/IPancakeRouter02.sol";

contract BeltSingleAssetStrategy is BaseUpgradeableStrategy {
  using SafeMath for uint256;
  using SafeBEP20 for IBEP20;

  address constant public pancakeswapRouterV2 = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);

  address[] public pancake_path;

  constructor() public BaseUpgradeableStrategy() {
  }

  function initialize(
    address _storage,
    address _underlying,
    address _vault,
    address _rewardPool,
    address _rewardToken
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _rewardPool,
      _rewardToken,
      80, // profit sharing numerator
      1000, // profit sharing denominator
      true, // sell
      1e16, // sell floor
      12 hours // implementation change delay
    );

    // require(IMultiStrategyToken(rewardPool()).token == underlying(), "Pool Info does not match underlying");
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function rewardPoolBalance() internal view returns (uint256) {
      return IMultiStrategyTokenImpl(rewardPool()).balanceOf(address(this));
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
  }

  function enterRewardPool() internal {
    uint256 entireBalance = IBEP20(underlying()).balanceOf(address(this));
    IBEP20(underlying()).safeApprove(rewardPool(), 0);
    IBEP20(underlying()).safeApprove(rewardPool(), entireBalance);

    IMultiStrategyTokenImpl(rewardPool()).deposit(entireBalance, 0);
  }

  /*
  *   Resumes the ability to invest into the underlying reward pools
  */
  function continueInvesting() public onlyGovernance {
    _setPausedInvesting(false);
  }

  function setLiquidationPath(address [] memory _route) public onlyGovernance {
    require(_route[0] == rewardToken(), "Path should start with rewardToken");
    pancake_path = _route;
  }

  // We assume that all the tradings can be done on Pancakeswap
  function _liquidateReward() internal {
    uint256 rewardBalance = IBEP20(rewardToken()).balanceOf(address(this));
    if (!sell() || rewardBalance < sellFloor()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), rewardBalance < sellFloor());
      return;
    }

    notifyProfitInRewardToken(rewardBalance);
    uint256 remainingRewardBalance = IBEP20(rewardToken()).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    // allow Pancakeswap to sell our reward
    IBEP20(rewardToken()).safeApprove(pancakeswapRouterV2, 0);
    IBEP20(rewardToken()).safeApprove(pancakeswapRouterV2, remainingRewardBalance);

    // we can accept 1 as minimum because this is called only by a trusted role
    uint256 amountOutMin = 1;

    IPancakeRouter02(pancakeswapRouterV2).swapExactTokensForTokens(
      remainingRewardBalance,
      amountOutMin,
      pancake_path,
      address(this),
      block.timestamp
    );
  }

  function claimAndLiquidateReward() internal {
    uint256 amount = rewardPoolBalance();
    if (amount != 0) {
      IMultiStrategyToken(rewardPool()).withdraw(amount, 0);
    _liquidateReward();
    }
    // if (IBEP20(busd).balanceOf(address(this)) > 0) {
    //   beltFromBusd();
    // }
  }

  // function beltFromBusd() internal {
  //   uint256 busdBalance = IBEP20(busd).balanceOf(address(this));
  //   if (busdBalance > 0) {
  //     IBEP20(busd).safeApprove(depositor(), 0);
  //     IBEP20(busd).safeApprove(depositor(), busdBalance);

  //     // we can accept 0 as minimum, this will be called only by trusted roles
  //     uint256 minimum = 0;
  //     IDepositor(depositor()).add_liquidity([0, 0, 0, busdBalance], minimum);
  //   }
  // }


  /*
  *   Stakes everything the strategy holds into the reward pool
  */
  function investAllUnderlying() internal onlyNotPausedInvesting {
    // this check is needed, because most of the SNX reward pools will revert if
    // you try to stake(0).
    if(IBEP20(underlying()).balanceOf(address(this)) > 0) {
      enterRewardPool();
    }
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawAllToVault() public restricted {
    if (address(rewardPool()) != address(0)) {
      uint256 bal = rewardPoolBalance();
      if (bal != 0) {
        claimAndLiquidateReward();
        IMultiStrategyTokenImpl(rewardPool()).withdraw(bal, 0);
      }
    }
    IBEP20(underlying()).safeTransfer(vault(), IBEP20(underlying()).balanceOf(address(this)));
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawToVault(uint256 amount) public restricted {
    // Typically there wouldn't be any amount here
    // however, it is possible because of the emergencyExit
    uint256 entireBalance = IBEP20(underlying()).balanceOf(address(this));

    if(amount > entireBalance){
      // While we have the check above, we still using SafeMath below
      // for the peace of mind (in case something gets changed in between)
      uint256 needToWithdraw = amount.sub(entireBalance);
      uint256 toWithdraw = MathUpgradeable.min(rewardPoolBalance(), needToWithdraw);
      IMultiStrategyTokenImpl(rewardPool()).withdraw(toWithdraw, 0);
    }

    IBEP20(underlying()).safeTransfer(vault(), amount);
  }

  /*
  *   Note that we currently do not have a mechanism here to include the
  *   amount of reward that is accrued.
  */
  function investedUnderlyingBalance() external view returns (uint256) {
    if (rewardPool() == address(0)) {
      return IBEP20(underlying()).balanceOf(address(this));
    }
    // Adding the amount locked in the reward pool and the amount that is somehow in this contract
    // both are in the units of "underlying"
    // The second part is needed because there is the emergency exit mechanism
    // which would break the assumption that all the funds are always inside of the reward pool
    return rewardPoolBalance().add(IBEP20(underlying()).balanceOf(address(this)));
  }

  /*
  *   Governance or Controller can claim coins that are somehow transferred into the contract
  *   Note that they cannot come in take away coins that are used and defined in the strategy itself
  */
  function salvage(address recipient, address token, uint256 amount) external onlyControllerOrGovernance {
     // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "token is defined as not salvagable");
    IBEP20(token).safeTransfer(recipient, amount);
  }

  /*
  *   Get the reward, sell it in exchange for underlying, invest what you got.
  *   It's not much, but it's honest work.
  *
  *   Note that although `onlyNotPausedInvesting` is not added here,
  *   calling `investAllUnderlying()` affectively blocks the usage of `doHardWork`
  *   when the investing is being paused by governance.
  */
  function doHardWork() external onlyNotPausedInvesting restricted {
    uint256 bal = rewardPoolBalance();
    if (bal != 0) {
      claimAndLiquidateReward();
    }
    investAllUnderlying();
  }

  /**
  * Can completely disable claiming rewards and selling. Good for emergency withdraw in the
  * simplest possible way.
  */
  function setSell(bool s) public onlyGovernance {
    _setSell(s);
  }

  /**
  * Sets the minimum amount needed to trigger a sale.
  */
  function setSellFloor(uint256 floor) public onlyGovernance {
    _setSellFloor(floor);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }
}
