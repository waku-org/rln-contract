// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IPriceCalculator {
   /// Returns the token and price to pay in `token` for some `_rateLimit`
   /// @param _rateLimit the rate limit the user wants to acquire
   function calculate(uint _rateLimit) external view returns (address, uint);
}