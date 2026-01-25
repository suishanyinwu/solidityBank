// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./6_ITokenRecipient.sol";

error TransferFalse();
error AmountNotZero();
error AddressNotZero();

contract smartToken is ERC20{
    constructor(string memory name_,string memory symbol_) ERC20(name_,symbol_){

    }

    function transferAndCall(address bankAddress,uint256 amount) external  {
        if(amount == 0) revert AmountNotZero();
        if(bankAddress == address(0) || bankAddress.code.length == 0) revert AddressNotZero();

        //触发TokenBank的回调函数
        if(bankAddress.code.length > 0) ITokenRecipient(bankAddress).onTransferReceived(msg.sender,amount);

    }

}