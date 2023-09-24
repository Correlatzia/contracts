pragma solidity 0.8.19;

// a library for performing various math operations using numerical approximations
library NumericalMethods {
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    // babylonian method
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function getCorrelation(uint256[] memory x, uint256[] memory y) internal pure returns (int128 corr){
        uint256 numerator = getCovariance(x, y);
        uint256 denominator = getVariance(x) * getVariance(y);

        corr = numerator / denominator;
    }

    function getCovariance(uint256[] memory x, uint256[] memory y) internal pure returns (int128 covariance){
        require(x.length == y.length);
        int128 n = int128(x.length);
        // Step 1: Calculate the means (μX and μY) for X and Y:
        uint256 meanX = getMean(x);
        uint256 meanY = getMean(y);
        // Step 2: Subtract the means from each data point and calculate the product of the differences
        uint256 numerator;

        for(uint i = 0; i < n; i++){
            numerator += (x[i] - meanX) * (y[i] - meanY);
        }

        covariance = numerator/ n;

    }

    function getVariance(uint256[] memory data) pure internal returns (int128) {
        require(data.length > 1, "Input array must contain at least 2 elements");

        // Step 1: Calculate the mean (average) of the data
        uint256 mean = getMean(data);

        // Step 2: Calculate the sum of squared differences from the mean
        uint256 sumSquaredDifferences = 0;
        for (uint256 i = 0; i < data.length; i++) {
            uint256 difference = data[i] - mean;
            sumSquaredDifferences += uint256(difference * difference);
        }

        // Step 3: Calculate the variance
        uint256 variance = sumSquaredDifferences / (data.length - 1);

        return variance;
    }

    function getMean(uint256[] memory data) internal pure returns(uint256 mean){
        uint256 sum = 0;
        for (uint256 i = 0; i < data.length; i++) {
            sum += data[i];
        }
        mean = sum / uint256(data.length);
    }
}
