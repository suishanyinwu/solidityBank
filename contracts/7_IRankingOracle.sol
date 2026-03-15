// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IRankingOracle
 * @dev 排行榜预言机接口，定义排行榜更新的标准方法
 */
interface IRankingOracle {
    
    function updateRanking(
        address _user,
        address[3] calldata _currentTop3,
        address _bankContract
    ) external returns (address[3] memory newTop3);

}