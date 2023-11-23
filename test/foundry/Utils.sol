// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {IERC1155Permit} from "../../contracts/interfaces/IERC1155Permit.sol";
import {IERC721Permit} from "../../contracts/interfaces/IERC721Permit.sol";
import {Coupon} from "../../contracts/libraries/Coupon.sol";
import {ERC20PermitParams, PermitSignature} from "../../contracts/libraries/PermitParams.sol";

library ERC20Utils {
    function amount(IERC20 token, uint256 ethers) internal view returns (uint256) {
        return ethers * 10 ** (IERC20Metadata(address(token)).decimals());
    }
}

library Utils {
    function toArr(Coupon memory coupon) internal pure returns (Coupon[] memory arr) {
        arr = new Coupon[](1);
        arr[0] = coupon;
    }

    function toArr(address account) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = account;
    }

    function toArr(address account0, address account1) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = account0;
        arr[1] = account1;
    }

    function toArr(address account0, address account1, address account2) internal pure returns (address[] memory arr) {
        arr = new address[](3);
        arr[0] = account0;
        arr[1] = account1;
        arr[2] = account2;
    }

    function toArr(address[] memory arr) internal pure returns (address[][] memory nested) {
        nested = new address[][](1);
        nested[0] = arr;
    }

    function toArr(address[] memory arr0, address[] memory arr1) internal pure returns (address[][] memory nested) {
        nested = new address[][](2);
        nested[0] = arr0;
        nested[1] = arr1;
    }

    function toArr(address[] memory arr0, address[] memory arr1, address[] memory arr2)
        internal
        pure
        returns (address[][] memory nested)
    {
        nested = new address[][](3);
        nested[0] = arr0;
        nested[1] = arr1;
        nested[2] = arr2;
    }

    function toArr(uint256 n0) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = n0;
    }

    function toArr(uint256 n0, uint256 n1) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = n0;
        arr[1] = n1;
    }

    function toArr(uint256 n0, uint256 n1, uint256 n2) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = n0;
        arr[1] = n1;
        arr[2] = n2;
    }
}

library ForkUtils {
    function fork(Vm vm, uint256 blockNumber) public {
        uint256 newFork = vm.createFork(vm.envString("FORK_URL"));
        vm.selectFork(newFork);
        vm.rollFork(blockNumber);
    }
}

library PermitSignLibrary {
    bytes32 private constant _ERC20_PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function signPermit(Vm vm, uint256 privateKey, IERC20Permit token, address spender, uint256 amount)
        internal
        view
        returns (ERC20PermitParams memory)
    {
        address owner = vm.addr(privateKey);
        bytes32 structHash = keccak256(
            abi.encode(_ERC20_PERMIT_TYPEHASH, owner, spender, amount, token.nonces(owner), block.timestamp + 1)
        );
        bytes32 hash = MessageHashUtils.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return ERC20PermitParams(amount, PermitSignature(block.timestamp + 1, v, r, s));
    }

    function signPermit(Vm vm, uint256 privateKey, IERC721Permit token, address spender, uint256 tokenId)
        internal
        view
        returns (PermitSignature memory)
    {
        bytes32 structHash =
            keccak256(abi.encode(token.PERMIT_TYPEHASH(), spender, tokenId, token.nonces(tokenId), block.timestamp + 1));
        bytes32 hash = MessageHashUtils.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return PermitSignature(block.timestamp + 1, v, r, s);
    }

    function signPermit(Vm vm, uint256 privateKey, IERC1155Permit token, address spender, bool approved)
        internal
        view
        returns (PermitSignature memory)
    {
        address owner = vm.addr(privateKey);
        bytes32 structHash = keccak256(
            abi.encode(token.PERMIT_TYPEHASH(), owner, spender, approved, token.nonces(owner), block.timestamp + 1)
        );
        bytes32 hash = MessageHashUtils.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return PermitSignature(block.timestamp + 1, v, r, s);
    }
}

library VmLogUtilsLibrary {
    function findLogsByEvent(Vm.Log[] memory logs, bytes32 eventSelector) internal pure returns (Vm.Log[] memory) {
        Vm.Log[] memory result = new Vm.Log[](logs.length);
        uint256 index = 0;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == eventSelector) {
                result[index] = logs[i];
                index++;
            }
        }
        assembly {
            mstore(result, index)
        }
        return result;
    }
}
