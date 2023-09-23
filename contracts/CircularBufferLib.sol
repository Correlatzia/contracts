// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// CircularBuffer Library
library CircularBufferLib {
    uint256 constant ONE_HUNDRED = 100; // max 99 safe values

    struct TokenPrices {
        uint128 a;
        uint128 b;
    }

    struct Buffer {
        TokenPrices[ONE_HUNDRED] prices;
        uint256 head;
        uint256 tail;
    }

    function push(Buffer storage buf, uint128 aValue, uint128 bValue) internal {
        buf.prices[buf.tail] = TokenPrices(aValue, bValue);
        buf.tail = (buf.tail + 1) % ONE_HUNDRED;

        if (buf.tail == buf.head) {
            buf.head = (buf.head + 1) % ONE_HUNDRED;
        }
    }

    function getOrderedBuffer(
        Buffer storage buf
    ) internal view returns (TokenPrices[] memory) {
        uint256 availableValues = buf.tail >= buf.head
            ? buf.tail - buf.head
            : 100 + buf.tail - buf.head;
        TokenPrices[] memory ordered = new TokenPrices[](availableValues);
        uint256 count = 0;

        for (uint256 i = buf.head; count < availableValues; i = (i + 1) % 100) {
            ordered[count] = buf.prices[i];
            count++;
        }

        return ordered;
    }

    function getLatestNValues(
        Buffer storage buf,
        uint256 n
    ) internal view returns (TokenPrices[] memory) {
        if (n > ONE_HUNDRED - 1) n = ONE_HUNDRED - 1; // Limit to max safe size

        uint256 availableValues = buf.tail >= buf.head
            ? buf.tail - buf.head
            : ONE_HUNDRED + buf.tail - buf.head;

        // Determine the number of values to retrieve
        uint256 valuesToRetrieve = n < availableValues ? n : availableValues;

        TokenPrices[] memory latestValues = new TokenPrices[](valuesToRetrieve);
        uint256 count = 0;

        int256 index = int256(buf.tail) - 1; // Start from tail and move backward

        while (count < valuesToRetrieve) {
            if (index < 0) index = int256(ONE_HUNDRED - 1); // Wrap around if negative
            latestValues[count] = buf.prices[uint256(index)];
            count++;
            index--;
        }

        return latestValues;
    }
}

// how to use:
// contract CircularBuffer {
//     using CircularBufferLib for CircularBufferLib.Buffer;
//     CircularBufferLib.Buffer private buffer;

//     function push(uint256 value) external {
//         buffer.push(value);
//     }

//     function getOrderedBuffer() external view returns (uint256[] memory) {
//         return buffer.getOrderedBuffer();
//     }

//     function getLatestNValues(
//         uint256 n
//     ) external view returns (uint256[] memory) {
//         return buffer.getLatestNValues(n);
//     }
// }
