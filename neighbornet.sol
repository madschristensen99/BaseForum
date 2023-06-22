// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract neighbornet is ERC20 {
    constructor() ERC20("NeighborNet", "NNET") {
        _mint(msg.sender, 100000000 * (10 ** uint256(decimals()))); // Mint 100 million tokens
    }
}

contract Tag is ERC721Enumerable {
    neighbornet public nnetContract;
    mapping(address => uint256) public lastMint;
    mapping(string => uint256) private _tagFees;
    mapping(string => address) private _tagOwners;

    constructor(address _nnetContract) ERC721("Tag", "TAG") {
        nnetContract = neighbornet(_nnetContract);
    }

    function mintTag(string memory tagId) public {
        // Require holding of at least one NNET token
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token");

        // Enforce a 24 hour period keeping an owner to minting max one per day
        require(block.timestamp >= lastMint[msg.sender] + 1 days, "You must wait 24 hours between mintings");
        lastMint[msg.sender] = block.timestamp;

        // Prevent duplicate tagIds
        require(_tagOwners[tagId] == address(0), "Tag ID already exists");

        _tagOwners[tagId] = msg.sender;
        _mint(msg.sender, uint256(keccak256(bytes(tagId))));
    }

    function setFee(string memory tagId, uint256 fee) public {
        require(_tagOwners[tagId] == msg.sender, "Not tag owner");
        _tagFees[tagId] = fee;
    }

    function getFee(string memory tagId) public view returns (uint256) {
        require(_tagOwners[tagId] != address(0), "Tag does not exist");
        return _tagFees[tagId];
    }

    function ownerOf(string memory tagId) public view returns (address) {
        address owner = _tagOwners[tagId];
        require(owner != address(0), "Tag does not exist");
        return owner;
    }
}

contract Forum {
    struct Post {
        address author;
        string content;
        mapping (string => uint) tags; // tags mapping updated here
        mapping (address => uint) upvotes;
        mapping (address => uint) downvotes;
    }

    Post[] public Forum;

    neighbornet public nnetContract;
    Tag public tagContract;

    constructor(address _nnetContract, address _tagContract) {
        nnetContract = neighbornet(_nnetContract);
        tagContract = Tag(_tagContract);
    }

    function createPost(string memory content) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token");
        Forum.push();
        Post storage p = Forum[Forum.length - 1];
        p.author = msg.sender;
        p.content = content;
    }

    function tagPost(uint256 postId, string memory tagId) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token");
        require(tagContract.ownerOf(tagId) != address(0), "Tag does not exist");

        uint256 fee = tagContract.getFee(tagId);
        if (tagContract.ownerOf(tagId) != msg.sender && fee > 0) {
            require(nnetContract.balanceOf(msg.sender) >= fee, "Not enough NNET tokens to add tag");
            nnetContract.transferFrom(msg.sender, tagContract.ownerOf(tagId), fee);
        }
        Post storage post = Forum[postId];
        post.tags[tagId] += 1;  // Increment the count of the tag on the post here
    }

        function removeTag(uint256 postId, string memory tagId) public {
        Post storage post = Forum[postId];
        require(post.author == msg.sender, "Only the post author can remove tags");
        post.tags[tagId] = 0;
    }

    function upvotePost(uint256 postId, uint256 amount) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token to vote");
        require(nnetContract.balanceOf(msg.sender) >= amount, "Not enough NNET tokens to upvote");
        Forum[postId].upvotes[msg.sender] += amount;
    }

    function downvotePost(uint256 postId, uint256 amount) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token to vote");
        require(nnetContract.balanceOf(msg.sender) >= amount, "Not enough NNET tokens to downvote");
        Forum[postId].downvotes[msg.sender] += amount;
    }

    function getPost(uint256 postId) public view returns (address, string memory) {
        Post storage post = Forum[postId];
        return (post.author, post.content);
    }

    function getVotes(uint256 postId) public view returns (uint) {
        return (postId);
    }

}
