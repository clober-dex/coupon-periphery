// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Constants} from "../Constants.sol";
import {ForkUtils, ERC20Utils, Utils, PermitSignLibrary} from "../Utils.sol";
import {IAssetPool} from "../../../contracts/interfaces/IAssetPool.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {IControllerV2} from "../../../contracts/interfaces/IControllerV2.sol";
import {IAaveTokenSubstitute} from "../../../contracts/interfaces/IAaveTokenSubstitute.sol";
import {IERC721Permit} from "../../../contracts/interfaces/IERC721Permit.sol";
import {IBondPositionManager} from "../../../contracts/interfaces/IBondPositionManager.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {CouponKey, CouponKeyLibrary} from "../../../contracts/libraries/CouponKey.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {BondPosition} from "../../../contracts/libraries/BondPosition.sol";
import {Wrapped1155MetadataBuilder} from "../../../contracts/libraries/Wrapped1155MetadataBuilder.sol";
import {ERC20PermitParams, PermitSignature} from "../../../contracts/libraries/PermitParams.sol";
import {IWrapped1155Factory} from "../../../contracts/external/wrapped1155/IWrapped1155Factory.sol";
import {IController} from "../../../contracts/external/clober-v2/IController.sol";
import {IBookManager} from "../../../contracts/external/clober-v2/IBookManager.sol";
import {IHooks} from "../../../contracts/external/clober-v2/IHooks.sol";
import {Currency, CurrencyLibrary} from "../../../contracts/external/clober-v2/IBookManager.sol";
import {FeePolicy, FeePolicyLibrary} from "../../../contracts/external/clober-v2/FeePolicy.sol";
import {DepositControllerV2} from "../../../contracts/DepositControllerV2.sol";
import {AaveTokenSubstitute} from "../../../contracts/AaveTokenSubstitute.sol";
import {MockBookManager} from "../mocks/MockBookManager.sol";
import {MockController} from "../mocks/MockController.sol";

