// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {SimpleBondController} from "../../../contracts/SimpleBondController.sol";
import {CouponWrapper} from "../../../contracts/CouponWrapper.sol";
import {IBondPositionManager} from "../../../contracts/interfaces/IBondPositionManager.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {BondPosition} from "../../../contracts/libraries/BondPosition.sol";
import {CouponKeyLibrary, CouponKey} from "../../../contracts/libraries/CouponKey.sol";
import {CouponLibrary, Coupon} from "../../../contracts/libraries/Coupon.sol";
import {EpochLibrary, Epoch} from "../../../contracts/libraries/Epoch.sol";
import {ERC20PermitParams, PermitSignature} from "../../../contracts/libraries/PermitParams.sol";
import {IWETH9} from "../../../contracts/external/weth/IWETH9.sol";
import {Constants} from "../Constants.sol";
import {ForkUtils, PermitSignLibrary} from "../Utils.sol";

contract SimpleBondControllerIntegrationTest is Test, ERC1155Holder {
    using EpochLibrary for Epoch;
    using CouponLibrary for Coupon;
    using CouponKeyLibrary for CouponKey;
    using PermitSignLibrary for Vm;

    IBondPositionManager public bondPositionManager = IBondPositionManager(Constants.COUPON_BOND_POSITION_MANAGER);
    ICouponManager public couponManager = ICouponManager(Constants.COUPON_COUPON_MANAGER);
    CouponWrapper public couponWrapper;
    SimpleBondController public controller;
    IWETH9 public weth = IWETH9(Constants.WETH);
    address public wethSubstitute = Constants.COUPON_WETH_SUBSTITUTE;
    address public user;
    Epoch public currentEpoch;
    ERC20PermitParams public emptyERC20PermitParams;
    PermitSignature public emptyPermitSignature;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        user = vm.addr(1);
        couponWrapper = new CouponWrapper(Constants.COUPON_COUPON_MANAGER, Constants.WRAPPED1155_FACTORY);
        controller =
        new SimpleBondController(Constants.WETH, Constants.COUPON_BOND_POSITION_MANAGER, Constants.COUPON_COUPON_MANAGER, address(couponWrapper), address(this));

        vm.deal(user, 2000 ether);
        vm.prank(user);
        weth.deposit{value: 1000 ether}();

        currentEpoch = couponManager.currentEpoch();
    }

    function testMint() public {
        vm.startPrank(user);

        uint256 beforeWEthBalance = weth.balanceOf(user);
        uint256 positionId = controller.mint{value: 0.5 ether}(
            vm.signERC20Permit(1, IERC20Permit(address(weth)), address(controller), 0.5 ether),
            wethSubstitute,
            1 ether,
            currentEpoch.add(1)
        );

        BondPosition memory position = bondPositionManager.getPosition(positionId);
        assertEq(position.amount, 1 ether, "POSITION_AMOUNT");
        assertEq(position.expiredWith, currentEpoch.add(1), "POSITION_EXPIRED_AT");
        assertEq(beforeWEthBalance, 0.5 ether + weth.balanceOf(user), "USER_BALANCE");
        assertEq(bondPositionManager.ownerOf(positionId), user, "POSITION_OWNER");

        for (uint16 i; i < 5; ++i) {
            CouponKey memory key = CouponKey({asset: wethSubstitute, epoch: currentEpoch.add(i)});
            address wrappedCoupon = couponWrapper.getWrappedCoupon(key);
            if (i < 2) {
                assertEq(couponManager.balanceOf(user, key.toId()), 1 ether, "COUPON_BALANCE");
            } else {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_ZERO");
            }
            assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE");
        }

        vm.stopPrank();
    }

    function testMintAndWrapCoupons() public {
        vm.startPrank(user);

        uint256 beforeWEthBalance = weth.balanceOf(user);
        uint256 positionId = controller.mintAndWrapCoupons{value: 0.5 ether}(
            vm.signERC20Permit(1, IERC20Permit(address(weth)), address(controller), 0.5 ether),
            wethSubstitute,
            1 ether,
            currentEpoch.add(1)
        );

        BondPosition memory position = bondPositionManager.getPosition(positionId);
        assertEq(position.amount, 1 ether, "POSITION_AMOUNT");
        assertEq(position.expiredWith, currentEpoch.add(1), "POSITION_EXPIRED_AT");
        assertEq(beforeWEthBalance, 0.5 ether + weth.balanceOf(user), "USER_BALANCE");
        assertEq(bondPositionManager.ownerOf(positionId), user, "POSITION_OWNER");

        for (uint16 i; i < 5; ++i) {
            CouponKey memory key = CouponKey({asset: wethSubstitute, epoch: currentEpoch.add(i)});
            address wrappedCoupon = couponWrapper.getWrappedCoupon(key);
            if (i < 2) {
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 1 ether, "WRAPPED_COUPON_BALANCE");
            } else {
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE_ZERO");
            }
            assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE");
        }

        vm.stopPrank();
    }

    function _mint() internal returns (uint256) {
        return controller.mint{value: 0.5 ether}(
            vm.signERC20Permit(1, IERC20Permit(address(weth)), address(controller), 0.5 ether),
            wethSubstitute,
            1 ether,
            currentEpoch.add(1)
        );
    }

    function testAdjustIncreaseAmountAndEpoch() public {
        vm.startPrank(user);
        uint256 positionId = _mint();

        uint256 beforeWEthBalance = weth.balanceOf(user);
        controller.adjust{value: 0.5 ether}(
            vm.signERC20Permit(1, IERC20Permit(address(weth)), address(controller), 0.5 ether),
            vm.signERC721Permit(1, bondPositionManager, address(controller), positionId),
            emptyPermitSignature,
            positionId,
            2 ether,
            currentEpoch.add(2)
        );

        BondPosition memory position = bondPositionManager.getPosition(positionId);
        assertEq(position.amount, 2 ether, "POSITION_AMOUNT");
        assertEq(position.expiredWith, currentEpoch.add(2), "POSITION_EXPIRED_AT");
        assertEq(beforeWEthBalance, 0.5 ether + weth.balanceOf(user), "USER_BALANCE");

        for (uint16 i; i < 5; ++i) {
            CouponKey memory key = CouponKey({asset: wethSubstitute, epoch: currentEpoch.add(i)});
            address wrappedCoupon = couponWrapper.getWrappedCoupon(key);
            if (i < 3) {
                assertEq(couponManager.balanceOf(user, key.toId()), 2 ether, "COUPON_BALANCE");
            } else {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_ZERO");
            }
            assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE");
        }

        vm.stopPrank();
    }

    function testAdjustIncreaseAmountAndDecreaseEpoch() public {
        vm.startPrank(user);
        uint256 positionId = _mint();

        uint256 beforeWEthBalance = weth.balanceOf(user);
        controller.adjust{value: 0.5 ether}(
            vm.signERC20Permit(1, IERC20Permit(address(weth)), address(controller), 0.5 ether),
            vm.signERC721Permit(1, bondPositionManager, address(controller), positionId),
            vm.signERC1155Permit(1, couponManager, address(controller), true),
            positionId,
            2 ether,
            currentEpoch
        );

        BondPosition memory position = bondPositionManager.getPosition(positionId);
        assertEq(position.amount, 2 ether, "POSITION_AMOUNT");
        assertEq(position.expiredWith, currentEpoch, "POSITION_EXPIRED_AT");
        assertEq(beforeWEthBalance, 0.5 ether + weth.balanceOf(user), "USER_BALANCE");

        for (uint16 i; i < 5; ++i) {
            CouponKey memory key = CouponKey({asset: wethSubstitute, epoch: currentEpoch.add(i)});
            address wrappedCoupon = couponWrapper.getWrappedCoupon(key);
            if (i < 1) {
                assertEq(couponManager.balanceOf(user, key.toId()), 2 ether, "COUPON_BALANCE");
            } else {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_ZERO");
            }
            assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE");
        }

        vm.stopPrank();
    }

    function testAdjustDecreaseAmountAndIncreaseEpoch() public {
        vm.startPrank(user);
        uint256 positionId = _mint();

        uint256 beforeWEthBalance = weth.balanceOf(user);
        uint256 beforeEthBalance = user.balance;
        controller.adjust(
            emptyERC20PermitParams,
            vm.signERC721Permit(1, bondPositionManager, address(controller), positionId),
            vm.signERC1155Permit(1, couponManager, address(controller), true),
            positionId,
            0.5 ether,
            currentEpoch.add(2)
        );

        BondPosition memory position = bondPositionManager.getPosition(positionId);
        assertEq(position.amount, 0.5 ether, "POSITION_AMOUNT");
        assertEq(position.expiredWith, currentEpoch.add(2), "POSITION_EXPIRED_AT");
        assertEq(beforeEthBalance + 0.5 ether, user.balance, "USER_ETH_BALANCE");
        assertEq(beforeWEthBalance, weth.balanceOf(user), "USER_BALANCE");

        for (uint16 i; i < 5; ++i) {
            CouponKey memory key = CouponKey({asset: wethSubstitute, epoch: currentEpoch.add(i)});
            address wrappedCoupon = couponWrapper.getWrappedCoupon(key);
            if (i < 3) {
                assertEq(couponManager.balanceOf(user, key.toId()), 0.5 ether, "COUPON_BALANCE");
            } else {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_ZERO");
            }
            assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE");
        }

        vm.stopPrank();
    }

    function testAdjustDecreaseAmountAndEpoch() public {
        vm.startPrank(user);
        uint256 positionId = _mint();

        uint256 beforeWEthBalance = weth.balanceOf(user);
        uint256 beforeEthBalance = user.balance;
        controller.adjust(
            emptyERC20PermitParams,
            vm.signERC721Permit(1, bondPositionManager, address(controller), positionId),
            vm.signERC1155Permit(1, couponManager, address(controller), true),
            positionId,
            0.5 ether,
            currentEpoch
        );

        BondPosition memory position = bondPositionManager.getPosition(positionId);
        assertEq(position.amount, 0.5 ether, "POSITION_AMOUNT");
        assertEq(position.expiredWith, currentEpoch, "POSITION_EXPIRED_AT");
        assertEq(beforeEthBalance + 0.5 ether, user.balance, "USER_ETH_BALANCE");
        assertEq(beforeWEthBalance, weth.balanceOf(user), "USER_BALANCE");

        for (uint16 i; i < 5; ++i) {
            CouponKey memory key = CouponKey({asset: wethSubstitute, epoch: currentEpoch.add(i)});
            address wrappedCoupon = couponWrapper.getWrappedCoupon(key);
            if (i < 1) {
                assertEq(couponManager.balanceOf(user, key.toId()), 0.5 ether, "COUPON_BALANCE");
            } else {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_ZERO");
            }
            assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE");
        }

        vm.stopPrank();
    }

    function testAdjustAndWrapCouponsIncreaseAmountAndEpoch() public {
        vm.startPrank(user);
        uint256 positionId = _mint();

        uint256 beforeWEthBalance = weth.balanceOf(user);
        controller.adjustAndWrapCoupons{value: 0.5 ether}(
            vm.signERC20Permit(1, IERC20Permit(address(weth)), address(controller), 0.5 ether),
            vm.signERC721Permit(1, bondPositionManager, address(controller), positionId),
            emptyPermitSignature,
            positionId,
            2 ether,
            currentEpoch.add(2)
        );

        BondPosition memory position = bondPositionManager.getPosition(positionId);
        assertEq(position.amount, 2 ether, "POSITION_AMOUNT");
        assertEq(position.expiredWith, currentEpoch.add(2), "POSITION_EXPIRED_AT");
        assertEq(beforeWEthBalance, 0.5 ether + weth.balanceOf(user), "USER_BALANCE");

        for (uint16 i; i < 5; ++i) {
            CouponKey memory key = CouponKey({asset: wethSubstitute, epoch: currentEpoch.add(i)});
            address wrappedCoupon = couponWrapper.getWrappedCoupon(key);
            if (i < 2) {
                assertEq(couponManager.balanceOf(user, key.toId()), 1 ether, "COUPON_BALANCE_0");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 1 ether, "WRAPPED_COUPON_BALANCE_0");
            } else if (i < 3) {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_1");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 2 ether, "WRAPPED_COUPON_BALANCE_1");
            } else {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_2");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE_2");
            }
        }

        vm.stopPrank();
    }

    function testAdjustAndWrapCouponsIncreaseAmountAndDecreaseEpoch() public {
        vm.startPrank(user);
        uint256 positionId = _mint();

        uint256 beforeWEthBalance = weth.balanceOf(user);
        controller.adjustAndWrapCoupons{value: 0.5 ether}(
            vm.signERC20Permit(1, IERC20Permit(address(weth)), address(controller), 0.5 ether),
            vm.signERC721Permit(1, bondPositionManager, address(controller), positionId),
            vm.signERC1155Permit(1, couponManager, address(controller), true),
            positionId,
            2 ether,
            currentEpoch
        );

        BondPosition memory position = bondPositionManager.getPosition(positionId);
        assertEq(position.amount, 2 ether, "POSITION_AMOUNT");
        assertEq(position.expiredWith, currentEpoch, "POSITION_EXPIRED_AT");
        assertEq(beforeWEthBalance, 0.5 ether + weth.balanceOf(user), "USER_BALANCE");

        for (uint16 i; i < 5; ++i) {
            CouponKey memory key = CouponKey({asset: wethSubstitute, epoch: currentEpoch.add(i)});
            address wrappedCoupon = couponWrapper.getWrappedCoupon(key);
            if (i < 1) {
                assertEq(couponManager.balanceOf(user, key.toId()), 1 ether, "COUPON_BALANCE_0");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 1 ether, "WRAPPED_COUPON_BALANCE_0");
            } else if (i < 2) {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_1");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE_1");
            } else {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_2");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE_2");
            }
        }

        vm.stopPrank();
    }

    function testAdjustAndWrapCouponsDecreaseAmountAndIncreaseEpoch() public {
        vm.startPrank(user);
        uint256 positionId = _mint();

        uint256 beforeWEthBalance = weth.balanceOf(user);
        uint256 beforeEthBalance = user.balance;
        controller.adjustAndWrapCoupons(
            emptyERC20PermitParams,
            vm.signERC721Permit(1, bondPositionManager, address(controller), positionId),
            vm.signERC1155Permit(1, couponManager, address(controller), true),
            positionId,
            0.5 ether,
            currentEpoch.add(2)
        );

        BondPosition memory position = bondPositionManager.getPosition(positionId);
        assertEq(position.amount, 0.5 ether, "POSITION_AMOUNT");
        assertEq(position.expiredWith, currentEpoch.add(2), "POSITION_EXPIRED_AT");
        assertEq(beforeEthBalance + 0.5 ether, user.balance, "USER_ETH_BALANCE");
        assertEq(beforeWEthBalance, weth.balanceOf(user), "USER_BALANCE");

        for (uint16 i; i < 5; ++i) {
            CouponKey memory key = CouponKey({asset: wethSubstitute, epoch: currentEpoch.add(i)});
            address wrappedCoupon = couponWrapper.getWrappedCoupon(key);
            if (i < 2) {
                assertEq(couponManager.balanceOf(user, key.toId()), 0.5 ether, "COUPON_BALANCE_0");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE_0");
            } else if (i < 3) {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_1");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 0.5 ether, "WRAPPED_COUPON_BALANCE_1");
            } else {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_2");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE_2");
            }
        }

        vm.stopPrank();
    }

    function testAdjustAndWrapCouponsDecreaseAmountAndEpoch() public {
        vm.startPrank(user);
        uint256 positionId = _mint();

        uint256 beforeWEthBalance = weth.balanceOf(user);
        uint256 beforeEthBalance = user.balance;
        controller.adjustAndWrapCoupons(
            emptyERC20PermitParams,
            vm.signERC721Permit(1, bondPositionManager, address(controller), positionId),
            vm.signERC1155Permit(1, couponManager, address(controller), true),
            positionId,
            0.5 ether,
            currentEpoch
        );

        BondPosition memory position = bondPositionManager.getPosition(positionId);
        assertEq(position.amount, 0.5 ether, "POSITION_AMOUNT");
        assertEq(position.expiredWith, currentEpoch, "POSITION_EXPIRED_AT");
        assertEq(beforeEthBalance + 0.5 ether, user.balance, "USER_ETH_BALANCE");
        assertEq(beforeWEthBalance, weth.balanceOf(user), "USER_BALANCE");

        for (uint16 i; i < 5; ++i) {
            CouponKey memory key = CouponKey({asset: wethSubstitute, epoch: currentEpoch.add(i)});
            address wrappedCoupon = couponWrapper.getWrappedCoupon(key);
            if (i < 1) {
                assertEq(couponManager.balanceOf(user, key.toId()), 0.5 ether, "COUPON_BALANCE_0");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE_0");
            } else if (i < 2) {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_1");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE_1");
            } else {
                assertEq(couponManager.balanceOf(user, key.toId()), 0, "COUPON_BALANCE_2");
                assertEq(IERC20(wrappedCoupon).balanceOf(user), 0, "WRAPPED_COUPON_BALANCE_2");
            }
        }

        vm.stopPrank();
    }

    function testWithdrawLostToken() public {
        vm.prank(user);
        weth.transfer(address(controller), 1 ether);

        uint256 beforeOwnerWEthBalance = weth.balanceOf(address(this));
        uint256 beforeControllerWEthBalance = weth.balanceOf(address(controller));

        controller.withdrawLostToken(address(weth), address(this));

        assertEq(weth.balanceOf(address(this)), beforeOwnerWEthBalance + 1 ether, "OWNER_WETH_BALANCE");
        assertEq(weth.balanceOf(address(controller)), beforeControllerWEthBalance - 1 ether, "CONTROLLER_WETH_BALANCE");
    }

    function testWithdrawLostTokenAccess() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, (user)));
        vm.prank(user);
        controller.withdrawLostToken(address(weth), user);
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(Epoch.unwrap(e1), Epoch.unwrap(e2), err);
    }
}
