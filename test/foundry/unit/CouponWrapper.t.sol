// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {IWrapped1155Factory} from "../../../contracts/external/wrapped1155/IWrapped1155Factory.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {IERC1155Permit} from "../../../contracts/interfaces/IERC1155Permit.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {CouponKey} from "../../../contracts/libraries/CouponKey.sol";
import {Wrapped1155MetadataBuilder} from "../../../contracts/libraries/Wrapped1155MetadataBuilder.sol";
import {ERC20PermitParams} from "../../../contracts/libraries/PermitParams.sol";
import {CouponWrapper} from "../../../contracts/CouponWrapper.sol";
import {Constants} from "../Constants.sol";
import {ForkUtils, Utils, PermitSignLibrary} from "../Utils.sol";

contract CouponWrapperUnitTest is Test, ERC1155Holder {
    using Strings for uint256;
    using EpochLibrary for Epoch;
    using CouponLibrary for Coupon;
    using PermitSignLibrary for Vm;

    ICouponManager public couponManager;
    IWrapped1155Factory public wrapped1155Factory;
    CouponWrapper public couponWrapper;
    ERC20PermitParams public emptyPermitParams;

    address public user;
    Coupon[] public coupons;
    bytes[] public metadata;
    address[] public wrappedCoupons;
    Epoch public startEpoch;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);

        couponManager = ICouponManager(Constants.COUPON_COUPON_MANAGER);
        wrapped1155Factory = IWrapped1155Factory(Constants.WRAPPED1155_FACTORY);
        couponWrapper = new CouponWrapper(address(couponManager), Constants.WRAPPED1155_FACTORY);
        startEpoch = EpochLibrary.current();
        user = vm.addr(1);

        vm.prank(Constants.COUPON_BOND_POSITION_MANAGER);
        coupons.push(CouponLibrary.from(Constants.WETH, startEpoch, 1 ether));
        coupons.push(CouponLibrary.from(Constants.WETH, startEpoch.add(1), 2 ether));
        coupons.push(CouponLibrary.from(Constants.WETH, startEpoch.add(2), 3 ether));
        couponManager.mintBatch(user, coupons, "");

        for (uint256 i; i < coupons.length; ++i) {
            metadata.push(Wrapped1155MetadataBuilder.buildWrapped1155Metadata(coupons[i].key));
            wrappedCoupons.push(
                wrapped1155Factory.requireWrapped1155(address(couponManager), coupons[i].id(), metadata[i])
            );
        }
    }

    function testGetWrappedCoupon() public {
        for (uint256 i; i < coupons.length; ++i) {
            assertEq(couponWrapper.getWrappedCoupon(coupons[i].key), wrappedCoupons[i]);
        }
    }

    function testGetWrappedCoupons() public {
        CouponKey[] memory keys = new CouponKey[](coupons.length);
        for (uint256 i; i < coupons.length; ++i) {
            keys[i] = coupons[i].key;
        }
        assertEq(couponWrapper.getWrappedCoupons(keys), wrappedCoupons);
    }

    function testBuildMetadata() public {
        for (uint256 i; i < coupons.length; ++i) {
            assertEq(couponWrapper.buildMetadata(coupons[i].key), metadata[i]);
        }
    }

    function testBuildBatchMetadata() public {
        CouponKey[] memory keys = new CouponKey[](coupons.length);
        bytes memory batchMetadata;
        for (uint256 i; i < coupons.length; ++i) {
            keys[i] = coupons[i].key;
            batchMetadata = bytes.concat(batchMetadata, metadata[i]);
        }
        assertEq(couponWrapper.buildBatchMetadata(keys), batchMetadata);
    }

    function testWrap() public {
        vm.startPrank(user);
        couponManager.setApprovalForAll(address(couponWrapper), true);

        (uint256[] memory beforeCouponBalances, uint256[] memory beforeWrappedCouponBalances) = _getBalances(user);

        couponWrapper.wrap(coupons, user);

        (uint256[] memory afterCouponBalances, uint256[] memory afterWrappedCouponBalances) = _getBalances(user);

        for (uint256 i; i < coupons.length; ++i) {
            assertEq(
                afterCouponBalances[i],
                beforeCouponBalances[i] - coupons[i].amount,
                string.concat("COUPON_BALANCE_", i.toString())
            );
            assertEq(
                afterWrappedCouponBalances[i],
                beforeWrappedCouponBalances[i] + coupons[i].amount,
                string.concat("WRAPPED_COUPON_BALANCE_", i.toString())
            );
        }
        vm.stopPrank();
    }

    function testWrapWithPermit() public {
        vm.startPrank(user);
        couponManager.setApprovalForAll(address(couponWrapper), false);

        (uint256[] memory beforeCouponBalances, uint256[] memory beforeWrappedCouponBalances) = _getBalances(user);

        couponWrapper.wrapWithPermit(
            vm.signERC1155Permit(1, couponManager, address(couponWrapper), true), coupons, user
        );

        (uint256[] memory afterCouponBalances, uint256[] memory afterWrappedCouponBalances) = _getBalances(user);

        for (uint256 i; i < coupons.length; ++i) {
            assertEq(
                afterCouponBalances[i],
                beforeCouponBalances[i] - coupons[i].amount,
                string.concat("COUPON_BALANCE_", i.toString())
            );
            assertEq(
                afterWrappedCouponBalances[i],
                beforeWrappedCouponBalances[i] + coupons[i].amount,
                string.concat("WRAPPED_COUPON_BALANCE_", i.toString())
            );
        }
        vm.stopPrank();
    }

    function testUnwrap() public {
        vm.startPrank(user);
        couponManager.setApprovalForAll(address(couponWrapper), true);
        couponWrapper.wrap(coupons, user);

        for (uint256 i; i < wrappedCoupons.length; ++i) {
            IERC20(wrappedCoupons[i]).approve(address(couponWrapper), coupons[i].amount);
        }

        (uint256[] memory beforeCouponBalances, uint256[] memory beforeWrappedCouponBalances) = _getBalances(user);

        couponWrapper.unwrap(coupons, user);

        (uint256[] memory afterCouponBalances, uint256[] memory afterWrappedCouponBalances) = _getBalances(user);

        for (uint256 i; i < coupons.length; ++i) {
            assertEq(
                afterCouponBalances[i],
                beforeCouponBalances[i] + coupons[i].amount,
                string.concat("COUPON_BALANCE_", i.toString())
            );
            assertEq(
                afterWrappedCouponBalances[i],
                beforeWrappedCouponBalances[i] - coupons[i].amount,
                string.concat("WRAPPED_COUPON_BALANCE_", i.toString())
            );
        }

        vm.stopPrank();
    }

    function _getBalances(address owner)
        internal
        view
        returns (uint256[] memory couponBalances, uint256[] memory wrappedCouponBalances)
    {
        couponBalances = new uint256[](coupons.length);
        wrappedCouponBalances = new uint256[](coupons.length);
        for (uint256 i; i < coupons.length; ++i) {
            couponBalances[i] = couponManager.balanceOf(owner, coupons[i].id());
            wrappedCouponBalances[i] = IERC20(wrappedCoupons[i]).balanceOf(owner);
        }
    }
}
