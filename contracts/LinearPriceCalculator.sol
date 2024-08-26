// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IPriceCalculator} from "./IPriceCalculator.sol";

/// @title Linear Price Calculator to determine the price to acquire a membership
contract LinearPriceCalculator is IPriceCalculator, Ownable {
    address private token;
    uint private pricePerMessage;

    constructor(address _token, uint16 _price) Ownable() {
        token = _token;
        pricePerMessage = _price;
    }

    /// Set accepted token and price per message
    /// @param _token The token accepted by the membership management for RLN
    /// @param _price Price per message per epoch
    function setTokenAndPrice(address _token, uint _price) external onlyOwner {
        token = _token;
        pricePerMessage = _price;
    }

    function calculate(uint _rateLimit) external view returns (address, uint) {
        return (token, _rateLimit * pricePerMessage);
    }

}
