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
error NotInGracePeriod(uint256 membershipMapIdx);
error NotHolder(uint256 membershipMapIdx);

contract Membership {
    using SafeERC20 for IERC20;

    // TODO START - add owned setters to all these variables

    IPriceCalculator public priceCalculator;
    uint256 public maxTotalRateLimitPerEpoch;
    uint16 public maxRateLimitPerMembership;
    uint16 public minRateLimitPerMembership;

    uint256 public expirationTerm;
    uint256 public gracePeriod;

    // TODO END

    enum MembershipStatus {
        NonExistent,
        Active,
        GracePeriod,
        Expired,
        ErasedAwaitsWithdrawal,
        Erased
    }

    uint public totalRateLimitPerEpoch;

    mapping(uint256 => MembershipDetails) public memberships;
    uint256 public oldestMembership = 1;
    uint256 public newestMembership = 1;

    struct MembershipDetails {
        address holder;
        // TODO: should we store the commitment?
        uint256 expirationDate;
        address token;
        uint256 amount;
    }

    event ExpiredMembership(uint256 membershipMapIndex, address holder); // TODO: should it contain the commitment?
    event MembershipExtended(
        uint256 membershipMapIndex,
        uint256 newExpirationDate
    ); // TODO: should it contain the commitment?

    function __Membership_init(
        address _priceCalculator,
        uint _maxTotalRateLimitPerEpoch,
        uint16 _maxRateLimitPerMembership,
        uint16 _minRateLimitPerMembership,
        uint _expirationTerm,
        uint _gracePeriod
    ) internal {
        priceCalculator = IPriceCalculator(_priceCalculator);
        maxTotalRateLimitPerEpoch = _maxTotalRateLimitPerEpoch;
        maxRateLimitPerMembership = _maxRateLimitPerMembership;
        minRateLimitPerMembership = _minRateLimitPerMembership;
        expirationTerm = _expirationTerm;
        gracePeriod = _gracePeriod;
    }

    function registerMembership(
        address _sender,
        uint256[] memory commitments,
        uint _rateLimit
    ) internal {
        // TODO: for each commitment?
        (address token, uint amount) = priceCalculator.calculate(_rateLimit);
        acquireRateLimit(_sender, commitments, _rateLimit, token, amount);
        transferMembershipFees(
            _sender,
            token,
            amount * _rateLimit * commitments.length
        );
    }

    function transferMembershipFees(
        address _from,
        address _token,
        uint _amount
    ) internal {
        if (_token == address(0)) {
            if (msg.value != _amount) revert IncorrectAmount();
        } else {
            if (msg.value != 0) revert OnlyTokensAccepted();
            IERC20(_token).safeTransferFrom(_from, address(this), _amount);
        }
    }

    function acquireRateLimit(
        address _sender,
        uint256[] memory _commitments,
        uint256 _rateLimit,
        address _token,
        uint256 _amount
    ) internal {
        // TODO: for each commitment?
        if (
            _rateLimit < minRateLimitPerMembership ||
            _rateLimit > maxRateLimitPerMembership
        ) revert InvalidRateLimit();

        uint newTotalRateLimitPerEpoch = totalRateLimitPerEpoch + _rateLimit;

        if (newTotalRateLimitPerEpoch > maxTotalRateLimitPerEpoch) {
            // Determine if there are any available spot in the membership map
            // by looking at the oldest membership. If it's expired, we can use it
            MembershipDetails storage oldestMembershipDetails = memberships[
                oldestMembership
            ];

            if (isExpired(oldestMembershipDetails.expirationDate)) {
                emit ExpiredMembership(
                    oldestMembership,
                    memberships[oldestMembership].holder
                );
                deleteOldestMembership();
                // TODO: move balance from expired to the current holder
            } else {
                revert ExceedMaxRateLimitPerEpoch();
            }
        }

        newestMembership += 1;
        memberships[newestMembership] = MembershipDetails({
            holder: _sender,
            expirationDate: block.timestamp + expirationTerm,
            token: _token,
            amount: _amount
        });
    }

    function extendMembership(
        address _sender,
        uint256[] memory membershipMapIdx
    ) public {
        for (uint256 i = 0; i < membershipMapIdx.length; i++) {
            uint256 currentMembershipMapIdx = membershipMapIdx[i];

            MembershipDetails storage mdetails = memberships[
                currentMembershipMapIdx
            ];

            if (!_isGracePeriod(mdetails.expirationDate))
                revert NotInGracePeriod(currentMembershipMapIdx);

            if (_sender != mdetails.holder)
                revert NotHolder(currentMembershipMapIdx);

            uint256 newExpirationDate = block.timestamp + expirationTerm;

            // TODO: remove current membership
            // TODO: add membership at the end (since it will be the newest)

            emit MembershipExtended(currentMembershipMapIdx, newExpirationDate);
        }
    }

    function _isExpired(uint256 expirationDate) internal view returns (bool) {
        return expirationDate + gracePeriod > block.timestamp;
    }

    function isExpired(uint256 membershipMapIdx) public view returns (bool) {
        return _isExpired(memberships[membershipMapIdx].expirationDate);
    }

    function _isGracePeriod(
        uint256 expirationDate
    ) internal view returns (bool) {
        return
            block.timestamp >= expirationDate &&
            block.timestamp <= expirationDate + gracePeriod;
    }

    function isGracePeriod(
        uint256 membershipMapIdx
    ) public view returns (bool) {
        uint256 expirationDate = memberships[membershipMapIdx].expirationDate;
        return _isGracePeriod(expirationDate);
    }

    function withdraw() public {}

    // TODO - keep track of balances, use msg.sender

    function getOldestMembership()
        public
        view
        returns (MembershipDetails memory)
    {
        return memberships[oldestMembership];
    }

    function deleteOldestMembership() internal {
        require(newestMembership > oldestMembership);
        delete memberships[oldestMembership];
        oldestMembership += 1;
    }

    function getMembershipLength() public view returns (uint256) {
        return newestMembership - oldestMembership;
    }
}