contract DepositControllerV2IntegrationTest is Test, ERC1155Holder {
    using FeePolicyLibrary for FeePolicy;
    using Strings for *;
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for CouponKey;
    using EpochLibrary for Epoch;
    using PermitSignLibrary for Vm;

    address public constant MARKET_MAKER = address(999123);

    IAssetPool public assetPool;
    DepositControllerV2 public depositController;
    IBondPositionManager public bondPositionManager;
    IWrapped1155Factory public wrapped1155Factory;
    ICouponManager public couponManager;
    IController public cloberController;
    IBookManager public bookManager;
    IERC20 public usdc;
    address public wausdc;
    address public waweth;
    address public user;
    ERC20PermitParams public emptyERC20PermitParams;
    PermitSignature public emptyERC721PermitParams;

    CouponKey[] public couponKeys;
    address[] public wrappedCoupons;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        user = vm.addr(1);

        usdc = IERC20(Constants.USDC);
        vm.startPrank(Constants.USDC_WHALE);
        usdc.transfer(user, usdc.amount(1_000_000));
        usdc.transfer(address(this), usdc.amount(1_000_000));
        vm.stopPrank();
        vm.deal(user, 1_000_000 ether);
        vm.deal(address(this), 1_000_000 ether);
        (bool success,) = payable(Constants.WETH).call{value: 500_000 ether}("");
        require(success, "transfer failed");

        wrapped1155Factory = IWrapped1155Factory(Constants.WRAPPED1155_FACTORY);
        wausdc = Constants.COUPON_USDC_SUBSTITUTE;
        waweth = Constants.COUPON_WETH_SUBSTITUTE;
        assetPool = IAssetPool(Constants.COUPON_ASSET_POOL);
        couponManager = ICouponManager(Constants.COUPON_COUPON_MANAGER);
        bondPositionManager = IBondPositionManager(Constants.COUPON_BOND_POSITION_MANAGER);

        usdc.approve(wausdc, usdc.amount(3_000));
        IAaveTokenSubstitute(wausdc).mint(usdc.amount(3_000), address(this));
        IERC20(Constants.WETH).approve(waweth, 3_000 ether);
        IAaveTokenSubstitute(waweth).mint(3_000 ether, address(this));

        // create wrapped1155
        couponKeys.push(CouponKey({asset: wausdc, epoch: EpochLibrary.current()}));
        couponKeys.push(CouponKey({asset: waweth, epoch: EpochLibrary.current()}));
        couponKeys.push(CouponKey({asset: wausdc, epoch: EpochLibrary.current().add(1)}));
        couponKeys.push(CouponKey({asset: waweth, epoch: EpochLibrary.current().add(1)}));

        for (uint256 i = 0; i < 4; i++) {
            address wrappedToken = wrapped1155Factory.requireWrapped1155(
                address(couponManager),
                couponKeys[i].toId(),
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );
            wrappedCoupons.push(wrappedToken);
        }

        bookManager = IBookManager(address(new MockBookManager()));
        cloberController = IController(address(new MockController(wrappedCoupons)));
        depositController = new DepositControllerV2(
            Constants.WRAPPED1155_FACTORY,
            address(cloberController),
            address(bookManager),
            address(couponManager),
            Constants.WETH,
            address(bondPositionManager)
        );

        IERC20(wausdc).transfer(address(cloberController), IERC20(wausdc).amount(500));
        IERC20(waweth).transfer(address(cloberController), IERC20(waweth).amount(500));

        for (uint256 i = 0; i < 4; i++) {
            CouponKey memory key = couponKeys[i];
            uint256 amount = IERC20(wrappedCoupons[i]).amount(100);
            Coupon[] memory coupons = Utils.toArr(Coupon(key, amount));
            vm.prank(Constants.COUPON_LOAN_POSITION_MANAGER);
            couponManager.mintBatch(address(this), coupons, "");
            couponManager.safeBatchTransferFrom(
                address(this),
                address(wrapped1155Factory),
                coupons,
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );
            IERC20(wrappedCoupons[i]).transfer(
                address(cloberController), IERC20(wrappedCoupons[i]).balanceOf(address(this))
            );

            IHooks hooks;
            IBookManager.BookKey memory sellBookKey = IBookManager.BookKey({
                base: Currency.wrap(wrappedCoupons[i]),
                unit: 10 ** 6,
                quote: Currency.wrap(i % 2 == 0 ? wausdc : waweth),
                makerPolicy: FeePolicyLibrary.encode(true, -100),
                hooks: hooks,
                takerPolicy: FeePolicyLibrary.encode(true, -100)
            });
            IBookManager.BookKey memory buyBookKey = IBookManager.BookKey({
                base: Currency.wrap(i % 2 == 0 ? wausdc : waweth),
                unit: 10 ** 6,
                quote: Currency.wrap(wrappedCoupons[i]),
                makerPolicy: FeePolicyLibrary.encode(true, -100),
                hooks: hooks,
                takerPolicy: FeePolicyLibrary.encode(true, -100)
            });

            depositController.setCouponBookKey(couponKeys[i], sellBookKey, buyBookKey);
        }
    }

    function _checkWrappedTokenAlmost0Balance(address who) internal {
        for (uint256 i = 0; i < wrappedCoupons.length; ++i) {
            assertLt(
                IERC20(wrappedCoupons[i]).balanceOf(who),
                i < 4 ? 100 : 1e14,
                string.concat(who.toHexString(), " WRAPPED_TOKEN_", i.toString())
            );
        }
    }

    function testDeposit() public {
        vm.startPrank(user);
        uint256 amount = usdc.amount(10);

        uint256 beforeBalance = usdc.balanceOf(user);

        uint256 tokenId = bondPositionManager.nextId();
        depositController.deposit(
            wausdc,
            amount,
            EpochLibrary.current(),
            0,
            vm.signPermit(1, IERC20Permit(Constants.USDC), address(depositController), amount - 100)
        );

        BondPosition memory position = bondPositionManager.getPosition(tokenId);

        assertEq(bondPositionManager.ownerOf(tokenId), user, "POSITION_OWNER");
        assertGt(usdc.balanceOf(user), beforeBalance - amount, "USDC_BALANCE");
        console.log("diff", usdc.balanceOf(user) - (beforeBalance - amount));
        assertEq(position.asset, wausdc, "POSITION_ASSET");
        assertEq(position.amount, amount, "POSITION_AMOUNT");
        assertEq(position.expiredWith, EpochLibrary.current(), "POSITION_EXPIRED_WITH");
        assertEq(position.nonce, 0, "POSITION_NONCE");
        _checkWrappedTokenAlmost0Balance(address(depositController));

        vm.stopPrank();
    }

    function testDepositOverSlippage() public {
        uint256 amount = usdc.amount(10);

        ERC20PermitParams memory permitParams =
            vm.signPermit(1, IERC20Permit(Constants.USDC), address(depositController), amount);
        vm.expectRevert(abi.encodeWithSelector(IControllerV2.ControllerSlippage.selector));
        vm.prank(user);
        depositController.deposit(wausdc, amount, EpochLibrary.current(), int256(amount * 4 / 100), permitParams);
    }

    function testDepositNative() public {
        vm.startPrank(user);
        uint256 amount = 10 ether;

        uint256 beforeBalance = user.balance;

        uint256 tokenId = bondPositionManager.nextId();
        depositController.deposit{value: amount}(waweth, amount, EpochLibrary.current(), 0, emptyERC20PermitParams);

        BondPosition memory position = bondPositionManager.getPosition(tokenId);

        assertEq(bondPositionManager.ownerOf(tokenId), user, "POSITION_OWNER");
        assertGt(user.balance, beforeBalance - amount, "NATIVE_BALANCE");
        console.log("diff", user.balance - (beforeBalance - amount));
        assertEq(position.asset, waweth, "POSITION_ASSET");
        assertEq(position.amount, amount, "POSITION_AMOUNT");
        assertEq(position.expiredWith, EpochLibrary.current(), "POSITION_EXPIRED_WITH");
        assertEq(position.nonce, 0, "POSITION_NONCE");
        _checkWrappedTokenAlmost0Balance(address(depositController));

        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(user);
        uint256 amount = usdc.amount(10);
        uint256 tokenId = bondPositionManager.nextId();
        depositController.deposit(
            wausdc,
            amount,
            EpochLibrary.current(),
            0,
            vm.signPermit(1, IERC20Permit(Constants.USDC), address(depositController), amount)
        );

        BondPosition memory beforePosition = bondPositionManager.getPosition(tokenId);
        uint256 beforeBalance = usdc.balanceOf(user);

        console.log("---------");
        depositController.adjust(
            tokenId,
            amount / 2,
            beforePosition.expiredWith,
            type(int256).max,
            emptyERC20PermitParams,
            vm.signPermit(1, bondPositionManager, address(depositController), tokenId)
        );

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(bondPositionManager.ownerOf(tokenId), user, "POSITION_OWNER_0");
        assertLt(usdc.balanceOf(user), beforeBalance + amount / 2, "USDC_BALANCE_0");
        console.log("diff", beforeBalance + amount / 2 - usdc.balanceOf(user));
        assertEq(afterPosition.asset, wausdc, "POSITION_ASSET_0");
        assertEq(afterPosition.amount, beforePosition.amount - amount / 2, "POSITION_AMOUNT_0");
        assertEq(afterPosition.expiredWith, beforePosition.expiredWith, "POSITION_EXPIRED_WITH_0");
        assertEq(afterPosition.nonce, beforePosition.nonce + 1, "POSITION_NONCE_0");

        beforeBalance = usdc.balanceOf(user);
        beforePosition = afterPosition;

        depositController.adjust(
            tokenId, 0, beforePosition.expiredWith, type(int256).max, emptyERC20PermitParams, emptyERC721PermitParams
        );

        afterPosition = bondPositionManager.getPosition(tokenId);

        vm.expectRevert("ERC721: invalid token ID");
        bondPositionManager.ownerOf(tokenId);
        assertLt(usdc.balanceOf(user), beforeBalance + beforePosition.amount, "USDC_BALANCE_1");
        console.log("diff", beforeBalance + beforePosition.amount - usdc.balanceOf(user));
        assertEq(afterPosition.asset, wausdc, "POSITION_ASSET_1");
        assertEq(afterPosition.amount, 0, "POSITION_AMOUNT_1");
        assertEq(afterPosition.expiredWith, EpochLibrary.lastExpiredEpoch(), "POSITION_EXPIRED_WITH_1");
        assertEq(afterPosition.nonce, beforePosition.nonce, "POSITION_NONCE_1");
        _checkWrappedTokenAlmost0Balance(address(depositController));

        vm.stopPrank();
    }

    function testWithdrawMaxMinusOne() public {
        vm.startPrank(user);
        uint256 amount = usdc.amount(10);
        uint256 tokenId = bondPositionManager.nextId();
        depositController.deposit(
            wausdc,
            amount,
            EpochLibrary.current(),
            0,
            vm.signPermit(1, IERC20Permit(Constants.USDC), address(depositController), amount)
        );

        BondPosition memory beforePosition = bondPositionManager.getPosition(tokenId);
        uint256 beforeBalance = usdc.balanceOf(user);

        depositController.adjust(
            tokenId,
            1,
            beforePosition.expiredWith,
            type(int256).max,
            emptyERC20PermitParams,
            vm.signPermit(1, bondPositionManager, address(depositController), tokenId)
        );

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(bondPositionManager.ownerOf(tokenId), user, "POSITION_OWNER_0");
        assertLt(usdc.balanceOf(user), beforeBalance + amount, "USDC_BALANCE_0");
        assertEq(afterPosition.asset, wausdc, "POSITION_ASSET_0");
        assertEq(afterPosition.amount, 1, "POSITION_AMOUNT_0");
        assertEq(afterPosition.expiredWith, beforePosition.expiredWith, "POSITION_EXPIRED_WITH_0");
        assertEq(afterPosition.nonce, beforePosition.nonce + 1, "POSITION_NONCE_0");

        vm.stopPrank();
    }

    function testWithdrawNative() public {
        vm.startPrank(user);
        uint256 amount = 10 ether;
        uint256 tokenId = bondPositionManager.nextId();
        depositController.deposit{value: amount}(
            waweth, amount, EpochLibrary.current().add(1), 0, emptyERC20PermitParams
        );

        BondPosition memory beforePosition = bondPositionManager.getPosition(tokenId);
        uint256 beforeBalance = user.balance;

        depositController.adjust(
            tokenId,
            amount / 2,
            beforePosition.expiredWith,
            type(int256).max,
            emptyERC20PermitParams,
            vm.signPermit(1, bondPositionManager, address(depositController), tokenId)
        );

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(bondPositionManager.ownerOf(tokenId), user, "POSITION_OWNER");
        assertLt(user.balance, beforeBalance + amount / 2, "NATIVE_BALANCE");
        console.log("diff", beforeBalance + amount / 2 - user.balance);
        assertEq(afterPosition.asset, waweth, "POSITION_ASSET");
        assertEq(afterPosition.amount, beforePosition.amount - amount / 2, "POSITION_AMOUNT");
        assertEq(afterPosition.expiredWith, beforePosition.expiredWith, "POSITION_EXPIRED_WITH");
        assertEq(afterPosition.nonce, beforePosition.nonce + 1, "POSITION_NONCE");

        beforeBalance = user.balance;
        beforePosition = afterPosition;

        depositController.adjust(
            tokenId, 0, beforePosition.expiredWith, type(int256).max, emptyERC20PermitParams, emptyERC721PermitParams
        );

        afterPosition = bondPositionManager.getPosition(tokenId);

        vm.expectRevert("ERC721: invalid token ID");
        bondPositionManager.ownerOf(tokenId);
        assertLt(user.balance, beforeBalance + beforePosition.amount, "NATIVE_BALANCE_1");
        console.log("diff", beforeBalance + beforePosition.amount - user.balance);
        assertEq(afterPosition.asset, waweth, "POSITION_ASSET_1");
        assertEq(afterPosition.amount, 0, "POSITION_AMOUNT_1");
        assertEq(afterPosition.expiredWith, EpochLibrary.lastExpiredEpoch(), "POSITION_EXPIRED_WITH_1");
        assertEq(afterPosition.nonce, beforePosition.nonce, "POSITION_NONCE_1");
        _checkWrappedTokenAlmost0Balance(address(depositController));

        vm.stopPrank();
    }

    function testCollect() public {
        vm.startPrank(user);
        uint256 amount = usdc.amount(10);
        uint256 tokenId = bondPositionManager.nextId();
        depositController.deposit(
            wausdc,
            amount,
            EpochLibrary.current(),
            0,
            vm.signPermit(1, IERC20Permit(Constants.USDC), address(depositController), amount)
        );
        vm.warp(EpochLibrary.current().add(1).startTime());

        BondPosition memory beforePosition = bondPositionManager.getPosition(tokenId);
        uint256 beforeBalance = usdc.balanceOf(user);

        depositController.adjust(
            tokenId,
            0,
            beforePosition.expiredWith,
            0,
            emptyERC20PermitParams,
            vm.signPermit(1, bondPositionManager, address(depositController), tokenId)
        );

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        vm.expectRevert("ERC721: invalid token ID");
        bondPositionManager.ownerOf(tokenId);
        assertEq(usdc.balanceOf(user), beforeBalance + beforePosition.amount, "USDC_BALANCE");
        assertEq(afterPosition.asset, wausdc, "POSITION_ASSET");
        assertEq(afterPosition.amount, 0, "POSITION_AMOUNT");
        assertEq(afterPosition.expiredWith, EpochLibrary.lastExpiredEpoch(), "POSITION_EXPIRED_WITH");
        assertEq(afterPosition.nonce, beforePosition.nonce + 1, "POSITION_NONCE");

        vm.stopPrank();
    }

    function testCollectNative() public {
        vm.startPrank(user);
        uint256 amount = 10 ether;
        uint256 tokenId = bondPositionManager.nextId();
        depositController.deposit{value: amount}(waweth, amount, EpochLibrary.current(), 0, emptyERC20PermitParams);
        vm.warp(EpochLibrary.current().add(1).startTime());

        BondPosition memory beforePosition = bondPositionManager.getPosition(tokenId);
        uint256 beforeBalance = user.balance;

        depositController.adjust(
            tokenId,
            0,
            beforePosition.expiredWith,
            0,
            emptyERC20PermitParams,
            vm.signPermit(1, bondPositionManager, address(depositController), tokenId)
        );

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        vm.expectRevert("ERC721: invalid token ID");
        bondPositionManager.ownerOf(tokenId);
        assertEq(user.balance, beforeBalance + beforePosition.amount, "NATIVE_BALANCE");
        assertEq(afterPosition.asset, waweth, "POSITION_ASSET");
        assertEq(afterPosition.amount, 0, "POSITION_AMOUNT");
        assertEq(afterPosition.expiredWith, EpochLibrary.lastExpiredEpoch(), "POSITION_EXPIRED_WITH");
        assertEq(afterPosition.nonce, beforePosition.nonce + 1, "POSITION_NONCE");

        vm.stopPrank();
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(Epoch.unwrap(e1), Epoch.unwrap(e2), err);
    }
}
