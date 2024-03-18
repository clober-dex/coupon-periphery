// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../contracts/external/clober-v2/IController.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "../Constants.sol";

contract MockController {
    using SafeERC20 for IERC20;

    address[] public wrappedCoupons;

    constructor(address[] memory _wrappedCoupons) {
        wrappedCoupons = _wrappedCoupons;
    }

    function execute(
        IController.Action[] calldata actionList,
        bytes[] calldata paramsDataList,
        address[] calldata tokensToSettle,
        IController.ERC20PermitParams[] calldata erc20PermitParamsList,
        IController.ERC721PermitParams[] calldata erc721PermitParamsList,
        uint64 deadline
    ) external payable returns (OrderId[] memory ids) {
        uint256 length = actionList.length;
        for (uint256 i = 0; i < length; ++i) {
            if (actionList[i] == IController.Action.SPEND) {
                IController.SpendOrderParams memory params =
                    abi.decode(paramsDataList[i], (IController.SpendOrderParams));
                if (BookId.unwrap(params.id) == 5123218587801245791363875878418863513309367190045666848596) {
                    IERC20(wrappedCoupons[0]).safeTransferFrom(msg.sender, address(this), params.baseAmount - 1);
                    IERC20(Constants.COUPON_USDC_SUBSTITUTE).safeTransfer(msg.sender, params.baseAmount / 50);
                } else if (BookId.unwrap(params.id) == 2050871663329071981865486441148209933927850794997083594453) {
                    IERC20(wrappedCoupons[1]).safeTransferFrom(msg.sender, address(this), params.baseAmount - 1);
                    IERC20(Constants.COUPON_WETH_SUBSTITUTE).safeTransfer(msg.sender, params.baseAmount / 50);
                }
            } else if (actionList[i] == IController.Action.TAKE) {
                IController.TakeOrderParams memory params = abi.decode(paramsDataList[i], (IController.TakeOrderParams));
                if (BookId.unwrap(params.id) == 3982373688268902797607790123826322480679588654359190790390) {
                    IERC20(Constants.COUPON_WETH_SUBSTITUTE).safeTransferFrom(
                        msg.sender, address(this), params.quoteAmount / 50
                    );
                    IERC20(wrappedCoupons[1]).safeTransfer(msg.sender, params.quoteAmount + 1);
                } else if (BookId.unwrap(params.id) == 5028964825499590552846748960829820796991540535456089637028) {
                    IERC20(Constants.COUPON_USDC_SUBSTITUTE).safeTransferFrom(
                        msg.sender, address(this), params.quoteAmount / 50
                    );
                    IERC20(wrappedCoupons[0]).safeTransfer(msg.sender, params.quoteAmount + 1);
                }
            }
        }
    }

    receive() external payable {}
}
