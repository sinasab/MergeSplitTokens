/* solhint-disable avoid-low-level-calls, indent, no-inline-assembly */
/* This contract is copied from Spawner package: https://github.com/0age/Spawner */
pragma solidity >=0.8.13;

import "openzeppelin-contracts/utils/Create2.sol";

import "./ERC20Ownable.sol";

contract Spawner {

    address private _logicContract;

    /**
     * @notice set the logic contract address
     * @param _addr address of the logic contract
     */
    function _setLogicContract(address _addr) internal {
        _logicContract = _addr;
    }

    /**
     * @notice clone the logic contract, initialize it with the new name, symbol, decimals
     * @param token address of the underlying token, used as salt
     * @param name name to init the cloned MergeSplitERC20 with
     * @param symbol symbol to init the cloned MergeSplitERC20 with
     * @param decimals decimals to init the cloned MergeSplitERC20 with
     */
    function _cloneMergeSplitToken(address token, string memory name, string memory symbol, uint8 decimals) internal returns (address clone) {

        // calldata that will be supplied to the `DELEGATECALL` from the spawned contract 
        // to the logic contract during contract creation
        bytes memory initializationCalldata = abi.encodeWithSelector(
            ERC20Ownable(_logicContract).init.selector,
            name,
            symbol,
            decimals
        );

        bytes32 salt = keccak256(abi.encodePacked(token));

        // place the creation code and constructor args of the contract to spawn in memory
        bytes memory initCode = abi.encodePacked(
            type(Spawner).creationCode,
            abi.encode(_logicContract, initializationCalldata)
        );

        // spawn the contract using `CREATE2`
        return Create2.deploy(0, salt, initCode);
    }
}



/**
 * @title Spawn
 * @author 0age
 * @notice This contract provides creation code that is used by Spawner in order
 * to initialize and deploy eip-1167 minimal proxies for a given logic contract.
 * SPDX-License-Identifier: MIT
 */
// version: https://github.com/0age/Spawner/blob/1b342afda0c1ec47e6a2d65828a6ca50f0a442fe/contracts/Spawner.sol
contract Spawn {
    constructor(address logicContract, bytes memory initializationCalldata) payable {
        // delegatecall into the logic contract to perform initialization.
        (bool ok, ) = logicContract.delegatecall(initializationCalldata);
        if (!ok) {
            // pass along failure message from delegatecall and revert.
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }

        // place eip-1167 runtime code in memory.
        bytes memory runtimeCode = abi.encodePacked(
            bytes10(0x363d3d373d3d3d363d73),
            logicContract,
            bytes15(0x5af43d82803e903d91602b57fd5bf3)
        );

        // return eip-1167 code to write it to spawned contract runtime.
        assembly {
            return(add(0x20, runtimeCode), 45) // eip-1167 runtime code, length
        }
    }
}
