// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./6_ITokenRecipient.sol";

contract tokenBank is ITokenRecipient{
    using SafeERC20 for IERC20;
    //用户地址=>代币地址=>金额
    mapping(address => mapping(address => uint256)) userTokenBalance;
    //代币地址=>合约储备总金额
    mapping(address => uint256) tokenTotalReserves;

    event depositEvent(address user,address token,uint256 amount);
    event withdrawEvent(address to,address token,uint256 value);
    event tokenReservesChangeEvent(address token,uint256 oldReserves,uint256 newReserves);

    error AmountNotZero();
    error TokenTransferError();
    error TokenBalanceNotEnough();
    error TransferAddressError();
    error AddressNotToken();

    //存款
    function deposit(address _token,uint256 _amount) public {
        if( _amount==0 ) revert AmountNotZero();
        if( _token==address(0) || _token.code.length==0 ) revert AddressNotToken();
        
        IERC20 token = IERC20(_token);
        if( _amount > token.allowance(msg.sender,address(this)) ) revert TokenBalanceNotEnough();
        
        token.safeTransferFrom(msg.sender, address(this), _amount);

        _depositInformationChange(msg.sender, _token, _amount);

    }

    //存款-本地信息修改
    function _depositInformationChange(address _user,address _token,uint256 _amount) private {
        uint256 oldReserves = tokenTotalReserves[_token];
        uint256 newReserves = IERC20(_token).balanceOf(address(this));
        if( newReserves-oldReserves < _amount ) revert TokenTransferError();

        userTokenBalance[_user][_token]+=_amount;
        emit depositEvent(_user, _token, _amount);

        tokenTotalReserves[_token]=newReserves;
        emit tokenReservesChangeEvent(_token, oldReserves, newReserves);
    }

    //提款
    function withdraw(address _token,uint256 _amount) public {
        if(_amount==0) revert AmountNotZero();
        if(_token==address(0) || _token.code.length==0 ) revert AddressNotToken();
        
        IERC20 token = IERC20(_token);
        if( _amount > userTokenBalance[msg.sender][_token] ) revert TokenBalanceNotEnough();

        token.safeTransfer(msg.sender,_amount);

        _withdrawInformationChange(msg.sender, _token, _amount);
    }

    //提款-本地信息修改
    function _withdrawInformationChange(address _user,address _token,uint256 _amount) private {
        uint256 oldReserves = tokenTotalReserves[_token];
        uint256 newReserves = IERC20(_token).balanceOf(address(this));
        if( oldReserves - newReserves < _amount ) revert TokenTransferError();

        userTokenBalance[_user][_token]-=_amount;
        emit withdrawEvent(_user, _token, _amount);

        tokenTotalReserves[_token]=newReserves;
        emit tokenReservesChangeEvent(_token, oldReserves, newReserves);

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
        if(_amount==0) revert AmountNotZero();
        if(_from==address(0) || _from.code.length!=0 ) revert TransferAddressError();
        if( msg.sender.code.length==0 ) revert AddressNotToken();

        //更新本地信息
        _depositInformationChange(_from, msg.sender, _amount);
    }
}