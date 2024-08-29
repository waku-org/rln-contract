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
error NotExpired(uint256 membershipMapIdx);
error NotHolder(uint256 membershipMapIdx);

error InsufficientBalance();
error FailedTransfer();

contract Membership {
    using SafeERC20 for IERC20;

    // TODO START - add owned setters to all these variables

    IPriceCalculator public priceCalculator;

    /// @notice Maximum total rate limit of all memberships in the tree
    uint32 public maxTotalRateLimitPerEpoch; // TO-ASK: what's the theoretical maximum rate limit per epoch we could set? uint32 accepts a max of 4292967295

    /// @notice Maximum rate limit of one membership
    uint16 public maxRateLimitPerMembership; // TO-ASK: what's the theoretical maximum rate limit per epoch a single membership can have? this accepts 65535

    /// @notice Minimum rate limit of one membership
    uint16 public minRateLimitPerMembership; // TO-ASK: what's the theoretical largest minimum rate limit per epoch a single membership can have? this accepts a minimum from 0 to 65535

    // TO-ASK: what happens with existing memberships if
    // the expiration term and grace period are updated?

    /// @notice Membership expiration term
    uint32 public expirationTerm; // TO-ASK - confirm maximum expiration term possible

    /// @notice Membership grace period
    uint32 public gracePeriod; // TOTO-ASKDO - confirm maximum expiration term possible

    // TODO END

    /// @notice balances available to withdraw
    mapping(address => mapping(address => uint)) public balancesToWithdraw; // holder ->  token -> balance

    /// @notice Total rate limit of all memberships in the tree
    uint public totalRateLimitPerEpoch;

    /// @notice List of registered memberships
    mapping(uint256 => MembershipDetails) public memberships;

    /// @dev Oldest membership
    uint256 private head = 0;

    /// @dev Newest membership
    uint256 private tail = 0;

    /// @dev Autoincrementing ID for memberships
    uint256 private nextID = 0;

    // TODO: associate membership details with commitment

    struct MembershipDetails {
        // Double linked list pointers
        uint256 prev; // index of the previous membership
        uint256 next; // index of the next membership
        // Membership data
        uint256 amount;
        uint256 gracePeriodStartDate;
        uint32 gracePeriod;
        uint16 rateLimit;
        address holder;
        address token;
    }

    // TODO: should it contain the commitment?
    event ExpiredMembership(uint256 membershipMapIndex, address holder);
    // TODO: should it contain the commitment?
    event MembershipExtended(uint256 membershipMapIndex, uint256 newExpirationDate);

    function __Membership_init(
        address _priceCalculator,
        uint32 _maxTotalRateLimitPerEpoch,
        uint16 _maxRateLimitPerMembership,
        uint16 _minRateLimitPerMembership,
        uint32 _expirationTerm,
        uint32 _gracePeriod
    ) internal {
        priceCalculator = IPriceCalculator(_priceCalculator);
        maxTotalRateLimitPerEpoch = _maxTotalRateLimitPerEpoch;
        maxRateLimitPerMembership = _maxRateLimitPerMembership;
        minRateLimitPerMembership = _minRateLimitPerMembership;
        expirationTerm = _expirationTerm;
        gracePeriod = _gracePeriod;
    }

    function _addMembership(
        address _sender,
        uint256[] memory commitments,
        uint16 _rateLimit
    ) internal {
        // TODO: for each commitment
        (address token, uint256 amount) = priceCalculator.calculate(_rateLimit);
        _setupMembershipDetails(_sender, commitments, _rateLimit, token, amount);
        _transferFees(_sender, token, amount * _rateLimit * commitments.length);
    }

    function _transferFees(address _from, address _token, uint256 _amount) internal {
        if (_token == address(0)) {
            if (msg.value != _amount) revert IncorrectAmount();
        } else {
            if (msg.value != 0) revert OnlyTokensAccepted();
            IERC20(_token).safeTransferFrom(_from, address(this), _amount);
        }
    }

    function _setupMembershipDetails(
        address _sender,
        uint256[] memory _commitments,
        uint16 _rateLimit,
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
            MembershipDetails memory oldestMembershipDetails = memberships[head];

            if (
                oldestMembershipDetails.holder != address(0) && // membership has a holder
                isExpired(oldestMembershipDetails.gracePeriodStartDate)
            ) {
                emit ExpiredMembership(head, oldestMembershipDetails.holder);

                // Deduct the expired membership rate limit
                totalRateLimitPerEpoch -= oldestMembershipDetails.rateLimit;

                // Promote the next oldest membership to oldest
                uint256 nextOldestId = oldestMembershipDetails.next;
                head = nextOldestId;
                if (nextOldestId != 0) {
                    memberships[nextOldestId].prev = 0;
                }

                // Move balance from expired membership to holder balance
                balancesToWithdraw[oldestMembershipDetails.holder][
                    oldestMembershipDetails.token
                ] += oldestMembershipDetails.amount;

                delete memberships[head];
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
            // TODO: test adding memberships after the list has been emptied
            head = nextID;
        }

        totalRateLimitPerEpoch += _rateLimit;

        memberships[nextID] = MembershipDetails({
            holder: _sender,
            gracePeriodStartDate: block.timestamp + expirationTerm,
            gracePeriod: gracePeriod,
            token: _token,
            amount: _amount,
            rateLimit: _rateLimit,
            next: 0, // It's the last value, so point to nowhere
            prev: prev
        });

        tail = nextID;
    }

    function _extendMembership(address _sender, uint256[] calldata membershipMapIdx) public {
        for (uint256 i = 0; i < membershipMapIdx.length; i++) {
            uint256 idx = membershipMapIdx[i];

            MembershipDetails storage mdetails = memberships[idx];

            if (!_isGracePeriod(mdetails.gracePeriodStartDate, mdetails.gracePeriod))
                revert NotInGracePeriod(idx);

            if (_sender != mdetails.holder) revert NotHolder(idx);

            uint256 newExpirationDate = block.timestamp + expirationTerm;

            uint256 mdetailsNext = mdetails.next;
            uint256 mdetailsPrev = mdetails.prev;

            // Remove current membership references
            if (mdetailsPrev != 0) {
                memberships[mdetailsPrev].next = mdetailsNext;
            } else {
                head = mdetailsNext;
            }

            if (mdetailsNext != 0) {
                memberships[mdetailsNext].prev = mdetailsPrev;
            } else {
                tail = mdetailsPrev;
            }

            // Move membership to the end (since it will be the newest)
            mdetails.next = 0;
            mdetails.prev = tail;
            mdetails.gracePeriodStartDate = newExpirationDate;
            mdetails.gracePeriod = gracePeriod;

            memberships[tail].next = idx;
            tail = idx;

            emit MembershipExtended(idx, newExpirationDate);
        }
    }

    function _isExpired(
        uint256 _gracePeriodStartDate,
        uint256 _gracePeriod
    ) internal view returns (bool) {
        return _gracePeriodStartDate + _gracePeriod > block.timestamp;
    }

    function isExpired(uint256 membershipMapIdx) public view returns (bool) {
        MembershipDetails memory m = memberships[membershipMapIdx];
        return _isExpired(m.gracePeriodStartDate, m.gracePeriod);
    }

    function _isGracePeriod(
        uint256 _gracePeriodStartDate,
        uint256 _gracePeriod
    ) internal view returns (bool) {
        uint256 blockTimestamp = block.timestamp;
        return
            blockTimestamp >= _gracePeriodStartDate &&
            blockTimestamp <= _gracePeriodStartDate + _gracePeriod;
    }

    function isGracePeriod(uint256 membershipMapIdx) public view returns (bool) {
        MembershipDetails memory m = memberships[membershipMapIdx];
        return _isGracePeriod(m.gracePeriodStartDate, m.gracePeriod);
    }

    function eraseExpiredMemberships(uint256[] calldata expiredMembershipsIdx) public {
        // Might be useful because then offchain the user can determine which
        // expired memberships slots are available, and proceed to free them.
        // This might be cheaper than the `while` loop used when registering
        // memberships, although easily solved by having a function that receives
        // the list of memberships to free, and the information for the new
        // membership to register

        for (uint256 i = 0; i < expiredMembershipsIdx.length; i++) {
            uint256 idx = expiredMembershipsIdx[i];
            MembershipDetails memory mdetails = memberships[idx];

            if (!_isExpired(mdetails.gracePeriodStartDate, mdetails.gracePeriod))
                revert NotExpired(idx);

            // TODO: this code is repeated in other places, maybe it
            // makes sense to extract to an internal function?

            // Move balance from expired membership to holder balance
            balancesToWithdraw[mdetails.holder][mdetails.token] += mdetails.amount;

            // Deduct the expired membership rate limit
            totalRateLimitPerEpoch -= mdetails.rateLimit;

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

            delete memberships[idx];
        }
    }

    // TODO: withdraw grace period or expired memberships
    //       should be similar to previous function except that
    //       it will check if the membership is in grace period
    //       or is expired, and also if it's owned by whoever calls
    //       the function.

    function _withdraw(address _sender, address token) internal {
        uint256 amount = balancesToWithdraw[_sender][token];
        require(amount > 0, "Insufficient balance");

        balancesToWithdraw[_sender][token] = 0;
        if (token == address(0)) {
            // ETH
            (bool success, ) = _sender.call{value: amount}("");
            require(success, "eth transfer failed");
        } else {
            IERC20(token).safeTransfer(_sender, amount);
        }
    }

    function oldestMembership() public view returns (MembershipDetails memory) {
        return memberships[head];
    }
}
