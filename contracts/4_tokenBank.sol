// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./6_ITokenRecipient.sol";

contract tokenBank is ITokenRecipient, ReentrancyGuard, Ownable(msg.sender) {
    using SafeERC20 for IERC20;
    //用户地址=>代币地址=>金额
    mapping(address => mapping(address => uint256)) private _userTokenBalance;
    //代币地址=>合约储备总金额
    mapping(address => uint256) private _tokenReserves;
    //紧急暂停开关
    bool private _paused; 

    event depositEvent(address indexed user,address indexed token,uint256 amount);
    event withdrawEvent(address indexed to,address indexed token,uint256 value);
    event Paused(address account);
    event Unpaused(address account);

    error ZeroAmount();
    error InvalidTokenAddress();
    error InsufficientBalance();
    error TransferAddressError();
    error TransferFailed();
    error InsufficientContractBalance();
    error ContractPaused();

    // 暂停修饰器
    modifier whenNotPaused() {
        if (_paused) revert ContractPaused();
        _;
    }

    // 紧急暂停（仅管理员）
    function pause() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }


    function deposit(address _token, uint256 _amount) public nonReentrant whenNotPaused {
        if( _amount==0 ) revert ZeroAmount();
        if( _token==address(0) || _token.code.length==0 ) revert InvalidTokenAddress();
        
        IERC20 token = IERC20(_token);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        _userTokenBalance[msg.sender][_token] += _amount;
        _tokenReserves[_token] += _amount;

        emit depositEvent(msg.sender, _token, _amount);
    }

  
    function withdraw(address _token,uint256 _amount) public nonReentrant whenNotPaused {
        if( _amount==0 ) revert ZeroAmount();
        if( _token==address(0) || _token.code.length==0 ) revert InvalidTokenAddress();

        uint256 userBalance = _userTokenBalance[msg.sender][_token];
        if (userBalance < _amount) revert InsufficientBalance();

        IERC20 token = IERC20(_token);

        uint256 contractBalance = token.balanceOf(address(this));
        if (contractBalance < _amount) revert InsufficientContractBalance();

        token.safeTransfer(msg.sender,_amount);

        _userTokenBalance[msg.sender][_token] -= _amount;
        _tokenReserves[_token] -= _amount;

        emit withdrawEvent(msg.sender, _token, _amount);
    }

   function permitDeposit(
        address _token,
        address _owner,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant whenNotPaused {
        if( _value==0 ) revert ZeroAmount();
        if( _token==address(0) || _token.code.length==0 ) revert InvalidTokenAddress();
        
        IERC20Permit(_token).permit(_owner,address(this),_value,_deadline,_v,_r,_s);
        deposit(_token, _value);
    }


    function onTransferReceived(address _from,uint256 _amount) external nonReentrant whenNotPaused {
        if( _amount==0 ) revert ZeroAmount();
        if(_from==address(0) || _from.code.length!=0 ) revert TransferAddressError();
        if( msg.sender.code.length==0 ) revert InvalidTokenAddress();

        IERC20 token = IERC20(msg.sender);
        uint256 contractBalance = token.balanceOf(address(this));
        uint256 expectedReserve = _tokenReserves[msg.sender] + _amount;
        if (contractBalance < expectedReserve) revert TransferFailed();

        _userTokenBalance[_from][msg.sender] += _amount;
        _tokenReserves[msg.sender] = expectedReserve;

        emit depositEvent(_from, msg.sender, _amount);
    }

    // 查询函数
    function getUserBalance(address _user, address _token) external view returns (uint256) {
        return _userTokenBalance[_user][_token];
    }

    function getContractReserve(address _token) external view returns (uint256) {
        return _tokenReserves[_token];
    }

    function getContractBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}