// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
/**
 * **** Data Conversions ****
 *
 * market (uint256)
 * --------------------------
 * Value    Type
 * --------------------------
 * 0        create
 * 1        resolve
 *
 */
/**
 * @title A consumer contract for Enetscores.
 * @author LinkPool.
 * @notice Interact with the daily events API.
 * @dev Uses @chainlink/contracts 0.4.2.
 */
contract EnetscoresConsumer is ChainlinkClient {
    using Chainlink for Chainlink.Request;
    using CBORChainlink for BufferChainlink.buffer;
    struct GameCreate {
        uint32 gameId;
        uint40 startTime;
        string homeTeam;
        string awayTeam;
    }
    struct GameResolve {
        uint32 gameId;
        uint8 homeScore;
        uint8 awayScore;
        string status;
    }
    mapping(bytes32 => bytes[]) public requestIdGames;
    error FailedTransferLINK(address to, uint256 amount);
    /**
     * @param _link the LINK token address.
     * @param _oracle the Operator.sol contract address.
     */
    constructor(address _link, address _oracle) {
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
    }
    /* ========== EXTERNAL FUNCTIONS ========== */
    function cancelRequest(
        bytes32 _requestId,
        uint256 _payment,
        bytes4 _callbackFunctionId,
        uint256 _expiration
    ) external {
        cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
    }
    /**
     * @notice Stores the scheduled games.
     * @param _requestId the request ID for fulfillment.
     * @param _result the games either to be created or resolved.
     */
    function fulfillSchedule(bytes32 _requestId, bytes[] memory _result)
        external
        recordChainlinkFulfillment(_requestId)
    {
        requestIdGames[_requestId] = _result;
    }
    /**
     * @notice Requests the tournament games either to be created or to be resolved on a specific date.
     * @dev Requests the 'schedule' endpoint. Result is an array of GameCreate or GameResolve encoded (see structs).
     * @param _specId the jobID.
     * @param _payment the LINK amount in Juels (i.e. 10^18 aka 1 LINK).
     * @param _market the number associated with the type of market (see Data Conversions).
     * @param _leagueId the tournament ID.
     * @param _date the starting time of the event as a UNIX timestamp in seconds.
     */
    function requestSchedule(
        bytes32 _specId,
        uint256 _payment,
        uint256 _market,
        uint256 _leagueId,
        uint256 _date
    ) external {
        Chainlink.Request memory req = buildOperatorRequest(_specId, this.fulfillSchedule.selector);
        req.addUint("market", _market);
        req.addUint("leagueId", _leagueId);
        req.addUint("date", _date);
        sendOperatorRequest(req, _payment);
    }
    /**
     * @notice Requests the tournament games either to be created or to be resolved on a specific date.
     * @dev Requests the 'schedule' endpoint. Result is an array of GameCreate or GameResolve encoded (see structs).
     * @param _specId the jobID.
     * @param _payment the LINK amount in Juels (i.e. 10^18 aka 1 LINK).
     * @param _market the context of the games data to be requested: `0` (markets to be created),
     * `1` (markets to be resolved).
     * @param _leagueId the tournament ID.
     * @param _date the date to request events by, as a UNIX timestamp in seconds.
     * @param _gameIds the list of game IDs to filter by for market `1`, otherwise the value is ignored.
     */
    function requestSchedule(
        bytes32 _specId,
        uint256 _payment,
        uint256 _market,
        uint256 _leagueId,
        uint256 _date,
        uint256[] calldata _gameIds
    ) external {
        Chainlink.Request memory req = buildOperatorRequest(_specId, this.fulfillSchedule.selector);
        req.addUint("market", _market);
        req.addUint("leagueId", _leagueId);
        req.addUint("date", _date);
        _addUintArray(req, "gameIds", _gameIds);
        sendOperatorRequest(req, _payment);
    }
    function setOracle(address _oracle) external {
        setChainlinkOracle(_oracle);
    }
    function setRequestIdGames(bytes32 _requestId, bytes[] memory _games) external {
        requestIdGames[_requestId] = _games;
    }
    function withdrawLink(address payable _payee, uint256 _amount) external {
        LinkTokenInterface linkToken = LinkTokenInterface(chainlinkTokenAddress());
        if (!linkToken.transfer(_payee, _amount)) {
            revert FailedTransferLINK(_payee, _amount);
        }
    }
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */
    function getGameCreate(bytes32 _requestId, uint256 _idx) external view returns (GameCreate memory) {
        return _getGameCreateStruct(requestIdGames[_requestId][_idx]);
    }
    function getGameResolve(bytes32 _requestId, uint256 _idx) external view returns (GameResolve memory) {
        return _getGameResolveStruct(requestIdGames[_requestId][_idx]);
    }
    function _getOracleAddress() external view returns (address) {
        return chainlinkOracleAddress();
    }
    /* ========== PRIVATE PURE FUNCTIONS ========== */
    function _addUintArray(
        Chainlink.Request memory _req,
        string memory _key,
        uint256[] memory _values
    ) private pure {
        Chainlink.Request memory r2 = _req;
        r2.buf.encodeString(_key);
        r2.buf.startArray();
        uint256 valuesLength = _values.length;
        for (uint256 i = 0; i < valuesLength; ) {
            r2.buf.encodeUInt(_values[i]);
            unchecked {
                ++i;
            }
        }
        r2.buf.endSequence();
        _req = r2;
    }
    function _getGameCreateStruct(bytes memory _data) private pure returns (GameCreate memory) {
        uint32 gameId = uint32(bytes4(_sliceDynamicArray(0, 4, _data)));
        uint40 startTime = uint40(bytes5(_sliceDynamicArray(4, 9, _data)));
        uint8 homeTeamLength = uint8(bytes1(_data[9]));
        uint256 endHomeTeam = 10 + homeTeamLength;
        string memory homeTeam = string(_sliceDynamicArray(10, endHomeTeam, _data));
        string memory awayTeam = string(_sliceDynamicArray(endHomeTeam, _data.length, _data));
        GameCreate memory gameCreate = GameCreate(gameId, startTime, homeTeam, awayTeam);
        return gameCreate;
    }
    function _getGameResolveStruct(bytes memory _data) private pure returns (GameResolve memory) {
        uint32 gameId = uint32(bytes4(_sliceDynamicArray(0, 4, _data)));
        uint8 homeScore = uint8(bytes1(_data[4]));
        uint8 awayScore = uint8(bytes1(_data[5]));
        string memory status = string(_sliceDynamicArray(6, _data.length, _data));
        GameResolve memory gameResolve = GameResolve(gameId, homeScore, awayScore, status);
        return gameResolve;
    }
    function _sliceDynamicArray(
        uint256 _start,
        uint256 _end,
        bytes memory _data
    ) private pure returns (bytes memory) {
        bytes memory result = new bytes(_end - _start);
        for (uint256 i = 0; i < _end - _start; ++i) {
            result[i] = _data[_start + i];
        }
        return result;
    }
}