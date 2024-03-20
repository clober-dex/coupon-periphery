// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDepositControllerV2} from "./interfaces/IDepositControllerV2.sol";
import {IBondPositionManager} from "./interfaces/IBondPositionManager.sol";
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";
import {BondPosition} from "./libraries/BondPosition.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {CouponKey} from "./libraries/CouponKey.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {ISubstitute} from "./interfaces/ISubstitute.sol";
import {SubstituteLibrary} from "./libraries/Substitute.sol";
import {ControllerV2} from "./libraries/ControllerV2.sol";
import {ERC20PermitParams, PermitSignature, PermitParamsLibrary} from "./libraries/PermitParams.sol";

contract DepositControllerV2 is IDepositControllerV2, ControllerV2, IPositionLocker {
    using PermitParamsLibrary for *;
    using EpochLibrary for Epoch;

    IBondPositionManager private immutable _bondPositionManager;

    modifier onlyPositionOwner(uint256 positionId) {
        if (_bondPositionManager.ownerOf(positionId) != msg.sender) revert InvalidAccess();
        _;
    }

    constructor(
        address wrapped1155Factory,
        address cloberController,
        address bookManager,
        address couponManager,
        address weth,
        address bondPositionManager
    ) ControllerV2(wrapped1155Factory, cloberController, bookManager, couponManager, weth) {
        _bondPositionManager = IBondPositionManager(bondPositionManager);
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory result) {
        if (msg.sender != address(_bondPositionManager)) revert InvalidAccess();

        uint256 positionId;
        address user;
        (positionId, user, data) = abi.decode(data, (uint256, address, bytes));
        if (positionId == 0) {
            address asset;
            (asset, data) = abi.decode(data, (address, bytes));
            positionId = _bondPositionManager.mint(asset);
            result = abi.encode(positionId);
        }
        BondPosition memory position = _bondPositionManager.getPosition(positionId);

        int256 interestThreshold;
        (position.amount, position.expiredWith, interestThreshold) = abi.decode(data, (uint256, Epoch, int256));
        (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 amountDelta) =
            _bondPositionManager.adjustPosition(positionId, position.amount, position.expiredWith);
        if (amountDelta < 0) _bondPositionManager.withdrawToken(position.asset, address(this), uint256(-amountDelta));
        if (couponsToMint.length > 0) {
            _bondPositionManager.mintCoupons(couponsToMint, address(this), "");
            _wrapCoupons(couponsToMint);
        }

        _executeCouponTrade(user, position.asset, couponsToMint, couponsToBurn, interestThreshold);

        if (amountDelta > 0) {
            _mintSubstituteAll(position.asset, user, uint256(amountDelta));
            IERC20(position.asset).approve(address(_bondPositionManager), uint256(amountDelta));
            _bondPositionManager.depositToken(position.asset, uint256(amountDelta));
        }
        if (couponsToBurn.length > 0) {
            _unwrapCoupons(couponsToBurn);
            _bondPositionManager.burnCoupons(couponsToBurn);
        }

        _bondPositionManager.settlePosition(positionId);
    }

    function deposit(
        address asset,
        uint256 amount,
        Epoch expiredWith,
        int256 minEarnInterest,
        ERC20PermitParams calldata tokenPermitParams
    ) external payable nonReentrant wrapAndRefundETH returns (uint256 positionId) {
        tokenPermitParams.tryPermit(_getUnderlyingToken(asset), msg.sender, address(this));
        bytes memory lockData = abi.encode(amount, expiredWith, -minEarnInterest);
        bytes memory result = _bondPositionManager.lock(abi.encode(0, msg.sender, abi.encode(asset, lockData)));
        positionId = abi.decode(result, (uint256));

        _burnAllSubstitute(asset, msg.sender);

        _bondPositionManager.transferFrom(address(this), msg.sender, positionId);
    }

    function adjust(
        uint256 positionId,
        uint256 amount,
        Epoch expiredWith,
        int256 interestThreshold,
        ERC20PermitParams calldata tokenPermitParams,
        PermitSignature calldata positionPermitParams
    ) external payable nonReentrant wrapAndRefundETH onlyPositionOwner(positionId) {
        positionPermitParams.tryPermit(_bondPositionManager, positionId, address(this));
        BondPosition memory position = _bondPositionManager.getPosition(positionId);
        tokenPermitParams.tryPermit(position.asset, msg.sender, address(this));

        bytes memory lockData = abi.encode(amount, expiredWith, interestThreshold);
        _bondPositionManager.lock(abi.encode(positionId, msg.sender, lockData));

        _burnAllSubstitute(position.asset, msg.sender);
    }
}
