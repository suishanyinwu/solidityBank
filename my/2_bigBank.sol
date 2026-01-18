// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./1_baseBank.sol";
import "./3_IBank.sol";

contract BigBank is EtherBank,IBank{

    uint8 public decimals = 18;

    error SmallTransfer();
    error NewAdminNotZero();

    //最低存款限制
    modifier transferValueLimit{
        if(msg.value< (1 * 10**decimals) / 1000){
            revert SmallTransfer();
        }
        _;
    }

    function deposit(address _from) public payable override transferValueLimit{
        super.deposit(_from);
    }

    //管理员权限转移
    function transferOwnership(address newAdmin) public onlyOwner{
        if(address(0) == newAdmin){
            revert NewAdminNotZero();
        }
        owner=newAdmin;
    }

    //转账功能
    function withdraw(address _to,uint _value) external payable{

    }

}