// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IMultiStrategyTokenImpl {
  function balanceOf(address account) external view returns (uint256);
  function rebalance() public;
  function balance() public view returns (uint256);
  function deposit(uint256 _amount, uint256 _minShares) external;
  function withdraw(uint256 _shares, uint256 _minAmount) external;
}
