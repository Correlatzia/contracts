// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// CircularBuffer Library
library CircularBufferLib {
    struct Buffer {
        uint256[100] data;
        uint256 head;
        uint256 tail;
    }

    function push(Buffer storage buf, uint256 value) internal {
        buf.data[buf.tail] = value;
        buf.tail = (buf.tail + 1) % 100;

        if (buf.tail == buf.head) {
            buf.head = (buf.head + 1) % 100;
        }
    }

    function getOrderedBuffer(
        Buffer storage buf
    ) internal view returns (uint256[] memory) {
        uint256[] memory ordered = new uint256[100];
        uint256 count = 0;

        for (uint256 i = buf.head; i != buf.tail; i = (i + 1) % 100) {
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
        if (n > 100) n = 100; // Limit to max buffer size

        uint256 availableValues = buf.tail >= buf.head
            ? buf.tail - buf.head
            : 100 + buf.tail - buf.head;

        // Determine the number of values to retrieve
        uint256 valuesToRetrieve = n < availableValues ? n : availableValues;

        uint256[] memory latestValues = new uint256[valuesToRetrieve];
        uint256 count = 0;

        int256 index = int256(buf.tail) - 1; // Start from tail and move backward

        while (count < valuesToRetrieve) {
            if (index < 0) index = 99; // Wrap around if negative
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
