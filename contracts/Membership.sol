// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IPriceCalculator} from "./IPriceCalculator.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/Context.sol";

error IncorrectAmount();
error OnlyTokensAccepted();
error TokenMismatch();

error InvalidRateLimit();
error ExceedMaxRateLimitPerEpoch();

contract Membership {
    using SafeERC20 for IERC20;

    IPriceCalculator public priceCalculator;

    uint public maxTotalRateLimitPerEpoch;
    uint16 public maxRateLimitPerMembership;
    uint16 public minRateLimitPerMembership;

    enum MembershipStatus { Undefined, Active, GracePeriod, Expired, ErasedAwaitsWithdrawal, Erased }

    uint public totalRateLimitPerEpoch;

    function __Membership_init(
        address _priceCalculator,
        uint _maxTotalRateLimitPerEpoch,
        uint16 _maxRateLimitPerMembership,
        uint16 _minRateLimitPerMembership
    ) internal {
        priceCalculator = IPriceCalculator(_priceCalculator);
        maxTotalRateLimitPerEpoch = _maxTotalRateLimitPerEpoch;
        maxRateLimitPerMembership = _maxRateLimitPerMembership;
        minRateLimitPerMembership = _minRateLimitPerMembership;
    }

    function transferMembershipFees(address _from, uint _rateLimit) internal {
        (address token, uint price) = priceCalculator.calculate(_rateLimit);
        if (token == address(0)) {
            if (msg.value != price) revert IncorrectAmount();
        } else {
            if (msg.value != 0) revert OnlyTokensAccepted();
            IERC20(token).safeTransferFrom(_from, address(this), price);
        }
    }

    function acquireRateLimit(uint256[] memory commitments, uint _rateLimit) internal {
        if (
            _rateLimit < minRateLimitPerMembership ||
            _rateLimit > maxRateLimitPerMembership
        ) revert InvalidRateLimit();

        uint newTotalRateLimitPerEpoch = totalRateLimitPerEpoch + _rateLimit;
        if (newTotalRateLimitPerEpoch > maxTotalRateLimitPerEpoch) revert ExceedMaxRateLimitPerEpoch();

        // TODO: store _rateLimit
        // TODO:
        // Epoch length 	epoch 	10 	minutes
        // Membership expiration term 	T 	180 	days
        // Membership grace period 	G 	30 	days
    }
}
