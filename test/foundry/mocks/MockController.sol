// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../contracts/external/clober-v2/IController.sol";

contract MockController {
    function execute(
        Action[] calldata actionList,
        bytes[] calldata paramsDataList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata erc20PermitParamsList,
        ERC721PermitParams[] calldata erc721PermitParamsList,
        uint64 deadline
    ) external payable {

    }

    receive() external payable {}
}
