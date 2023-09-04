// SPDX-License-Identifier: MIT

/*
This contract presents a decentralized forum where discussions are categorized using unique tags. The tokenomics of this system revolves around two tokens: talkOnlineToken (TALK) and TagContract (TAG).

TALK, an ERC20 token, serves as a membership token and is used as currency for certain actions. Holding at least one TALK token is a prerequisite to mint new tags, vote on posts, and tag posts. This increases the utility and potential demand for TALK tokens.

Tag, an ERC721 token, represents a unique topic in the forum. Each tag is unique and owned by an individual who can charge a fee for others to use it. This creates a unique monetization model for popular content creators or influencers who can mint tags early and gain financial benefits from their subsequent popularity. It also encourages early adoption and active participation in the community.

By aligning incentives, this contract encourages quality content creation, active voting (curating), and valuable tag creation, which may be beneficial for the growth and vibrancy of the online community.

The contract also enables the monetization of online behavior including credentials. For example, a highly upvoted post can demonstrate expertise in a particular field, which might enhance the author's reputation or job prospects. Creator rewards for quality engagement can be raised through tagging.
*/

// boilerplate
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

// initilize erc20 token add 24hr time lock
contract talkOnlineToken is ERC20 {

    mapping(address => uint256) public lastVoteTime;

    constructor() ERC20("Talk.Online", "TALK") {
        _mint(msg.sender, 100000000 * (10 ** uint256(decimals())));
    }

    function voteLock() public {
        lastVoteTime[msg.sender] = block.timestamp;
    }

    function canTransfer(address _from) public view returns (bool) {
        // Check if user has ever voted
        if (lastVoteTime[_from] == 0) {
            return true;
        }

        return (block.timestamp >= lastVoteTime[_from] + 1 days);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        require(canTransfer(sender), "Too soon since last participation");
        super._transfer(sender, recipient, amount);
    }
}

