// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title LIPIdentityEngine
/// @notice ERC-721 identity engine with configurable traits, XP progression and level-gated abilities.
/// @dev Trait art and ability effects may be rendered/executed by a game client. This contract records
///      their authoritative IDs, requirements, cooldowns and events; it does not render art or execute
///      arbitrary off-chain game logic. USD pricing and payment rails are intentionally not hardcoded.
contract LIPIdentityEngine is ERC721URIStorage, Ownable2Step {
    uint32 public constant INITIAL_LEVEL = 5;
    uint32 public constant TRANSFORMATION_LEVEL = 100;
    uint32 public constant TRAIT_MILESTONE_INTERVAL = 500;

    uint256 public nextTokenId = 1;
    uint256 public baseXPForNextLevel = 100;

    struct TraitDefinition {
        bytes32 traitType;
        bytes32 slot;
        string value;
        string metadataURI;
        uint32 requiredLevel;
        uint8 rarity; // 1=common ... 5=legendary; presentation convention, not a price.
        bool enabled;
    }

    struct AbilityDefinition {
        string name;
        string metadataURI;
        uint32 requiredLevel;
        uint64 cooldownSeconds;
        bool enabled;
    }

    mapping(uint256 tokenId => uint32 level) public levelOf;
    mapping(uint256 tokenId => uint256 xp) public experienceOf;
    mapping(uint256 tokenId => uint256 xpRequired) public xpRequiredForNextLevel;
    mapping(uint256 tokenId => bool transformed) public isTransformed;
    mapping(uint256 tokenId => uint32 transformationCount) public transformationCount;

    uint256 public nextTraitId = 1;
    mapping(uint256 traitId => TraitDefinition definition) private traitDefinitions;
    mapping(uint256 tokenId => mapping(bytes32 slot => uint256 traitId)) public tokenTraitInSlot;
    mapping(uint256 tokenId => bytes32[] slots) private tokenTraitSlots;

    uint256 public nextAbilityId = 1;
    mapping(uint256 abilityId => AbilityDefinition definition) private abilityDefinitions;
    mapping(uint256 tokenId => mapping(uint256 abilityId => uint64 readyAt)) public abilityReadyAt;

    error InvalidRecipient();
    error InvalidToken();
    error InvalidAmount();
    error InvalidTrait();
    error TraitLevelLocked();
    error InvalidAbility();
    error AbilityLevelLocked();
    error AbilityOnCooldown(uint64 readyAt);
    error InsufficientExperience(uint256 available, uint256 required);
    error LevelLimitReached();

    event IdentityMinted(address indexed recipient, uint256 indexed tokenId, uint32 initialLevel);
    event ExperienceGranted(uint256 indexed tokenId, uint256 amount, uint256 totalExperience);
    event LevelAdvanced(uint256 indexed tokenId, uint32 previousLevel, uint32 newLevel, uint256 nextLevelXP);
    event TransformationUnlocked(uint256 indexed tokenId, uint32 level, uint32 transformationNumber);
    event TraitMilestoneReached(uint256 indexed tokenId, uint32 milestoneLevel);
    event TraitDefined(uint256 indexed traitId, bytes32 indexed traitType, bytes32 indexed slot, uint32 requiredLevel);
    event TraitApplied(uint256 indexed tokenId, uint256 indexed traitId, bytes32 indexed slot);
    event TraitRemoved(uint256 indexed tokenId, bytes32 indexed slot, uint256 previousTraitId);
    event AbilityDefined(uint256 indexed abilityId, string name, uint32 requiredLevel, uint64 cooldownSeconds);
    event AbilityStatusChanged(uint256 indexed abilityId, bool enabled);
    event AbilityUsed(uint256 indexed tokenId, uint256 indexed abilityId, address indexed user, bytes32 contextHash, uint64 nextReadyAt);
    event MetadataURIUpdated(uint256 indexed tokenId, string metadataURI);

    constructor(address initialOwner)
        ERC721("Lorem Ipsom Identity", "LIPID")
        Ownable(initialOwner)
    {
        if (initialOwner == address(0)) revert InvalidRecipient();
    }

    function mintIdentity(address recipient, string calldata metadataURI)
        external
        onlyOwner
        returns (uint256 tokenId)
    {
        if (recipient == address(0)) revert InvalidRecipient();

        tokenId = nextTokenId++;
        _safeMint(recipient, tokenId);
        _setTokenURI(tokenId, metadataURI);
        levelOf[tokenId] = INITIAL_LEVEL;
        xpRequiredForNextLevel[tokenId] = baseXPForNextLevel;

        emit IdentityMinted(recipient, tokenId, INITIAL_LEVEL);
    }

    /// @notice Authorized game/backend operator grants XP; XP is not directly purchasable here.
    function grantExperience(uint256 tokenId, uint256 amount) external onlyOwner {
        ownerOf(tokenId);
        if (amount == 0) revert InvalidAmount();
        experienceOf[tokenId] += amount;
        emit ExperienceGranted(tokenId, amount, experienceOf[tokenId]);
    }

    /// @notice Holder spends the current XP threshold to advance exactly one level.
    ///         The next threshold doubles, matching the current LIP progression rule.
    function levelUp(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert InvalidToken();
        uint32 previous = levelOf[tokenId];
        if (previous == type(uint32).max) revert LevelLimitReached();

        uint256 required = xpRequiredForNextLevel[tokenId];
        uint256 available = experienceOf[tokenId];
        if (available < required) revert InsufficientExperience(available, required);

        experienceOf[tokenId] = available - required;
        uint32 updated = previous + 1;
        levelOf[tokenId] = updated;
        uint256 nextRequired = required * 2;
        xpRequiredForNextLevel[tokenId] = nextRequired;

        emit LevelAdvanced(tokenId, previous, updated, nextRequired);

        if (previous < TRANSFORMATION_LEVEL && updated >= TRANSFORMATION_LEVEL) {
            isTransformed[tokenId] = true;
            transformationCount[tokenId] += 1;
            emit TransformationUnlocked(tokenId, updated, transformationCount[tokenId]);
        }

        if (updated % TRAIT_MILESTONE_INTERVAL == 0) {
            emit TraitMilestoneReached(tokenId, updated);
        }
    }

    function defineTrait(
        bytes32 traitType,
        bytes32 slot,
        string calldata value,
        string calldata metadataURI,
        uint32 requiredLevel,
        uint8 rarity
    ) external onlyOwner returns (uint256 traitId) {
        if (traitType == bytes32(0) || slot == bytes32(0) || bytes(value).length == 0) revert InvalidTrait();
        if (rarity < 1 || rarity > 5) revert InvalidTrait();

        traitId = nextTraitId++;
        traitDefinitions[traitId] = TraitDefinition({
            traitType: traitType,
            slot: slot,
            value: value,
            metadataURI: metadataURI,
            requiredLevel: requiredLevel,
            rarity: rarity,
            enabled: true
        });
        emit TraitDefined(traitId, traitType, slot, requiredLevel);
    }

    function setTraitEnabled(uint256 traitId, bool enabled) external onlyOwner {
        if (traitId == 0 || traitId >= nextTraitId) revert InvalidTrait();
        traitDefinitions[traitId].enabled = enabled;
    }

    /// @notice Holder equips one enabled trait per slot, provided its level requirement is met.
    function applyTrait(uint256 tokenId, uint256 traitId) external {
        if (ownerOf(tokenId) != msg.sender) revert InvalidToken();
        if (traitId == 0 || traitId >= nextTraitId) revert InvalidTrait();

        TraitDefinition storage trait = traitDefinitions[traitId];
        if (!trait.enabled) revert InvalidTrait();
        if (levelOf[tokenId] < trait.requiredLevel) revert TraitLevelLocked();

        bytes32 slot = trait.slot;
        if (tokenTraitInSlot[tokenId][slot] == 0) tokenTraitSlots[tokenId].push(slot);
        tokenTraitInSlot[tokenId][slot] = traitId;
        emit TraitApplied(tokenId, traitId, slot);
    }

    function removeTrait(uint256 tokenId, bytes32 slot) external {
        if (ownerOf(tokenId) != msg.sender) revert InvalidToken();
        uint256 previousTraitId = tokenTraitInSlot[tokenId][slot];
        if (previousTraitId == 0) return;

        delete tokenTraitInSlot[tokenId][slot];
        bytes32[] storage slots = tokenTraitSlots[tokenId];
        for (uint256 i = 0; i < slots.length; i++) {
            if (slots[i] == slot) {
                slots[i] = slots[slots.length - 1];
                slots.pop();
                break;
            }
        }
        emit TraitRemoved(tokenId, slot, previousTraitId);
    }

    function getTraitDefinition(uint256 traitId) external view returns (TraitDefinition memory) {
        if (traitId == 0 || traitId >= nextTraitId) revert InvalidTrait();
        return traitDefinitions[traitId];
    }

    function getTokenTraitSlots(uint256 tokenId) external view returns (bytes32[] memory) {
        ownerOf(tokenId);
        return tokenTraitSlots[tokenId];
    }

    function defineAbility(
        string calldata name,
        string calldata metadataURI,
        uint32 requiredLevel,
        uint64 cooldownSeconds
    ) external onlyOwner returns (uint256 abilityId) {
        if (bytes(name).length == 0) revert InvalidAbility();

        abilityId = nextAbilityId++;
        abilityDefinitions[abilityId] = AbilityDefinition({
            name: name,
            metadataURI: metadataURI,
            requiredLevel: requiredLevel,
            cooldownSeconds: cooldownSeconds,
            enabled: true
        });
        emit AbilityDefined(abilityId, name, requiredLevel, cooldownSeconds);
    }

    function setAbilityEnabled(uint256 abilityId, bool enabled) external onlyOwner {
        if (abilityId == 0 || abilityId >= nextAbilityId) revert InvalidAbility();
        abilityDefinitions[abilityId].enabled = enabled;
        emit AbilityStatusChanged(abilityId, enabled);
    }

    function getAbilityDefinition(uint256 abilityId) external view returns (AbilityDefinition memory) {
        if (abilityId == 0 || abilityId >= nextAbilityId) revert InvalidAbility();
        return abilityDefinitions[abilityId];
    }

    /// @notice Records an ability activation and enforces its cooldown.
    /// @dev contextHash can bind a game-server result or off-chain action receipt; it is not proof
    ///      that an external game action executed correctly.
    function useAbility(uint256 tokenId, uint256 abilityId, bytes32 contextHash) external {
        if (ownerOf(tokenId) != msg.sender) revert InvalidToken();
        if (abilityId == 0 || abilityId >= nextAbilityId) revert InvalidAbility();

        AbilityDefinition storage ability = abilityDefinitions[abilityId];
        if (!ability.enabled) revert InvalidAbility();
        if (levelOf[tokenId] < ability.requiredLevel) revert AbilityLevelLocked();

        uint64 readyAt = abilityReadyAt[tokenId][abilityId];
        if (block.timestamp < readyAt) revert AbilityOnCooldown(readyAt);

        uint64 nextReady = uint64(block.timestamp) + ability.cooldownSeconds;
        abilityReadyAt[tokenId][abilityId] = nextReady;
        emit AbilityUsed(tokenId, abilityId, msg.sender, contextHash, nextReady);
    }

    function updateMetadataURI(uint256 tokenId, string calldata metadataURI) external {
        if (ownerOf(tokenId) != msg.sender) revert InvalidToken();
        _setTokenURI(tokenId, metadataURI);
        emit MetadataURIUpdated(tokenId, metadataURI);
    }
}
