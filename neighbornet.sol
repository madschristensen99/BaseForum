// SPDX-License-Identifier: MIT
/*
This contract presents a decentralized forum where discussions are categorized using unique tags. The tokenomics of this system revolves around two tokens: NeighborNet (NNET) and Tag.

NNET, an ERC20 token, serves as a membership token and is used as currency for certain actions. Holding at least one NNET token is a prerequisite to mint new tags, vote on posts, and tag posts. This increases the utility and potential demand for NNET tokens.

Tag, an ERC721 token, represents a unique topic in the forum. Each tag is unique and owned by an individual who can charge a fee for others to use it. This creates a unique monetization model for popular content creators or influencers who can mint tags early and gain financial benefits from their subsequent popularity. It also encourages early adoption and active participation in the community.

By aligning incentives, this contract encourages quality content creation, active voting (curating), and valuable tag creation, which may be beneficial for the growth and vibrancy of the online community.

The contract also enables the monetization of online behavior including credentials. For example, a highly upvoted post can demonstrate expertise in a particular field, which might enhance the author's reputation or job prospects. Creator rewards for quality engagement can be raised through tagging.
*/
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

    // we can't have somebody who upvotes what they like then sends their money to an account they also control then upvote the same post again. 
    // So we created a rule: after you vote on a post, there's a 24 hour lock on your tokens. Maybe it should be a week idk.
    // but this caused an issue: you cant pay to tag a post if youve recently upvoted, so you are left out of part of the economy.
    mapping(address => uint256) public lastUpvote;

    function getLastVoteTime(address _voter) public view returns (uint256) {
        return lastUpvote[_voter];
    }

    function lockAfterVote() public {
        lastUpvote[msg.sender] = block.timestamp;
    }

    function canTransfer(address _from) public view returns (bool) {
        return (block.timestamp >= lastUpvote[_from] + 1 days);
    }

}