// initialize nft utilities for qualitative curation framework
contract Tag is ERC721Enumerable {

    talkOnlineToken public talkContract;

    struct TagDetails {
        uint256 ethFee;              // Fee in ETH to use this tag
        uint256 tokenRequirement;   // Amount of talkContract required to hold for using this tag
        mapping(address => bool) exemptedAccounts;
    }
    mapping(uint256 => TagDetails) public tags;
    mapping(address => uint256) public lastTagCreationTime;

    event TagCreated(string tag, address indexed owner);
    event TagFeeUpdated(string indexed tag, uint256 newEthFee);
    event TokenRequirementUpdated(string indexed tag, uint256 newTokenRequirement);
    event ExemptionStatusUpdated(string indexed tag, address indexed account, bool isExempted);

    constructor(address _talkContract) ERC721("TagToken", "TAG") {
        talkContract = talkOnlineToken(_talkContract);
    }

    uint256 public constant MAX_TAG_LENGTH = 256;
    uint256 public constant TAG_CREATION_INTERVAL = 1 hours;

    // fundraisers, ai art competitions.
    function createTag(string memory tagContent) public {
        require(talkContract.balanceOf(msg.sender) >= 10, "Must hold at least ten TALK tokens");
        uint256 tokenId = uint256(keccak256(bytes(tagContent)));
        require(ownerOf(tokenId) == address(0), "Tag already exists");
        require(bytes(tagContent).length <= MAX_TAG_LENGTH, "Tag name exceeds maximum length");
        require(block.timestamp >= lastTagCreationTime[msg.sender] + TAG_CREATION_INTERVAL, "You must wait for 1 hour between creating tags");
        talkContract.voteLock();

        _mint(msg.sender, uint256(keccak256(bytes(tagContent))));
        lastTagCreationTime[msg.sender] = block.timestamp;
        emit TagCreated(tagContent, msg.sender);
    }

    // paid messaging
    function updateTagFee(string memory tagContent, uint256 newEthFee) public {
        require(talkContract.balanceOf(msg.sender) > 0, "Must hold at least one TALK token");
        uint256 tokenId = uint256(keccak256(bytes(tagContent)));
        require(ownerOf(tokenId) != address(0), "Tag does not exist");
        require(ownerOf(tokenId) == msg.sender, "You are not the owner");
        
        tags[tokenId].ethFee = newEthFee;
        emit TagFeeUpdated(tagContent, newEthFee);
    }

    // high rollers club, increase quality of accounts
    function updateTokenRequirement(string memory tagContent, uint256 newTokenRequirement) public {
        uint256 tokenId = uint256(keccak256(bytes(tagContent)));
        require(ownerOf(tokenId) != address(0), "Tag does not exist");
        require(ownerOf(tokenId) == msg.sender, "You are not the owner");

        
        tags[tokenId].tokenRequirement = newTokenRequirement;
        emit TokenRequirementUpdated(tagContent, newTokenRequirement);
    }
    // permissioned system
    function exemptFromTagFee(string memory tagContent, address account) public {
        uint256 tokenId = uint256(keccak256(bytes(tagContent)));
        require(ownerOf(tokenId) != address(0), "Tag does not exist");
        require(ownerOf(tokenId) == msg.sender, "You are not the owner");
        require(!tags[tokenId].exemptedAccounts[account], "Account is already exempted");
        tags[tokenId].exemptedAccounts[account] = true;
        emit ExemptionStatusUpdated(tagContent, account, true);
    }

    // if it turns out you cant trust someone
    function removeExemptionFromTagFee(string memory tagContent, address account) public {
        uint256 tokenId = uint256(keccak256(bytes(tagContent)));
        require(ownerOf(tokenId) != address(0), "Tag does not exist");
        require(ownerOf(tokenId) == msg.sender, "You are not the owner");
        require(tags[tokenId].exemptedAccounts[account], "Account is not exempted");
        tags[tokenId].exemptedAccounts[account] = false;
        emit ExemptionStatusUpdated(tagContent, account, false);
    }

    function getFee(string memory tagContent) public view returns(uint256) {
        uint256 tokenId = uint256(keccak256(bytes(tagContent)));
        return tags[tokenId].ethFee;
    }

    function getTokenRequirement(string memory tagContent) public view returns(uint256) {
        uint256 tokenId = uint256(keccak256(bytes(tagContent)));
        return tags[tokenId].tokenRequirement;
    }

    function isExemptFromTagFee(string memory tagContent, address account) public view returns(bool) {
        uint256 tokenId = uint256(keccak256(bytes(tagContent)));
        return tags[tokenId].exemptedAccounts[account];
    }

    function getTagDetails(string memory tagContent) public view returns (uint256, uint256) {
        uint256 tokenId = uint256(keccak256(bytes(tagContent)));
        return (
            tags[tokenId].ethFee,
            tags[tokenId].tokenRequirement
        );
    }

}
// implement a forum which utilizes the features of the two previous contracts to initiate a forum managed by curation incentives
contract Forum {

    struct Post {
        address author;
        string content;
        mapping(address => mapping(uint => bool)) taggedByUser;
        uint [] replies;
        uint replyingTo;
        mapping(address => uint) upvotes;
        mapping(address => uint) downvotes;
        uint proScore;
        uint conScore;
    }

    Post[] public posts;

    talkOnlineToken public talkContract;
    Tag public tagContract;

    event PostCreated(address indexed author, string content, uint indexed replyingTo);
    event PostTagged(uint indexed postId, string indexed tagId, address indexed tagger);
    event PostEdited(uint indexed postId, string newContent);
    event PostLiked(uint indexed postID, address indexed liker);
    event PostDisliked(uint indexed postID, address indexed disliker);

    constructor(address _talkContract, address _tagContract) {
        talkContract = talkOnlineToken(_talkContract);
        tagContract = Tag(_tagContract);
        // Create an initial post
        Post storage newPost = posts.push();
        newPost.author = address(this); // Contract itself is the author of this post
        newPost.content = "Welcome to the Forum! Please follow the guidelines.";
        newPost.proScore = 0;
        newPost.conScore = 0;
    }

    function createPost(string calldata content, uint replyId) public {
        require(bytes(content).length > 0, "Content field cannot be empty");
        require(replyId < posts.length, "Invalid reply ID");
        Post storage newPost = posts.push();

        newPost.author = msg.sender;
        newPost.content = content;
        posts[replyId].replies.push(posts.length);
        newPost.replyingTo = replyId;
        newPost.proScore = 0;
        newPost.conScore = 0;


        emit PostCreated(msg.sender, content, replyId);
    }

    function tagPost(uint256 postId, string calldata tagContent) public {
        require(tagContract.ownerOf(uint256(keccak256(abi.encodePacked(tagContent)))) != address(0), "Tag does not exist");
        require(postId < posts.length, "Post does not exist");
        require(talkContract.balanceOf(msg.sender) >= tagContract.getTokenRequirement(tagContent), "Must hold more TALK token.");

        uint256 fee = tagContract.getFee(tagContent);


        if (tagContract.ownerOf(uint256(keccak256(abi.encodePacked(tagContent)))) != msg.sender && fee > 0 && !tagContract.isExemptFromTagFee(tagContent, msg.sender)) { 
            talkContract.transferFrom(msg.sender, tagContract.ownerOf(uint256(keccak256(abi.encodePacked(tagContent)))), fee);
        }
        posts[postId].taggedByUser[msg.sender][uint256(keccak256(abi.encodePacked(tagContent)))] = true;
        emit PostTagged(postId, tagContent, msg.sender);
    }

    function editPost(uint256 postId, string calldata updatedContent) public {
        require(talkContract.balanceOf(msg.sender) > 0, "Must hold at least one TALK token");
        require(postId < posts.length, "Post does not exist");
        require(posts[postId].author == msg.sender, "Only the author can edit the post");
        posts[postId].content = updatedContent;
        emit PostEdited(postId, updatedContent);
    }

    function upvotePost(uint256 postId) public {
        require(talkContract.balanceOf(msg.sender) > 0, "Must hold at least one TALK token to vote");
        require(posts[postId].upvotes[msg.sender] == 0, "Already upvoted");
        require(posts[postId].downvotes[msg.sender] == 0, "Cannot upvote and downvote simultaneously");
        require(posts[postId].author != msg.sender, "Author cannot vote on their own post");

        uint256 amount = talkContract.balanceOf(msg.sender);
        talkContract.voteLock();

        posts[postId].upvotes[msg.sender] = amount;
        posts[postId].proScore += amount;
        emit PostLiked(postId, msg.sender);

    }

    function downvotePost(uint256 postId) public {
        require(talkContract.balanceOf(msg.sender) > 0, "Must hold at least one TALK token to vote");
        require(posts[postId].downvotes[msg.sender] == 0, "Already downvoted");
        require(posts[postId].upvotes[msg.sender] == 0, "Cannot upvote and downvote simultaneously");
        require(posts[postId].author != msg.sender, "Author cannot vote on their own post");

        uint256 amount = talkContract.balanceOf(msg.sender);
        talkContract.voteLock();

        posts[postId].downvotes[msg.sender] = amount;
        posts[postId].conScore += amount;
        emit PostDisliked(postId, msg.sender);
    }
    function removeUpvote(uint256 postId) public {
        require(posts[postId].upvotes[msg.sender] > 0, "No upvote to remove");
        require(talkContract.balanceOf(msg.sender) >= posts[postId].upvotes[msg.sender], "Must hold at least as many TALK tokens as the upvotes you are removing");
        talkContract.voteLock();
        uint256 amount = posts[postId].upvotes[msg.sender];
        posts[postId].proScore -= amount;
        delete posts[postId].upvotes[msg.sender];
    }

    function removeDownvote(uint256 postId) public {
        require(posts[postId].downvotes[msg.sender] > 0, "No downvote to remove");
        require(talkContract.balanceOf(msg.sender) >= posts[postId].downvotes[msg.sender], "Must hold at least as many TALK tokens as the downvotes you are removing");
        talkContract.voteLock();
        uint256 amount = posts[postId].downvotes[msg.sender];
        posts[postId].conScore -= amount;
        delete posts[postId].downvotes[msg.sender];
    }

    function getPost(uint256 postId) public view returns (address, string memory, uint, uint, uint[] memory, uint) {
        require(postId < posts.length, "Post does not exist");

        Post storage p = posts[postId];
        return (p.author, p.content, p.proScore, p.conScore, p.replies, p.replyingTo);
    }

    function getForumLength() public view returns(uint) {
        return posts.length;
    }

    function getPostReplies(uint256 postId) public view returns (uint[] memory) {
        require(postId < posts.length, "Post does not exist");
        return posts[postId].replies;
    }
    function getPostReplyingTo(uint256 postId) public view returns (uint) {
        require(postId < posts.length, "Post does not exist");
        return posts[postId].replyingTo;
    }

    function getPostUpvotes(uint256 postId, address user) public view returns (uint) {
        require(postId < posts.length, "Post does not exist");
        return posts[postId].upvotes[user];
    }

    function getPostDownvotes(uint256 postId, address user) public view returns (uint) {
        require(postId < posts.length, "Post does not exist");
        return posts[postId].downvotes[user];
    }
    function getConScore(uint256 postId) public view returns (uint) {
        require(postId < posts.length, "Post does not exist");
        return posts[postId].conScore;
    }
    function getProScore(uint256 postId) public view returns (uint) {
        require(postId < posts.length, "Post does not exist");
        return posts[postId].proScore;
    }
    function createPostWithTag(string calldata content, uint replyId, string calldata tag) public {
        require(tagContract.ownerOf(uint256(keccak256(abi.encodePacked(tag)))) != address(0), "Tag does not exist");
        createPost(content, replyId);
        tagPost(posts.length - 1, tag); 
    }

}
