// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Constants} from "../Constants.sol";
import {ForkUtils, ERC20Utils, Utils, PermitSignLibrary} from "../Utils.sol";
import {IAssetPool} from "../../../contracts/interfaces/IAssetPool.sol";
import {ICouponOracle} from "../../../contracts/interfaces/ICouponOracle.sol";
import {IAaveTokenSubstitute} from "../../../contracts/interfaces/IAaveTokenSubstitute.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {ILoanPositionManager} from "../../../contracts/interfaces/ILoanPositionManager.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {CouponKey, CouponKeyLibrary} from "../../../contracts/libraries/CouponKey.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {LoanPosition} from "../../../contracts/libraries/LoanPosition.sol";
import {Wrapped1155MetadataBuilder} from "../../../contracts/libraries/Wrapped1155MetadataBuilder.sol";
import {ERC20PermitParams, PermitSignature} from "../../../contracts/libraries/PermitParams.sol";
import {IWrapped1155Factory} from "../../../contracts/external/wrapped1155/IWrapped1155Factory.sol";
import {CloberMarketFactory} from "../../../contracts/external/clober/CloberMarketFactory.sol";
import {CloberMarketSwapCallbackReceiver} from "../../../contracts/external/clober/CloberMarketSwapCallbackReceiver.sol";
import {CloberOrderBook} from "../../../contracts/external/clober/CloberOrderBook.sol";
import {RepayAdapter} from "../../../contracts/RepayAdapter.sol";
import {BorrowController} from "../../../contracts/BorrowController.sol";
import {IRepayAdapter} from "../../../contracts/interfaces/IRepayAdapter.sol";
import {AaveTokenSubstitute} from "../../../contracts/AaveTokenSubstitute.sol";

