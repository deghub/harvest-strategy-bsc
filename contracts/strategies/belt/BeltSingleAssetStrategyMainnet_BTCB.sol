//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./BeltSingleAssetStrategy.sol";

contract BeltSingleAssetStrategyMainnet_BTCB is BeltSingleAssetStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address btcb = address(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
    address belt = address(0xE0e514c71282b6f4e823703a39374Cf58dc3eA4f);
    address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    BeltSingleAssetStrategy.initialize(
      _storage,
      btcb,
      _vault,
      address(0x51bd63F240fB13870550423D208452cA87c44444), // stakingPool
      belt
    );
    pancake_path = [belt, wbnb, btcb];
  }
}
