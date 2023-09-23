// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// CircularBuffer Library
library CircularBufferLib {
    constant uint256 ONE_HUNDRED = 100; // max 99 safe values

    struct Buffer {
        uint256[ONE_HUNDRED] data;
        uint256 head;
        uint256 tail;
    }

    function push(Buffer storage buf, uint256 value) internal {
        buf.data[buf.tail] = value;
        buf.tail = (buf.tail + 1) % ONE_HUNDRED;

        if (buf.tail == buf.head) {
            buf.head = (buf.head + 1) % ONE_HUNDRED;
        }
    }

    function getOrderedBuffer(
        Buffer storage buf
    ) internal view returns (uint256[] memory) {
        uint256[] memory ordered = new uint256[ONE_HUNDRED];
        uint256 count = 0;

        for (uint256 i = buf.head; i != buf.tail; i = (i + 1) % ONE_HUNDRED) {
            ordered[count] = buf.data[i];
            count++;
        }

        uint256[] memory trimmed = new uint256[count];
        for (uint256 j = 0; j < count; j++) {
            trimmed[j] = ordered[j];
        }

        return trimmed;
    }

    function getLatestNValues(
        Buffer storage buf,
        uint256 n
    ) internal view returns (uint256[] memory) {
        if (n > ONE_HUNDRED - 1) n = ONE_HUNDRED - 1; // Limit to max safe size

        uint256 availableValues = buf.tail >= buf.head
            ? buf.tail - buf.head
            : ONE_HUNDRED + buf.tail - buf.head;

        // Determine the number of values to retrieve
        uint256 valuesToRetrieve = n < availableValues ? n : availableValues;

        uint256[] memory latestValues = new uint256[valuesToRetrieve];
        uint256 count = 0;

        int256 index = int256(buf.tail) - 1; // Start from tail and move backward

        while (count < valuesToRetrieve) {
            if (index < 0) index = ONE_HUNDRED - 1; // Wrap around if negative
            latestValues[count] = buf.data[uint256(index)];
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