contract RepayAdapterIntegrationTest is Test, CloberMarketSwapCallbackReceiver, ERC1155Holder {
    using Strings for *;
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for CouponKey;
    using EpochLibrary for Epoch;
    using PermitSignLibrary for Vm;

    address public constant MARKET_MAKER = address(999123);

    IAssetPool public assetPool;
    RepayAdapter public repayAdapter;
    BorrowController public borrowController;
    ILoanPositionManager public loanPositionManager;
    IWrapped1155Factory public wrapped1155Factory;
    ICouponManager public couponManager;
    ICouponOracle public oracle;
    CloberMarketFactory public cloberMarketFactory;
    IERC20 public usdc;
    IERC20 public weth;
    address public wausdc;
    address public waweth;
    address public user;
    ERC20PermitParams public emptyPermitParams;

    CouponKey[] public couponKeys;
    address[] public wrappedCoupons;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        user = vm.addr(1);

        usdc = IERC20(Constants.USDC);
        weth = IERC20(Constants.WETH);
        vm.startPrank(Constants.USDC_WHALE);
        usdc.transfer(user, usdc.amount(1_000_000));
        usdc.transfer(address(this), usdc.amount(1_000_000));
        vm.stopPrank();
        vm.deal(user, 1_000_000 ether);

        bool success;
        vm.startPrank(user);
        (success,) = payable(address(weth)).call{value: 500_000 ether}("");
        require(success, "transfer failed");
        vm.stopPrank();

        vm.deal(address(this), 1_000_000 ether);
        (success,) = payable(address(weth)).call{value: 500_000 ether}("");
        require(success, "transfer failed");

        wrapped1155Factory = IWrapped1155Factory(Constants.WRAPPED1155_FACTORY);
        cloberMarketFactory = CloberMarketFactory(Constants.CLOBER_FACTORY);
        wausdc = Constants.COUPON_USDC_SUBSTITUTE;
        waweth = Constants.COUPON_WETH_SUBSTITUTE;
        oracle = ICouponOracle(Constants.COUPON_COUPON_MANAGER);
        assetPool = IAssetPool(Constants.COUPON_ASSET_POOL);
        couponManager = ICouponManager(Constants.COUPON_COUPON_MANAGER);
        loanPositionManager = ILoanPositionManager(Constants.COUPON_LOAN_POSITION_MANAGER);

        usdc.approve(wausdc, usdc.amount(3_000));
        IAaveTokenSubstitute(wausdc).mint(usdc.amount(3_000), address(this));
        IERC20(Constants.WETH).approve(waweth, 3_000 ether);
        IAaveTokenSubstitute(waweth).mint(3_000 ether, address(this));

        borrowController = new BorrowController(
            Constants.WRAPPED1155_FACTORY,
            Constants.CLOBER_FACTORY,
            address(couponManager),
            Constants.WETH,
            address(loanPositionManager)
        );
        repayAdapter = new RepayAdapter(
            Constants.WRAPPED1155_FACTORY,
            Constants.CLOBER_FACTORY,
            address(couponManager),
            Constants.WETH,
            address(loanPositionManager),
            Constants.ODOS_V2_SWAP_ROUTER
        );

        IERC20(wausdc).transfer(address(assetPool), usdc.amount(1_000));
        IERC20(waweth).transfer(address(assetPool), 1_000 ether);

        // create wrapped1155
        for (uint8 i = 0; i < 5; i++) {
            couponKeys.push(CouponKey({asset: wausdc, epoch: EpochLibrary.current().add(i)}));
        }
        for (uint8 i = 0; i < 5; i++) {
            couponKeys.push(CouponKey({asset: waweth, epoch: EpochLibrary.current().add(i)}));
        }
        for (uint256 i = 0; i < 10; i++) {
            address wrappedToken = wrapped1155Factory.requireWrapped1155(
                address(couponManager),
                couponKeys[i].toId(),
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );
            wrappedCoupons.push(wrappedToken);
            address market = cloberMarketFactory.createVolatileMarket(
                address(Constants.TREASURY),
                couponKeys[i].asset,
                wrappedToken,
                i < 5 ? 1 : 1e9,
                0,
                400,
                1e10,
                1001 * 1e15
            );
            repayAdapter.setCouponMarket(couponKeys[i], market);
            borrowController.setCouponMarket(couponKeys[i], market);
        }
        _marketMake();

        vm.prank(Constants.USDC_WHALE);
        usdc.transfer(user, usdc.amount(10_000));
        vm.deal(address(user), 100 ether);
    }

    function _marketMake() internal {
        for (uint256 i = 0; i < wrappedCoupons.length; ++i) {
            CouponKey memory key = couponKeys[i];
            CloberOrderBook market = CloberOrderBook(repayAdapter.getCouponMarket(key));
            (uint16 bidIndex,) = market.priceToIndex(1e18 / 100 * 2, false); // 2%
            (uint16 askIndex,) = market.priceToIndex(1e18 / 100 * 4, false); // 4%
            CloberOrderBook(market).limitOrder(
                MARKET_MAKER, bidIndex, market.quoteToRaw(IERC20(key.asset).amount(1), false), 0, 3, ""
            );
            uint256 amount = IERC20(wrappedCoupons[i]).amount(100000000);
            Coupon[] memory coupons = Utils.toArr(Coupon(key, amount));
            vm.prank(Constants.COUPON_LOAN_POSITION_MANAGER);
            couponManager.mintBatch(address(this), coupons, "");
            couponManager.safeBatchTransferFrom(
                address(this),
                address(wrapped1155Factory),
                coupons,
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );
            CloberOrderBook(market).limitOrder(MARKET_MAKER, askIndex, 0, amount, 2, "");
        }
    }

    function cloberMarketSwapCallback(address inputToken, address, uint256 inputAmount, uint256, bytes calldata)
        external
        payable
    {
        if (inputAmount > 0) {
            IERC20(inputToken).transfer(msg.sender, inputAmount);
        }
    }

    function _initialBorrow(
        address borrower,
        address collateralToken,
        address borrowToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint16 loanEpochs
    ) internal returns (uint256 positionId) {
        positionId = loanPositionManager.nextId();
        ERC20PermitParams memory permitParams = vm.signPermit(
            1,
            IERC20Permit(AaveTokenSubstitute(payable(collateralToken)).underlyingToken()),
            address(borrowController),
            collateralAmount
        );
        vm.prank(borrower);
        borrowController.borrow(
            collateralToken,
            borrowToken,
            collateralAmount,
            borrowAmount,
            type(uint256).max,
            EpochLibrary.current().add(loanEpochs - 1),
            permitParams
        );
    }

    // Convert an hexadecimal character to their value
    function fromHexChar(uint8 c) public pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("f")) {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("F")) {
            return 10 + c - uint8(bytes1("A"));
        }
        revert("fail");
    }

    // Convert an hexadecimal string to raw bytes
    function fromHex(string memory s) public pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0); // length must be even
        bytes memory r = new bytes(ss.length/2);
        for (uint256 i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(fromHexChar(uint8(ss[2 * i])) * 16 + fromHexChar(uint8(ss[2 * i + 1])));
        }
        return r;
    }

    function remove0x(string calldata s) external pure returns (string memory) {
        return s[2:];
    }

    function testRepayWithCollateral() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(500);
        uint256 maxDebtAmount = 0.75 ether;
        bytes memory data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000803608bda99eed8c0028f5c00017F137D1D8d20BA54004Ba358E9C229DA26FA3Fa900000001",
                this.remove0x(Strings.toHexString(address(repayAdapter))),
                "000000010501020601a0a52cd80b010001020000270100030200020b0001040500ff000000fae2ae0a9f87fd35b5b0e24b47bac796a7eefea1af88d065e77c8cc2239327c5edb3a432268e5831d87899d10eaa10f3ade05038a38251f758e5c0ebc6f780497a95e246eb9449f5e4770916dcd6396a912ce59144191c1204e64559fe8253a0e49e654800000000000000000000000000000000000000000000000000000000"
            )
        );

        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(repayAdapter), positionId);

        vm.prank(user);
        repayAdapter.repayWithCollateral(positionId, collateralAmount, 1 ether - maxDebtAmount, data, permit721Params);

        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertLe(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount - collateralAmount,
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertLe(afterLoanPosition.debtAmount, maxDebtAmount, "POSITION_DEBT_AMOUNT");
        assertGe(afterLoanPosition.debtAmount, 0.7 ether, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testRepayWithLeftCollateral() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(5000);
        uint256 maxDebtAmount = 0.75 ether;
        bytes memory data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000803608bda99eed8c0028f5c00017F137D1D8d20BA54004Ba358E9C229DA26FA3Fa900000001",
                this.remove0x(Strings.toHexString(address(repayAdapter))),
                "000000010501020601a0a52cd80b010001020000270100030200020b0001040500ff000000fae2ae0a9f87fd35b5b0e24b47bac796a7eefea1af88d065e77c8cc2239327c5edb3a432268e5831d87899d10eaa10f3ade05038a38251f758e5c0ebc6f780497a95e246eb9449f5e4770916dcd6396a912ce59144191c1204e64559fe8253a0e49e654800000000000000000000000000000000000000000000000000000000"
            )
        );

        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(repayAdapter), positionId);

        vm.prank(user);
        repayAdapter.repayWithCollateral(positionId, collateralAmount, 1 ether - maxDebtAmount, data, permit721Params);

        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertLe(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount - usdc.amount(500),
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertLe(afterLoanPosition.debtAmount, maxDebtAmount, "POSITION_DEBT_AMOUNT");
        assertGe(afterLoanPosition.debtAmount, 0.7 ether, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testRepayAllWithCollateral() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 0.2 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(500);
        uint256 maxDebtAmount = 0;
        bytes memory data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000803608bda99eed8c0028f5c00017F137D1D8d20BA54004Ba358E9C229DA26FA3Fa900000001",
                this.remove0x(Strings.toHexString(address(repayAdapter))),
                "000000010501020601a0a52cd80b010001020000270100030200020b0001040500ff000000fae2ae0a9f87fd35b5b0e24b47bac796a7eefea1af88d065e77c8cc2239327c5edb3a432268e5831d87899d10eaa10f3ade05038a38251f758e5c0ebc6f780497a95e246eb9449f5e4770916dcd6396a912ce59144191c1204e64559fe8253a0e49e654800000000000000000000000000000000000000000000000000000000"
            )
        );

        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(repayAdapter), positionId);

        vm.prank(user);
        repayAdapter.repayWithCollateral(positionId, collateralAmount, 0.2 ether - maxDebtAmount, data, permit721Params);

        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(Epoch.wrap(645), afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount - usdc.amount(500),
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertLe(afterLoanPosition.debtAmount, maxDebtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    //    function testRepayWhenSmallDebt() public {
    //        uint256 positionId = _initialBorrow(user, waweth, wausdc, 1 ether, usdc.amount(100), 2);
    //
    //        address[] memory assets = new address[](2);
    //        assets[0] = address(0xFEfC6BAF87cF3684058D62Da40Ff3A795946Ab06);
    //        assets[1] = address(0);
    //
    //        uint256[] memory prices = new uint256[](2);
    //        prices[0] = 100000000;
    //        prices[1] = 1000000000000;
    //
    //        vm.mockCall(address(oracle), abi.encodeWithSignature("getAssetsPrices(address[])", assets), abi.encode(prices));
    //        assertEq(oracle.getAssetsPrices(assets)[1], 1000000000000, "MANIPULATE_ORACLE");
    //
    //        bytes memory data = fromHex(
    //            string.concat(
    //                "83bd37f9000a000b041dcd65000803608bda99eed8c0028f5c00017F137D1D8d20BA54004Ba358E9C229DA26FA3Fa900000001",
    //                this.remove0x(Strings.toHexString(address(repayAdapter))),
    //                "000000010501020601a0a52cd80b010001020000270100030200020b0001040500ff000000fae2ae0a9f87fd35b5b0e24b47bac796a7eefea1af88d065e77c8cc2239327c5edb3a432268e5831d87899d10eaa10f3ade05038a38251f758e5c0ebc6f780497a95e246eb9449f5e4770916dcd6396a912ce59144191c1204e64559fe8253a0e49e654800000000000000000000000000000000000000000000000000000000"
    //            )
    //        );
    //
    //        PermitSignature memory permit721Params =
    //            vm.signPermit(1, loanPositionManager, address(repayAdapter), positionId);
    //
    //        vm.startPrank(user);
    //        usdc.approve(address(repayAdapter), 7000000);
    //        vm.expectRevert(abi.encodeWithSelector(ControllerSlippage.selector));
    //        repayAdapter.repayWithCollateral(positionId, 0.02 ether, 0, data, permit721Params);
    //        vm.stopPrank();
    //    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(Epoch.unwrap(e1), Epoch.unwrap(e2), err);
    }
}
