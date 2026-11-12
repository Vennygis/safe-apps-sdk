// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LIPIdentityEngine} from "../src/LIPIdentityEngine.sol";

contract LIPIdentityEngineTest is Test {
    LIPIdentityEngine internal engine;
    address internal admin = address(0xA11CE);
    address internal alice = address(0xB0B);

    function setUp() public {
        vm.prank(admin);
        engine = new LIPIdentityEngine(admin);
    }

    function _mint() internal returns (uint256 tokenId) {
        vm.prank(admin);
        tokenId = engine.mintIdentity(alice, "ipfs://identity/1");
    }

    function testMintStartsAtLevelFive() public {
        uint256 tokenId = _mint();
        assertEq(engine.ownerOf(tokenId), alice);
        assertEq(engine.levelOf(tokenId), 5);
        assertEq(engine.xpRequiredForNextLevel(tokenId), 100);
    }

    function testXPLevelUpDoublesNextThreshold() public {
        uint256 tokenId = _mint();
        vm.prank(admin);
        engine.grantExperience(tokenId, 100);
        vm.prank(alice);
        engine.levelUp(tokenId);

        assertEq(engine.levelOf(tokenId), 6);
        assertEq(engine.experienceOf(tokenId), 0);
        assertEq(engine.xpRequiredForNextLevel(tokenId), 200);
    }

    function testTraitRequiresLevelAndCanBeEquipped() public {
        uint256 tokenId = _mint();
        vm.prank(admin);
        uint256 traitId = engine.defineTrait(
            keccak256("AURA"),
            keccak256("AURA_SLOT"),
            "Silver Aura",
            "ipfs://traits/silver-aura",
            5,
            3
        );

        vm.prank(alice);
        engine.applyTrait(tokenId, traitId);
        assertEq(engine.tokenTraitInSlot(tokenId, keccak256("AURA_SLOT")), traitId);
    }

    function testAbilityLevelGateAndCooldown() public {
        uint256 tokenId = _mint();
        vm.prank(admin);
        uint256 abilityId = engine.defineAbility("Pulse", "ipfs://abilities/pulse", 5, 60);

        vm.prank(alice);
        engine.useAbility(tokenId, abilityId, keccak256("test-context"));

        vm.prank(alice);
        vm.expectRevert();
        engine.useAbility(tokenId, abilityId, keccak256("second-use"));
    }

    function testNonHolderCannotLevelUp() public {
        uint256 tokenId = _mint();
        vm.prank(admin);
        engine.grantExperience(tokenId, 100);
        vm.prank(admin);
        vm.expectRevert();
        engine.levelUp(tokenId);
    }
}
