// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH9} from "./external/weth/IWETH9.sol";
import {ISubstitute} from "./interfaces/ISubstitute.sol";
import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";
import {ICouponLiquidator} from "./interfaces/ICouponLiquidator.sol";
import {ERC20PermitParams, PermitParamsLibrary} from "./libraries/PermitParams.sol";
import {LoanPosition} from "./libraries/LoanPosition.sol";
import {SubstituteLibrary} from "./libraries/Substitute.sol";

contract CouponLiquidator is ICouponLiquidator, IPositionLocker {
    using SafeERC20 for IERC20;
    using SubstituteLibrary for ISubstitute;
    using PermitParamsLibrary for ERC20PermitParams;

    ILoanPositionManager private immutable _loanPositionManager;
    address private immutable _router;
    IWETH9 internal immutable _weth;

    constructor(address loanPositionManager, address router, address weth) {
        _loanPositionManager = ILoanPositionManager(loanPositionManager);
        _router = router;
        _weth = IWETH9(weth);
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory) {
        (LiquidationType liquidationType, bytes memory lockData) = abi.decode(data, (LiquidationType, bytes));
        if (liquidationType == LiquidationType.WithRouter) {
            return _liquidateWithRouter(abi.decode(lockData, (LiquidateWithRouterParams)));
        } else if (liquidationType == LiquidationType.WithOwnLiquidity) {
            (address payer, LiquidateWithOwnLiquidityParams memory params) =
                abi.decode(lockData, (address, LiquidateWithOwnLiquidityParams));
            return _liquidateWithOwnLiquidity(payer, params);
        } else {
            revert UnsupportedLiquidationType();
        }
    }

    function liquidateWithRouter(LiquidateWithRouterParams calldata params) external {
        bytes memory lockData = abi.encode(params);
        _loanPositionManager.lock(abi.encode(LiquidationType.WithRouter, lockData));
    }

    function _liquidateWithRouter(LiquidateWithRouterParams memory params) internal returns (bytes memory) {
        LoanPosition memory position = _loanPositionManager.getPosition(params.positionId);
        address inToken = ISubstitute(position.collateralToken).underlyingToken();
        address outToken = ISubstitute(position.debtToken).underlyingToken();
        _loanPositionManager.withdrawToken(position.collateralToken, address(this), params.swapAmount);
        _burnAllSubstitute(position.collateralToken, address(this));
        if (inToken == address(_weth)) {
            _weth.deposit{value: params.swapAmount}();
        }
        _swap(inToken, params.swapAmount, params.swapData);

        (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) =
            _loanPositionManager.liquidate(params.positionId, IERC20(outToken).balanceOf(address(this)));

        IERC20(outToken).approve(position.debtToken, repayAmount);
        ISubstitute(position.debtToken).mint(repayAmount, address(this));
        IERC20(position.debtToken).approve(address(_loanPositionManager), repayAmount);
        _loanPositionManager.depositToken(position.debtToken, repayAmount);

        uint256 debtAmount = IERC20(outToken).balanceOf(address(this));
        if (debtAmount > 0) {
            IERC20(outToken).safeTransfer(params.recipient, debtAmount);
        }

        uint256 collateralAmount = liquidationAmount - protocolFeeAmount - params.swapAmount;

        _loanPositionManager.withdrawToken(position.collateralToken, address(this), collateralAmount);
        _burnAllSubstitute(position.collateralToken, params.recipient);

        return "";
    }

    function liquidateWithOwnLiquidity(
        ERC20PermitParams calldata debtPermitParams,
        LiquidateWithOwnLiquidityParams calldata params
    ) external payable {
        if (msg.value > 0) {
            _weth.deposit{value: msg.value}();
        }
        LoanPosition memory position = _loanPositionManager.getPosition(params.positionId);
        debtPermitParams.tryPermit(ISubstitute(position.debtToken).underlyingToken(), msg.sender, address(this));

        bytes memory lockData = abi.encode(msg.sender, params);
        _loanPositionManager.lock(abi.encode(LiquidationType.WithOwnLiquidity, lockData));
    }

    function _liquidateWithOwnLiquidity(address payer, LiquidateWithOwnLiquidityParams memory params)
        internal
        returns (bytes memory)
    {
        LoanPosition memory position = _loanPositionManager.getPosition(params.positionId);
        (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) =
            _loanPositionManager.liquidate(params.positionId, params.maxRepayAmount);

        ISubstitute(position.debtToken).ensureThisBalance(payer, repayAmount);

        IERC20(position.debtToken).approve(address(_loanPositionManager), repayAmount);
        _loanPositionManager.depositToken(position.debtToken, repayAmount);

        uint256 collateralAmount = liquidationAmount - protocolFeeAmount;

        _loanPositionManager.withdrawToken(position.collateralToken, address(this), collateralAmount);
        _burnAllSubstitute(position.collateralToken, params.recipient);

        return "";
    }

    function _swap(address inToken, uint256 inAmount, bytes memory swapParams) internal {
        IERC20(inToken).approve(_router, inAmount);
        (bool success, bytes memory result) = _router.call(swapParams);
        if (!success) revert CollateralSwapFailed(string(result));
        IERC20(inToken).approve(_router, 0);
    }

    function _burnAllSubstitute(address substitute, address to) internal {
        uint256 leftAmount = IERC20(substitute).balanceOf(address(this));
        if (leftAmount == 0) return;
        ISubstitute(substitute).burn(leftAmount, to);
    }

    receive() external payable {}
}
