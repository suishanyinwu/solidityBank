// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract tokenBank{
    //用户地址=>代币地址=>金额
    mapping(address =>mapping(address => uint)) userTokenBalance;

    event depositEvent(address user,address token,uint256 amount);
    event withdrawEvent(address to,address token,uint value);

    error WithdrawNotZero();
    error DepositNotZero();
    error TokenBalanceNotEnough();

    //存款
    function deposit(address _token,uint256 _amount) public {
        if(_amount==0) revert DepositNotZero();
        
        //代币
        IERC20 token = IERC20(_token);

        //查询用户授权给合约的余额
        if(_amount > token.allowance(msg.sender,address(this)) ) revert TokenBalanceNotEnough();
        
        //转账
        token.transferFrom(msg.sender, address(this), _amount);

        //信息存储到本地合约
        userTokenBalance[msg.sender][_token]+=_amount;
        emit depositEvent(msg.sender, _token, _amount);

    }

    //提款
    function withdraw(address _token,uint256 _amount) public {
        if(_amount==0) revert WithdrawNotZero();

        //代币
        IERC20 token = IERC20(_token);

        //查询用户给本合约的余额
        if( _amount > userTokenBalance[msg.sender][_token] ) revert TokenBalanceNotEnough();

        //更新本地余额
        userTokenBalance[msg.sender][_token]-=_amount;
        emit withdrawEvent(msg.sender,_token,_amount);

        //转账给用户
        token.transfer(msg.sender, _amount);
    }

    //离线签名授权
    function permitDeposit(
        address _token,
        address _owner,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public {
        IERC20Permit(_token).permit(_owner,address(this),_value,_deadline,_v,_r,_s);
        deposit(_token, _value);
    }
}