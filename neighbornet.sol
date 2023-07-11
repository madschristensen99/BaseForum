// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

// The NNET token contract
contract NeighborNet is ERC20 {
    constructor() ERC20("NeighborNet", "NNET") {
        _mint(msg.sender, 100000000 * (10 ** uint256(decimals()))); // Mint 100 million tokens
        // The initial minting of tokens establishes the total supply of tokens in the economy
        // This can create an incentive for early adoption if the token's value appreciates over time
    }
}

// The Tag contract which is a unique identifier for different topics
contract Tag is ERC721Enumerable {
    NeighborNet public nnetContract;
    mapping(address => uint256) public lastMint; // only mint every 24 hrs
    mapping(string => uint256) private _tagFees; // paid messaging & fundraising
    mapping(string => address) private _tagOwners; // account of ownership

    // Emit an event when a tag is minted
    event TagMinted(address indexed owner, string tagId);

    constructor(address _nnetContract) ERC721("Tag", "TAG") {
        nnetContract = NeighborNet(_nnetContract);
    }

    function mintTag(string memory tagId) public {
        // Require holding of at least one NNET token
        // This incentivizes users to acquire and hold NNET tokens, which can help drive the token's value
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token");

        // Enforce a 24 hour period keeping an owner to minting max one per day
        // This limits the rate at which new tags can enter the system, which can prevent the dilution of existing tags
        require(block.timestamp >= lastMint[msg.sender] + 1 days, "You must wait 24 hours between mintings");
        lastMint[msg.sender] = block.timestamp;

        // Prevent duplicate tagIds
        // This ensures the uniqueness of tags, which can make owning a popular tag more valuable
        require(_tagOwners[tagId] == address(0), "Tag ID already exists");

        _tagOwners[tagId] = msg.sender;
        _mint(msg.sender, uint256(keccak256(bytes(tagId))));
        emit TagMinted(msg.sender, tagId); // Emit an event when a new tag is minted
    }

    // Allow tag owners to set a fee for others to use their tag
    // This can create a secondary market for tags where popular tags can accrue value
    function setFee(string memory tagId, uint256 fee) public {
        require(_tagOwners[tagId] == msg.sender, "Not tag owner");
        _tagFees[tagId] = fee;
    }

    function getFee(string memory tagId) public view returns (uint256) {
        require(_tagOwners[tagId] != address(0), "Tag does not exist");
        return _tagFees[tagId];
    }

    function getOwnerOf(string memory tagId) public view returns (address) {
        address owner = _tagOwners[tagId];
        require(owner != address(0), "Tag does not exist");
        return owner;
    }
    function getTag(string memory tagId) public view returns (address, uint256) {
        return (getOwnerOf(tagId), getFee(tagId));
    }

}

// The main forum contract where posts are created, tagged, and voted on
contract Forum {

    struct Post {
        address author;
        string content;
        string [] tagWall; 
        mapping(address => uint) upvotes;
        mapping(address => uint) downvotes;
        uint netScore;
    }

    Post[] public posts;

    NeighborNet public nnetContract;
    Tag public tagContract;

    // Events that get emitted when posts are created and tagged
    event PostCreated(address indexed author, string content);
    event PostTagged(uint indexed postId, string tagId, address tagger);

    constructor(address _nnetContract, address _tagContract) {
        nnetContract = NeighborNet(_nnetContract);
        tagContract = Tag(_tagContract);
    }

    // Any user can create a post, but they need NNET tokens to tag or vote on posts
    // This incentivizes users to acquire NNET tokens, which can help drive the token's value
    function createPost(string memory content) public {
        posts.push();
        Post storage p = posts[posts.length - 1];
        p.author = msg.sender;
        p.content = content;
        emit PostCreated(msg.sender, content); // Emit an event when a post is created
    }

    // Tagging a post can require a fee if the tag is owned by someone else
    // This can create a secondary market for tags where popular tags can accrue value
    function tagPost(uint256 postId, string memory tagId) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token");
        require(tagContract.getOwnerOf(tagId) != address(0), "Tag does not exist");

        uint256 fee = tagContract.getFee(tagId);
        if (tagContract.getOwnerOf(tagId) != msg.sender && fee > 0) {
            require(nnetContract.balanceOf(msg.sender) >= fee, "Not enough NNET tokens to add tag");
            nnetContract.transferFrom(msg.sender, tagContract.getOwnerOf(tagId), fee);
        }

        posts[postId].tagWall.push(tagId);  // adds a new record for a posts tagWall
        emit PostTagged(postId, tagId, msg.sender); // Emit an event when a post is tagged
    }

    // Users can vote on posts with their NNET tokens
    // This creates a form of stakeholder voting where users with more tokens have more voting power
    function upvotePost(uint256 postId, uint256 amount) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token to vote");
        require(nnetContract.balanceOf(msg.sender) >= amount, "Not enough NNET tokens to upvote");
        require(posts[postId].upvotes[msg.sender] == 0, "Already upvoted");
        // TODO: require funds wern't recently sent, prevents folks from sending tokens to a new acct to inflate upvotes
        posts[postId].upvotes[msg.sender] += amount;
        posts[postId].netScore += amount;
    }

    function downvotePost(uint256 postId, uint256 amount) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token to vote");
        require(nnetContract.balanceOf(msg.sender) >= amount, "Not enough NNET tokens to downvote");
        require(posts[postId].downvotes[msg.sender] == 0, "Already downvoted");
        // TODO: require funds wern't recently sent, prevents folks from sending tokens to a new acct to inflate downvotes
        posts[postId].downvotes[msg.sender] += amount;
        posts[postId].netScore -= amount;
    }
    function deletePost(uint256 postId) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token to alter community data");
        require(postId < posts.length, "Post does not exist");
        require(posts[postId].author == msg.sender, "Only the author can delete the post");
        delete posts[postId];
    }
    function getPost(uint256 postId) public view returns (address, string memory, uint, string[] memory) {
        require(postId < posts.length, "Post does not exist");
        return (posts[postId].author, posts[postId].content, posts[postId].netScore, posts[postId].tagWall);
    }


}
