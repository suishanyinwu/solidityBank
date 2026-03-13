// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IBank {
    function withdraw(address _to,uint _value) external;
}