// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDepositController} from "./interfaces/IDepositController.sol";
import {IBondPositionManager} from "./interfaces/IBondPositionManager.sol";
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";
import {BondPosition} from "./libraries/BondPosition.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {CouponKey} from "./libraries/CouponKey.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Controller} from "./libraries/Controller.sol";
import {ERC20PermitParams, PermitSignature, PermitParamsLibrary} from "./libraries/PermitParams.sol";

contract DepositController is IDepositController, Controller, IPositionLocker {
    using PermitParamsLibrary for *;
    using EpochLibrary for Epoch;

    IBondPositionManager private immutable _bondPositionManager;

    modifier onlyPositionOwner(uint256 positionId) {
        if (_bondPositionManager.ownerOf(positionId) != msg.sender) revert InvalidAccess();
        _;
    }

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address bondPositionManager
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
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

        uint256 maxPayInterest;
        uint256 minEarnInterest;
        (position.amount, position.expiredWith, maxPayInterest, minEarnInterest) =
            abi.decode(data, (uint256, Epoch, uint256, uint256));
        (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 amountDelta) =
            _bondPositionManager.adjustPosition(positionId, position.amount, position.expiredWith);
        if (amountDelta < 0) _bondPositionManager.withdrawToken(position.asset, address(this), uint256(-amountDelta));
        if (couponsToMint.length > 0) {
            _bondPositionManager.mintCoupons(couponsToMint, address(this), "");
            _wrapCoupons(couponsToMint);
        }

        _executeCouponTrade(
            user,
            position.asset,
            couponsToMint,
            couponsToBurn,
            amountDelta > 0 ? uint256(amountDelta) : 0,
            maxPayInterest,
            minEarnInterest
        );

        if (amountDelta > 0) {
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
        uint16 lockEpochs,
        uint256 minEarnInterest,
        ERC20PermitParams calldata tokenPermitParams
    ) external payable nonReentrant wrapETH {
        tokenPermitParams.tryPermit(_getUnderlyingToken(asset), msg.sender, address(this));
        bytes memory lockData = abi.encode(amount, EpochLibrary.current().add(lockEpochs - 1), 0, minEarnInterest);
        bytes memory result = _bondPositionManager.lock(abi.encode(0, msg.sender, abi.encode(asset, lockData)));
        uint256 id = abi.decode(result, (uint256));

        _burnAllSubstitute(asset, msg.sender);

        _bondPositionManager.transferFrom(address(this), msg.sender, id);
    }

    function withdraw(
        uint256 positionId,
        uint256 withdrawAmount,
        uint256 maxPayInterest,
        PermitSignature calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        positionPermitParams.tryPermitERC721(_bondPositionManager, positionId, address(this));
        BondPosition memory position = _bondPositionManager.getPosition(positionId);

        bytes memory lockData = abi.encode(position.amount - withdrawAmount, position.expiredWith, maxPayInterest, 0);
        _bondPositionManager.lock(abi.encode(positionId, msg.sender, lockData));

        _burnAllSubstitute(position.asset, msg.sender);
    }

    function collect(uint256 positionId, PermitSignature calldata positionPermitParams)
        external
        nonReentrant
        onlyPositionOwner(positionId)
    {
        positionPermitParams.tryPermitERC721(_bondPositionManager, positionId, address(this));
        BondPosition memory position = _bondPositionManager.getPosition(positionId);
        if (position.expiredWith >= EpochLibrary.current()) revert NotExpired();

        _bondPositionManager.lock(abi.encode(positionId, msg.sender, abi.encode(0, position.expiredWith, 0, 0)));

        _burnAllSubstitute(position.asset, msg.sender);
    }
}