// The Tag contract which is a unique identifier for different topics
contract Tag is ERC721Enumerable {
    NeighborNet public nnetContract;
    mapping(address => uint256) public lastMint; // only mint every 24 hrs
    mapping(string => uint256) private _tagFees; // paid messaging, fundraising, creator reward fund
    mapping(string => address) private _tagOwners; // account of ownership
    mapping(string => mapping(address => bool)) private _tagFeeExemptions; // tag fee exemptions

    // Getter for the `lastMint` mapping
    function getLastMint(address _account) public view returns (uint256) {
        return lastMint[_account];
    }

    // Getter for the `_tagFees` mapping
    function getTagFee(string memory _tagId) public view returns (uint256) {
        return _tagFees[_tagId];
    }
    function getOwnerOf(string memory tagId) public view returns (address) {
        address owner = _tagOwners[tagId];
        require(owner != address(0), "Tag does not exist");
        return owner;
    }

    // Emit an event when a tag is minted
    event TagMinted(address indexed owner, string tagId);

    constructor(address _nnetContract) ERC721("Tag", "TAG") {
        nnetContract = NeighborNet(_nnetContract);
    }
    mapping(string => uint256[]) private _tagPosts;

    function getTagPosts(string memory tagId) public view returns (uint256[] memory) {
        return _tagPosts[tagId];
    }

    function exemptFromTagFee(string memory tagId, address user) public {
        require(_tagOwners[tagId] == msg.sender, "Only the tag owner can exempt users from the tag fee");
        _tagFeeExemptions[tagId][user] = true;
    }

    function revokeTagFeeExemption(string memory tagId, address user) public {
        require(_tagOwners[tagId] == msg.sender, "Only the tag owner can revoke tag fee exemptions");
        _tagFeeExemptions[tagId][user] = false;
    }
    function isExemptFromTagFee(string memory tagId, address user) public view returns (bool) {
        return _tagFeeExemptions[tagId][user];
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
        nnetContract.lockAfterVote();
        _tagOwners[tagId] = msg.sender; // makes function caller the owner
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
    // retrieve a tag's content
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
        uint proScore;
        uint conScore;
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
    // This incentivizes users to acquire NNET tokens while being open to new members
    function createPost(string memory content) public {
        require(bytes(content).length > 0, "Content field cannot be empty");
        posts.push();
        Post storage p = posts[posts.length - 1];
        p.author = msg.sender;
        p.content = content;
        emit PostCreated(msg.sender, content); // Emit an event when a post is created
    }
    // MAJOR TODO: bug where somebody cannot tag a post with a fee if they have posted recently because they cannot transfer their tokens now
    // Tagging a post can require a fee if the tag is owned by someone else
    // This can create a secondary market for tags where popular tags can accrue value
    function tagPost(uint256 postId, string memory tagId) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token");
        require(tagContract.getOwnerOf(tagId) != address(0), "Tag does not exist");
        require(postId < posts.length, "Post does not exist");
        uint256 fee = tagContract.getFee(tagId);
    
        // Check if the user tagging is not the owner, fee is not zero, and user is not exempted from fee
        if (tagContract.getOwnerOf(tagId) != msg.sender && fee > 0 && !tagContract.isExemptFromTagFee(tagId, msg.sender)) { 
            require(nnetContract.balanceOf(msg.sender) >= fee, "Not enough NNET tokens to add tag");
            nnetContract.transferFrom(msg.sender, tagContract.getOwnerOf(tagId), fee);
        }

        // Add the tag to the post
        posts[postId].tagWall.push();
        posts[postId].tagWall[posts[postId].tagWall.length - 1] = tagId;
        emit PostTagged(postId, tagId, msg.sender);
    }
    // Remove an upvote from a post
    function removeUpvotePost(uint256 postId, uint256 amount) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token to vote");
        require(posts[postId].upvotes[msg.sender] >= amount, "You have not upvoted this post with the amount specified");


        // Decrease the upvotes count for the post
        posts[postId].upvotes[msg.sender] -= amount;
        posts[postId].proScore -= amount;
    }

    // Remove a downvote from a post
    function removeDownvotePost(uint256 postId, uint256 amount) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token to vote");
        require(posts[postId].downvotes[msg.sender] >= amount, "You have not downvoted this post with the amount specified");

        // Decrease the downvotes count for the post
        posts[postId].downvotes[msg.sender] -= amount;
        posts[postId].conScore -= amount;
    }

    // Users can vote on posts with their NNET tokens
    // This creates a form of stakeholder voting where users with more tokens have more voting power
    function upvotePost(uint256 postId, uint256 amount) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token to vote");
        require(posts[postId].upvotes[msg.sender] == 0, "Already upvoted");
        require(posts[postId].downvotes[msg.sender] == 0, "Cannot upvote and downvote simultaneously");
        nnetContract.lockAfterVote();
        posts[postId].upvotes[msg.sender] += amount;
        posts[postId].proScore += amount;
    }

    function downvotePost(uint256 postId, uint256 amount) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token to vote");
        require(posts[postId].downvotes[msg.sender] == 0, "Already downvoted");
        require(posts[postId].upvotes[msg.sender] == 0, "Cannot upvote and downvote simultaneously");
        nnetContract.lockAfterVote();
        posts[postId].downvotes[msg.sender] += amount;
        posts[postId].conScore += amount;
    }
    // Create a post with associated tags
    function createPostWithTag(string memory content, string[] memory tagIds) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token");

        // Create the post
        createPost(content);
        // Emit an event when a post is created
        emit PostCreated(msg.sender, content);

        // Loop over the provided tags and add them to the post
        for(uint i = 0; i < tagIds.length; i++){
            // Tag the post
            tagPost(posts.length - 1, tagIds[i]);
        }
    }

    // removes post content
    function deletePost(uint256 postId) public {
        require(nnetContract.balanceOf(msg.sender) > 0, "Must hold at least one NNET token to alter community data");
        require(postId < posts.length, "Post does not exist");
        require(posts[postId].author == msg.sender, "Only the author can delete the post");
        posts[postId].content = "";
    }
    // retrieves information about a post
    function getPost(uint256 postId) public view returns (address, string memory, uint, uint, string[] memory) {
        require(postId < posts.length, "Post does not exist");
        return (posts[postId].author, posts[postId].content, posts[postId].proScore, posts[postId].conScore, posts[postId].tagWall);
    }
    // getters about a post
    function getForumLength() public view returns(uint){
        return posts.length;
    }

}
