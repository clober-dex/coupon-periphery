// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Epoch} from "../libraries/Epoch.sol";
import {ERC20PermitParams, PermitSignature} from "../libraries/PermitParams.sol";

interface ISimpleBondController is IERC1155Receiver {
    error InvalidAccess();
    error InvalidValueTransfer();

    function mint(ERC20PermitParams calldata permitParams, address asset, uint256 amount, Epoch expiredWith)
        external
        payable
        returns (uint256 positionId);

    function mintAndWrapCoupons(
        ERC20PermitParams calldata permitParams,
        address asset,
        uint256 amount,
        Epoch expiredWith
    ) external payable returns (uint256 positionId);

    function adjust(
        ERC20PermitParams calldata tokenPermitParams,
        PermitSignature calldata positionPermitParams,
        PermitSignature calldata couponPermitParams,
        uint256 tokenId,
        uint256 amount,
        Epoch expiredWith
    ) external payable;

    function adjustAndWrapCoupons(
        ERC20PermitParams calldata tokenPermitParams,
        PermitSignature calldata positionPermitParams,
        PermitSignature calldata couponPermitParams,
        uint256 tokenId,
        uint256 amount,
        Epoch expiredWith
    ) external payable;

    function withdrawLostToken(address token, address to) external;
}
