// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../contracts/external/clober-v2/BookId.sol";

contract MockBookManager {
    function getBookKey(BookId id) external view returns (BookKey memory) {
        FeePolicy memory feePolicy;
        IHooks hooks;
        return BookKey({
            base: Currency.NATIVE,
            unit: 10 ** 6,
            quote: Currency.NATIVE,
            makerPolicy: feePolicy,
            hooks: hooks,
            takerPolicy: feePolicy
        });
    }
}
