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

    // TO-ASK: what happens with existing memberships if
    // the expiration term and grace period are updated?
    uint256 public expirationTerm;
    uint256 public gracePeriod;

    // TODO END

    enum MembershipStatus {
        // TODO use in getter to determine state of membership?
        NonExistent,
        Active,
        GracePeriod,
        Expired,
        ErasedAwaitsWithdrawal,
        Erased
    }

    uint public totalRateLimitPerEpoch;

    mapping(uint256 => MembershipDetails) public memberships;
    uint256 public head = 0;
    uint256 public tail = 0;
    uint256 private nextID = 0;

    struct MembershipDetails {
        address holder;
        // TODO: should we store the commitment?
        uint256 expirationDate;
        uint256 rateLimit;
        address token;
        uint256 amount;
        uint prev; // index of the previous membership
        uint next; // index of the next membership
    }

    // TODO: should it contain the commitment?
    event ExpiredMembership(uint256 membershipMapIndex, address holder);
    // TODO: should it contain the commitment?
    event MembershipExtended(uint256 membershipMapIndex, uint256 newExpirationDate);

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
        // TODO: for each commitment
        (address token, uint amount) = priceCalculator.calculate(_rateLimit);
        acquireRateLimit(_sender, commitments, _rateLimit, token, amount);
        transferMembershipFees(_sender, token, amount * _rateLimit * commitments.length);
    }

    function transferMembershipFees(address _from, address _token, uint _amount) internal {
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
        // TODO: for each commitment
        if (_rateLimit < minRateLimitPerMembership || _rateLimit > maxRateLimitPerMembership)
            revert InvalidRateLimit();

        // Attempt to free expired membership slots
        while (totalRateLimitPerEpoch + _rateLimit > maxTotalRateLimitPerEpoch) {
            // Determine if there are any available spot in the membership map
            // by looking at the oldest membership. If it's expired, we can free it
            MembershipDetails storage oldestMembershipDetails = memberships[head];

            if (
                oldestMembershipDetails.holder != address(0) && // membership has a holder
                isExpired(oldestMembershipDetails.expirationDate)
            ) {
                emit ExpiredMembership(head, oldestMembershipDetails.holder);

                // Deduct the expired membership rate limit
                totalRateLimitPerEpoch -= oldestMembershipDetails.rateLimit;

                // Remove the expired membership
                uint256 nextOld = oldestMembershipDetails.next;
                if (nextOld != 0) memberships[nextOld].prev = 0;

                delete memberships[head];

                if (tail == head) {
                    // TODO: test this
                    tail = 0;
                }
                head = nextOld;

                // TODO: move balance from expired to the current holder
            } else {
                revert ExceedMaxRateLimitPerEpoch();
            }
        }

        nextID++;

        uint256 prev = 0;
        if (tail != 0) {
            MembershipDetails storage latestMembership = memberships[tail];
            latestMembership.next = nextID;
            prev = tail;
        } else {
            // First item
            head = nextID;
        }

        totalRateLimitPerEpoch += _rateLimit;

        memberships[nextID] = MembershipDetails({
            holder: _sender,
            expirationDate: block.timestamp + expirationTerm,
            token: _token,
            amount: _amount,
            rateLimit: _rateLimit,
            next: 0, // It's the last value, so point to nowhere
            prev: prev
        });

        tail = nextID;
    }

    function extendMembership(address _sender, uint256[] calldata membershipMapIdx) public {
        for (uint256 i = 0; i < membershipMapIdx.length; i++) {
            uint256 idx = membershipMapIdx[i];

            MembershipDetails storage mdetails = memberships[idx];

            if (!_isGracePeriod(mdetails.expirationDate)) revert NotInGracePeriod(idx);

            if (_sender != mdetails.holder) revert NotHolder(idx);

            uint256 newExpirationDate = block.timestamp + expirationTerm;

            // Remove current membership references
            if (mdetails.prev != 0) {
                memberships[mdetails.prev].next = mdetails.next;
            } else {
                head = mdetails.next;
            }

            if (mdetails.next != 0) {
                memberships[mdetails.next].prev = mdetails.prev;
            } else {
                tail = mdetails.prev;
            }

            // Move membership to the end (since it will be the newest)
            mdetails.next = 0;
            mdetails.prev = tail;
            mdetails.expirationDate = newExpirationDate;

            memberships[tail].next = idx;
            tail = idx;

            emit MembershipExtended(idx, newExpirationDate);
        }
    }

    function _isExpired(uint256 expirationDate) internal view returns (bool) {
        return expirationDate + gracePeriod > block.timestamp;
    }

    function isExpired(uint256 membershipMapIdx) public view returns (bool) {
        return _isExpired(memberships[membershipMapIdx].expirationDate);
    }

    function _isGracePeriod(uint256 expirationDate) internal view returns (bool) {
        return block.timestamp >= expirationDate && block.timestamp <= expirationDate + gracePeriod;
    }

    function isGracePeriod(uint256 membershipMapIdx) public view returns (bool) {
        uint256 expirationDate = memberships[membershipMapIdx].expirationDate;
        return _isGracePeriod(expirationDate);
    }

    function freeExpiredMemberships(uint256[] calldata expiredMemberships) public {
        // TODO: user can pass a list of expired memberships and free them
        // Might be useful because then offchain the user can determine which 
        // expired memberships slots are available, and proceed to free them.
        // This might be cheaper than the `while` loop used when registering
        // memberships, although easily solved by having a function that receives
        // the list of memberships to free, and the information for the new 
        // membership to register
    }

    function withdraw() public {
        // TODO:
    }

    // TODO - keep track of balances, use msg.sender

    function getOldestMembership() public view returns (MembershipDetails memory) {
        return memberships[head];
    }
}
