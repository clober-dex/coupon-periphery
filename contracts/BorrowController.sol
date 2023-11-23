// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IBorrowController} from "./interfaces/IBorrowController.sol";
import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";
import {LoanPosition} from "./libraries/LoanPosition.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {Controller} from "./libraries/Controller.sol";
import {ERC20PermitParams, PermitSignature, PermitParamsLibrary} from "./libraries/PermitParams.sol";

contract BorrowController is IBorrowController, Controller, IPositionLocker {
    using PermitParamsLibrary for *;
    using EpochLibrary for Epoch;

    ILoanPositionManager private immutable _loanPositionManager;

    modifier onlyPositionOwner(uint256 positionId) {
        if (_loanPositionManager.ownerOf(positionId) != msg.sender) revert InvalidAccess();
        _;
    }

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address loanPositionManager
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _loanPositionManager = ILoanPositionManager(loanPositionManager);
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory result) {
        if (msg.sender != address(_loanPositionManager)) revert InvalidAccess();

        uint256 positionId;
        address user;
        (positionId, user, data) = abi.decode(data, (uint256, address, bytes));
        if (positionId == 0) {
            address collateralToken;
            address debtToken;
            (collateralToken, debtToken, data) = abi.decode(data, (address, address, bytes));
            positionId = _loanPositionManager.mint(collateralToken, debtToken);
            result = abi.encode(positionId);
        }
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);

        uint256 maxPayInterest;
        uint256 minEarnInterest;
        (position.collateralAmount, position.debtAmount, position.expiredWith, maxPayInterest, minEarnInterest) =
            abi.decode(data, (uint256, uint256, Epoch, uint256, uint256));

        (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 collateralDelta, int256 debtDelta) =
        _loanPositionManager.adjustPosition(
            positionId, position.collateralAmount, position.debtAmount, position.expiredWith
        );
        if (collateralDelta < 0) {
            _loanPositionManager.withdrawToken(position.collateralToken, address(this), uint256(-collateralDelta));
        }
        if (debtDelta > 0) _loanPositionManager.withdrawToken(position.debtToken, address(this), uint256(debtDelta));
        if (couponsToMint.length > 0) {
            _loanPositionManager.mintCoupons(couponsToMint, address(this), "");
            _wrapCoupons(couponsToMint);
        }

        _executeCouponTrade(
            user,
            position.debtToken,
            couponsToMint,
            couponsToBurn,
            debtDelta < 0 ? uint256(-debtDelta) : 0,
            maxPayInterest,
            minEarnInterest
        );

        if (collateralDelta > 0) {
            _ensureBalance(position.collateralToken, user, uint256(collateralDelta));
            IERC20(position.collateralToken).approve(address(_loanPositionManager), uint256(collateralDelta));
            _loanPositionManager.depositToken(position.collateralToken, uint256(collateralDelta));
        }
        if (debtDelta < 0) {
            IERC20(position.debtToken).approve(address(_loanPositionManager), uint256(-debtDelta));
            _loanPositionManager.depositToken(position.debtToken, uint256(-debtDelta));
        }
        if (couponsToBurn.length > 0) {
            _unwrapCoupons(couponsToBurn);
            _loanPositionManager.burnCoupons(couponsToBurn);
        }

        _loanPositionManager.settlePosition(positionId);
    }

    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        uint16 loanEpochs,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable nonReentrant wrapETH {
        collateralPermitParams.tryPermit(_getUnderlyingToken(collateralToken), msg.sender, address(this));

        bytes memory lockData =
            abi.encode(collateralAmount, borrowAmount, EpochLibrary.current().add(loanEpochs - 1), maxPayInterest, 0);
        lockData = abi.encode(0, msg.sender, abi.encode(collateralToken, debtToken, lockData));
        bytes memory result = _loanPositionManager.lock(lockData);
        uint256 positionId = abi.decode(result, (uint256));

        _burnAllSubstitute(collateralToken, msg.sender);
        _burnAllSubstitute(debtToken, msg.sender);
        _loanPositionManager.transferFrom(address(this), msg.sender, positionId);
    }

    function adjustPosition(
        uint256 positionId,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        uint256 minEarnInterest,
        uint16 expiredWith,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata collateralPermitParams,
        ERC20PermitParams calldata debtPermitParams
    ) external payable nonReentrant wrapETH {
        positionPermitParams.tryPermitERC721(_loanPositionManager, positionId, address(this));
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        collateralPermitParams.tryPermit(_getUnderlyingToken(position.collateralToken), msg.sender, address(this));
        debtPermitParams.tryPermit(_getUnderlyingToken(position.debtToken), msg.sender, address(this));

        position.collateralAmount = collateralAmount;
        position.debtAmount = borrowAmount;
        position.expiredWith = Epoch.wrap(expiredWith);

        _loanPositionManager.lock(_encodeAdjustData(positionId, position, maxPayInterest, minEarnInterest));

        _burnAllSubstitute(position.collateralToken, msg.sender);
        _burnAllSubstitute(position.debtToken, msg.sender);
    }

    function _encodeAdjustData(uint256 id, LoanPosition memory p, uint256 maxPay, uint256 minEarn)
        internal
        view
        returns (bytes memory)
    {
        bytes memory data = abi.encode(p.collateralAmount, p.debtAmount, p.expiredWith, maxPay, minEarn);
        return abi.encode(id, msg.sender, data);
    }
}
