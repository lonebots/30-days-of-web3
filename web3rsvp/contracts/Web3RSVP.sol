// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

//rsvp contract
contract Web3RSVP{
    struct CreateEvent {
        bytes32 eventId;
        string eventDataCID;
        address eventOwner;
        uint256 eventTimeStamp;
        uint256 deposit;
        uint256 maxCapacity;
        address[] confirmedRSVPs;
        address[] claimedRSVPs;
        bool paidOut;
    }
//mapping of eventId to event data
    mapping(bytes32 => CreateEvent) public idToEvent;

//function to create an event
function createNewEvent(
    uint256 eventTimeStamp,
    uint256 deposit,
    uint256 maxCapacity,
    string calldata eventDataCID
) external {
    bytes32 eventId = keccak256(abi.encodePacked(
        msg.sender,
        address(this),
        eventTimeStamp,
        deposit,
        maxCapacity
    ));

    address[] memory confirmedRSVPs;
    address[] memory claimedRSVPs;

    //this creates a new CreateEvent struct and adds it to the idToEvent mapping
    idToEvent[eventId] = CreateEvent(
        eventId,
        eventDataCID,
        msg.sender,
        eventTimeStamp,
        deposit,
        maxCapacity,
        confirmedRSVPs,
        claimedRSVPs,
        false
    );
}

//fucntion to create rsvp
function createNewRSVP (bytes32 eventId) external payable {
    // look up event from our mapping
    CreateEvent storage myEvent = idToEvent[eventId];

    // transfer deposit to our contract / require tha they send in enough ETH to cover the deposit requirement of this specific event
    require(msg.value == myEvent.deposit, "NOT ENOUGH");

    // require that the event hasn't already happened (<eventTimeStamp)
    require(block.timestamp <= myEvent.eventTimeStamp, "ALREADY HAPPENED");

    // make sure event is under max capacity
    require(
        myEvent.confirmedRSVPs.length < myEvent.maxCapacity,
        "This event has reached capcity");
    
    // require that msg.sender isn't already in myEvent.confirmedRSVPs AKA hasn't already RSVP'd
    for (uint256 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
        require(myEvent.confirmedRSVPs[i] != msg.sender, "ALREADY CONFIRMED");
    }

    myEvent.confirmedRSVPs.push(payable(msg.sender));
}


function confirmAttendee(bytes32 eventId, address attendee) public {
    // look up event from our struct using the eventId
    CreateEvent storage myEvent = idToEvent[eventId];

    // require that msg.sender is the owner of the event - only the host should be able to check people in
    require(msg.sender == myEvent.eventOwner, "NOT AUTHORIZED");

    // require that attendee trying to check in actually RSVP'd
    address rsvpConfirm;

    for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
        if(myEvent.confirmedRSVPs[i] == attendee){
            rsvpConfirm = myEvent.confirmedRSVPs[i];
        }
    }

    require(rsvpConfirm == attendee, "NO RSVP TO CONFIRM");


    // require that attendee is NOT already in the claimedRSVPs list AKA make sure they haven't already checked in
    for (uint8 i = 0; i < myEvent.claimedRSVPs.length; i++) {
        require(myEvent.claimedRSVPs[i] != attendee, "ALREADY CLAIMED");
    }

    // require that deposits are not already claimed by the event owner
    require(myEvent.paidOut == false, "ALREADY PAID OUT");

    // add the attendee to the claimedRSVPs list
    myEvent.claimedRSVPs.push(attendee);

    // sending eth back to the staker `https://solidity-by-example.org/sending-ether`
    (bool sent,) = attendee.call{value: myEvent.deposit}("");

    // if this fails, remove the user from the array of claimed RSVPs
    if (!sent) {
        myEvent.claimedRSVPs.pop();
    }

    require(sent, "Failed to send Ether");
}

//confirm as a whole group 
function confirmAllAttendees(bytes32 eventId) external {
    // look up event from our struct with the eventId
    CreateEvent memory myEvent = idToEvent[eventId];

    // make sure you require that msg.sender is the owner of the event
    require(msg.sender == myEvent.eventOwner, "NOT AUTHORIZED");

    // confirm each attendee in the rsvp array
    for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
        confirmAttendee(eventId, myEvent.confirmedRSVPs[i]);
    }
}

//function to send the unclaimed deposit to the event host / owner 
function withdrawUnclaimedDeposits(bytes32 eventId) external {
    // look up event
    CreateEvent memory myEvent = idToEvent[eventId];

    // check that the paidOut boolean still equals false AKA the money hasn't already been paid out
    require(!myEvent.paidOut, "ALREADY PAID");

    // check if it's been 7 days past myEvent.eventTimestamp
    require(
        block.timestamp >= (myEvent.eventTimestamp + 7 days),
        "TOO EARLY"
    );

    // only the event owner can withdraw
    require(msg.sender == myEvent.eventOwner, "MUST BE EVENT OWNER");

    // calculate how many people didn't claim by comparing
    uint256 unclaimed = myEvent.confirmedRSVPs.length - myEvent.claimedRSVPs.length;

    uint256 payout = unclaimed * myEvent.deposit;

    // mark as paid before sending to avoid reentrancy attack
    myEvent.paidOut = true;

    // send the payout to the owner
    (bool sent, ) = msg.sender.call{value: payout}("");

    // if this fails
    if (!sent) {
        myEvent.paidOut = false;
    }

    require(sent, "Failed to send Ether");

}

}
