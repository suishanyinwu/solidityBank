// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./6_ITokenRecipient.sol";

contract tokenBank is ITokenRecipient{
    using SafeERC20 for IERC20;
    //用户地址=>代币地址=>金额
    mapping(address =>mapping(address => uint)) userTokenBalance;

    event depositEvent(address user,address token,uint256 amount);
    event withdrawEvent(address to,address token,uint value);

    error WithdrawNotZero();
    error DepositNotZero();
    error TokenBalanceNotEnough();
    error TransferAddressError();
    error AddressNotToken();

    //存款
    function deposit(address _token,uint256 _amount) public {
        if(_amount==0) revert DepositNotZero();
        if(_token==address(0) || _token.code.length==0 ) revert AddressNotToken();
        
        //代币
        IERC20 token = IERC20(_token);

        //查询用户授权给合约的余额
        if(_amount > token.allowance(msg.sender,address(this)) ) revert TokenBalanceNotEnough();
        
        //转账
        token.safeTransferFrom(msg.sender, address(this), _amount);

        //信息存储到本地合约
        userTokenBalance[msg.sender][_token]+=_amount;
        emit depositEvent(msg.sender, _token, _amount);

    }

    //提款
    function withdraw(address _token,uint256 _amount) public {
        if(_amount==0) revert WithdrawNotZero();
        if(_token==address(0) || _token.code.length==0 ) revert AddressNotToken();

        //代币
        IERC20 token = IERC20(_token);

        //查询用户给本合约的余额
        if( _amount > userTokenBalance[msg.sender][_token] ) revert TokenBalanceNotEnough();

        //更新本地余额
        userTokenBalance[msg.sender][_token]-=_amount;
        emit withdrawEvent(msg.sender,_token,_amount);

        //转账给用户
        token.safeTransfer(msg.sender, _amount);
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

    //回调函数
    function onTransferReceived(address _from,uint256 _amount) external {
        if(_amount==0) revert DepositNotZero();
        if(_from==address(0) || _from.code.length!=0 ) revert TransferAddressError();
        if( msg.sender.code.length==0 ) revert AddressNotToken();

        //代币
        IERC20 token = IERC20(msg.sender);

        //查询用户授权给合约的余额
        if(_amount > token.allowance(_from,address(this)) ) revert TokenBalanceNotEnough();
        
        //转账
        token.safeTransferFrom(_from, address(this), _amount);

        //更新本地余额
        userTokenBalance[_from][msg.sender]+=_amount;
        emit withdrawEvent(_from,msg.sender,_amount);
    }
}